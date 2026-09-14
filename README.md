# Madrid calendar feeds

Two auto-updating iCalendar (`.ics`) feeds for Madrid: official non-working days,
and the Comunidad de Madrid school calendar.

**Just want to subscribe? → [calendar.lemambo.com](https://calendar.lemambo.com)**

## Subscribe

Paste either `webcal://` URL into any calendar app, or open it on a device where
Apple Calendar is set up and it will offer to subscribe.

**Madrid holidays** — national, regional, and Ayuntamiento de Madrid local holidays.

```
webcal://calendar.lemambo.com/madrid-festivos.ics
```

**Calendario escolar Comunidad de Madrid** — the official 2026-27 school year.

```
webcal://calendar.lemambo.com/calendario-escolar-comunidad-madrid.ics
```

Both are also reachable over plain HTTPS
([holidays](https://calendar.lemambo.com/madrid-festivos.ics),
[school](https://calendar.lemambo.com/calendario-escolar-comunidad-madrid.ics))
and tracked in [`docs/`](docs/).

## What's in the feeds

The holiday feed combines national holidays, Comunidad de Madrid regional
holidays, and the local holidays set by the Ayuntamiento de Madrid.

The school feed covers holidays, non-teaching days, ordinary final assessments,
review days, and the start and end dates of each listed teaching period.
Saturdays and Sundays are omitted: the source marks every weekend as a
non-teaching day, which adds no information to a subscribed calendar.

---

## Sources and updates

The holiday feed comes from the Ayuntamiento de Madrid's [Calendario laboral
open-data dataset](https://datos.madrid.es/dataset/300082-0-calendario_laboral),
licensed under CC BY 4.0. The school feed comes from EducaMadrid's [Calendario
escolar 26-27](https://www.educa2.madrid.org/web/calendario-escolar-de-la-comunidad-de-madrid/calendario-escolar-26-27).

The GitHub Actions workflow runs on the 1st and 15th of every month, fetches the
currently published sources, and refreshes both calendars. It can also be started
by hand from the repository's Actions tab, or with
`gh workflow run "Update Madrid Calendar Feeds"`. Each feed is built in its own
step, so a failure in one does not discard the other's refresh.

The school feed is **not** fetched. It is generated from the archived copy of the
source page in `resources/`, refreshed by hand once per school year.

### Why the school calendar is not fetched automatically

EducaMadrid blocks access from outside Spain, and GitHub's hosted runners are not
in Spain. Probed from a runner, every request returns a byte-identical stock
Apache 403 - script user agent, browser user agent, no user agent, a full browser
header set, HTTP/1.1, a same-site referer, and load-balancer cookies established
on the root path. `external.educa2.madrid.org`, EducaMadrid's own documented host
for access from outside Spain, returns 403 as well. So does the Internet Archive,
whose only two captures of the page are the 403 page itself, and so do public
fetch proxies. The rejection is address-based; nothing on the client side reaches
it.

Getting through would mean paying for a Spanish egress - a VPS, a scraping API
with country targeting, or a cloud function in a Spanish region - to re-download a
document that changes once a year. That is not worth the cost, the credential, or
the extra way for the pipeline to fail quietly, so the generator does not try.

The full probe matrix is recorded at the top of
[`.github/workflows/diagnose-educamadrid.yml`](.github/workflows/diagnose-educamadrid.yml).
That workflow is manual-only; run it if you want to check whether the block has
lifted.

## Implementation

A Swift package. Run everything from the repository root:

```
swift test                          # 21 tests, no network
swift run GenerateHolidayFeed       # refresh docs/madrid-festivos.ics
swift run GenerateSchoolFeed        # refresh the school feed from the archive
swift run RefreshSchoolArchive      # check the live page (Spain only, see below)
```

| Target | What it is |
| --- | --- |
| `CalendarFeedCore` | Shared iCalendar plumbing: UTC dates, escaping, stable UIDs |
| `HolidayCalendar` | CKAN fetching plus pure ICS parsing and generation |
| `SchoolCalendar` | Pure parsing of the archived page. No networking at all |
| `GenerateHolidayFeed` | Writes `docs/madrid-festivos.ics` |
| `GenerateSchoolFeed` | Writes `docs/calendario-escolar-comunidad-madrid.ics` |
| `RefreshSchoolArchive` | Local-only tool to update `resources/` when the source changes |

Parsing and generation are pure functions, so the tests run the same code the
generators do, against the real archived page rather than a synthetic fixture.
No mocking is involved. CI runs `swift test` before generating anything, so a
broken parser cannot publish a truncated feed.

### Refreshing the archive locally

CI cannot reach EducaMadrid, but a Spanish connection can, so checking for
changes is a local job:

```
swift run RefreshSchoolArchive           # fetch, compare, report; changes nothing
swift run RefreshSchoolArchive --write   # update resources/ and regenerate the feed
```

It compares the live page against the archive by **parsed events**, not raw
bytes - Liferay varies about 60 bytes of page chrome between requests, so a byte
comparison reports a difference every time. It exits 0 when nothing changed, 2
when something did, and prints exactly which events were added or removed.

Event UIDs are built from the date plus an internal identifier, never from the
displayed title, so rewording a title does not force subscribers' calendar apps
to delete and recreate every event.

The 2026-27 source page is preserved in
[`resources/calendario-escolar-26-27.html`](resources/calendario-escolar-26-27.html)
and is the source the feed is built from. When the 2027-28 calendar is published,
save the new page there and update `archivePath` and `sourceURL` in
[`Sources/SchoolCalendar/SchoolCalendar.swift`](Sources/SchoolCalendar/SchoolCalendar.swift).
Saving it has to be done from a Spanish connection, for the reason described
above - `swift run RefreshSchoolArchive --write` does it for you.

You do not have to remember to check. The
[`Check for next school year`](.github/workflows/check-next-school-year.yml)
workflow runs monthly, watches the Comunidad de Madrid [calendar listing
page](https://www.comunidad.madrid/educacion/calendario-escolar), and **fails on
purpose** when it finds a calendar newer than the one the generator tracks. A red
run there is a reminder to re-archive, not a breakage. It also fails if the
listing becomes unreadable, since a silent alarm is worse than a noisy one.
