# Implementation

A Swift package. Run everything from the repository root.

```
swift test                          # 35 tests, no network
swift run GenerateHolidayFeed       # refresh docs/madrid-festivos.ics
swift run GenerateSchoolFeed        # refresh the school feed from the archive
swift run RefreshSchoolArchive      # check the live page (Spain only)
```

## Targets

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
No mocking is involved.

## Decisions worth knowing

**UIDs never depend on displayed text.** They are the date plus a digest of an
internal identifier, so rewording a title does not make subscribers' calendar
apps delete and recreate every event. The digest is an explicit FNV-1a rather
than `Hashable.hashValue`, which Swift seeds per process and would change on
every run.

**All date arithmetic runs in UTC.** A system-timezone calendar shifts day
arithmetic across DST transitions, which once published a zero-length all-day
event on 2027-03-28 that most clients will not render.

**A feed is rewritten only when its content changed.** `DTSTAMP` regenerates on
every run, so writing unconditionally produced an auto-commit on each scheduled
run even when nothing moved. Keeping the previous stamp also matches RFC 5545,
where `DTSTAMP` records when the object was last revised.

**Weekends are omitted from the school feed.** The source colours all 94 weekend
days of the school year with the same generic label it gives real holidays, and
never names them, so those entries carried no information.

**Generation refuses to publish a suspiciously small calendar.** An empty parse
was already an error, but a single changed cell colour would have silently
dropped a whole category while the run stayed green, so at least 30 events are
required.

**The pinned school year is consistency-checked.** It appears in several files
while only `Sources/SchoolCalendar` is authoritative, so tests assert that
`docs/index.html` and the 403 diagnostic agree with it. Prose documents that
mention future years on purpose are excluded.

## Continuous integration

`.github/workflows/update.yml` runs on the 1st and 15th of every month, and can
be started by hand from the Actions tab or with
`gh workflow run "Update Madrid Calendar Feeds"`.

It runs `swift test` before generating anything, so a broken parser cannot
publish a truncated feed. Each feed is then built in its own step, so a failure
in one does not discard the other's refresh, and the commit step runs either way.

The job runs in the official `swift:6.3` container rather than using a setup
action. That pins the toolchain, keeps the build cache valid across runs, and
avoids `swift-actions/setup-swift`, which declares `node20` in every released
version including the v3 beta - a runtime GitHub removes on 2026-09-23.

`.build` is cached with `actions/cache`, keyed on `Package.swift`, `Sources/**`
and `Tests/**`, with a `spm-swift6.3-` prefix as a restore key so an older cache
can seed an incremental rebuild. There are no external dependencies and no
`Package.resolved`, so the cache holds compiled output only.

Local development uses whatever Xcode provides, currently newer than the
container. If that difference ever matters, CI fails and the failure is reviewed.

Two other workflows exist, both documented in
[`SOURCES.md`](SOURCES.md): the next-school-year alarm and the EducaMadrid 403
diagnostic.
