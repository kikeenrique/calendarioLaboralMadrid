#!/usr/bin/env python3
"""
Build an auto-updating ICS feed of Madrid (city) non-working days
("días festivos / no laborables") from the Ayuntamiento de Madrid's
official open-data portal.

Source: https://datos.madrid.es/dataset/300082-0-calendario_laboral
This dataset already scopes the holidays to the ciudad de Madrid
(national + Comunidad de Madrid regional + the 2 local festivos of
the capital), so no extra filtering by region is required.

Instead of hardcoding per-year resource IDs (which the portal assigns
unpredictably each year -- e.g. 2024, 2025 and 2026 all have different,
non-sequential IDs), this script asks the CKAN "package_show" API for
the current list of resources in the dataset, finds every resource
published in ICS format, downloads each one, and merges them into a
single combined calendar. New years therefore get picked up
automatically the moment the Ayuntamiento publishes them -- no code
changes needed.

Usage:
    python fetch_and_build.py

Writes:
    docs/madrid-festivos.ics
"""
from __future__ import annotations

import datetime as dt
import re
import sys
from pathlib import Path

import requests

PACKAGE_ID = "300082-0-calendario_laboral"
PACKAGE_SHOW_URL = f"https://datos.madrid.es/api/3/action/package_show?id={PACKAGE_ID}"

# Keep a rolling window so the feed doesn't grow forever with stale
# past years, but still shows last year for reference.
KEEP_YEARS_BACK = 1

OUTPUT_PATH = Path(__file__).parent / "docs" / "madrid-festivos.ics"

HEADERS = {
    # Identify ourselves honestly. This hits the documented open-data
    # JSON API (meant for programmatic reuse), not the HTML site.
    "User-Agent": (
        "MadridFestivosFeedBot/1.0 "
        "(+https://github.com/YOUR_GITHUB_USERNAME/madrid-holidays-feed; "
        "auto-updating .ics mirror of datos.madrid.es open data)"
    ),
    "Accept": "application/json",
}


class HolidayFetchError(RuntimeError):
    pass


def get_dataset_resources() -> list[dict]:
    resp = requests.get(PACKAGE_SHOW_URL, headers=HEADERS, timeout=30)
    resp.raise_for_status()
    payload = resp.json()
    if not payload.get("success"):
        raise HolidayFetchError(f"CKAN package_show did not succeed: {payload}")
    return payload["result"]["resources"]


def select_ics_resources(resources: list[dict]) -> list[dict]:
    """Pick every resource that is an ICS-format 'solo festivos' calendar."""
    picked = []
    for r in resources:
        fmt = (r.get("format") or "").upper()
        name = r.get("name") or ""
        if fmt == "ICS" and "festivos" in name.lower():
            picked.append(r)
    if not picked:
        raise HolidayFetchError(
            "No ICS resources found in the dataset -- the portal's "
            "resource naming/format may have changed; inspect "
            f"{PACKAGE_SHOW_URL} manually."
        )
    return picked


def unfold_ics(text: str) -> list[str]:
    """RFC5545 line unfolding: continuation lines start with a space/tab."""
    raw_lines = text.replace("\r\n", "\n").split("\n")
    lines: list[str] = []
    for line in raw_lines:
        if line.startswith((" ", "\t")) and lines:
            lines[-1] += line[1:]
        else:
            lines.append(line)
    return lines


def parse_vevents(ics_text: str) -> list[dict]:
    """Very small, dependency-free VEVENT parser -- good enough for the
    simple all-day holiday events this dataset publishes."""
    events = []
    current: dict | None = None
    for line in unfold_ics(ics_text):
        if line.strip() == "BEGIN:VEVENT":
            current = {}
        elif line.strip() == "END:VEVENT":
            if current and "date" in current and "summary" in current:
                events.append(current)
            current = None
        elif current is not None and ":" in line:
            key, _, value = line.partition(":")
            key_name = key.split(";")[0].upper()
            if key_name == "DTSTART":
                m = re.search(r"(\d{8})", value)
                if m:
                    current["date"] = m.group(1)
            elif key_name == "SUMMARY":
                current["summary"] = value.strip()
    return events


def fetch_all_holidays() -> dict[str, str]:
    """Returns {YYYYMMDD: summary}, de-duplicated across resources."""
    resources = get_dataset_resources()
    ics_resources = select_ics_resources(resources)

    holidays: dict[str, str] = {}
    fetched_names = []
    for res in ics_resources:
        url = res.get("url")
        if not url:
            continue
        try:
            r = requests.get(url, headers=HEADERS, timeout=30)
            r.raise_for_status()
        except requests.RequestException as e:
            print(f"  ! skipping {res.get('name')} ({url}): {e}", file=sys.stderr)
            continue
        events = parse_vevents(r.text)
        for ev in events:
            holidays[ev["date"]] = ev["summary"]
        fetched_names.append(f"{res.get('name')} [{len(events)} events]")

    print("Fetched resources:")
    for n in fetched_names:
        print(f"  - {n}")

    if not holidays:
        raise HolidayFetchError("Downloaded ICS resources but found zero events.")

    return holidays


def build_combined_ics(holidays: dict[str, str]) -> str:
    this_year = dt.date.today().year
    min_year = this_year - KEEP_YEARS_BACK

    now_stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//madrid-holidays-feed//github-actions//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:Madrid - Dias No Laborables",
        "X-WR-CALDESC:Festivos oficiales de la ciudad de Madrid (nacional + auton"
        "omico Comunidad de Madrid + locales). Fuente: datos.madrid.es (Ayuntami"
        "ento de Madrid). Generado automaticamente.",
        "X-WR-TIMEZONE:Europe/Madrid",
        "X-PUBLISHED-TTL:P30D",
        "REFRESH-INTERVAL;VALUE=DURATION:P30D",
    ]

    for date_str in sorted(holidays):
        year = int(date_str[:4])
        if year < min_year:
            continue
        summary = holidays[date_str]
        start = date_str
        end_date = dt.date(year, int(date_str[4:6]), int(date_str[6:8])) + dt.timedelta(days=1)
        end = end_date.strftime("%Y%m%d")
        uid = f"{start}-madrid-festivo@madrid-holidays-feed"
        lines += [
            "BEGIN:VEVENT",
            f"UID:{uid}",
            f"DTSTAMP:{now_stamp}",
            f"DTSTART;VALUE=DATE:{start}",
            f"DTEND;VALUE=DATE:{end}",
            f"SUMMARY:{summary}",
            "DESCRIPTION:Fuente oficial: datos.madrid.es (Ayuntamiento de Madrid)",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
        ]

    lines.append("END:VCALENDAR")
    return "\r\n".join(lines) + "\r\n"


def main() -> int:
    try:
        holidays = fetch_all_holidays()
    except HolidayFetchError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    ics_text = build_combined_ics(holidays)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(ics_text, encoding="utf-8")
    print(f"\nWrote {OUTPUT_PATH} with {ics_text.count('BEGIN:VEVENT')} events.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
