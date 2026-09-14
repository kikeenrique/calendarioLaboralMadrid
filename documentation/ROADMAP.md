# Roadmap

State of the project and what is left. See
[IMPLEMENTATION.md](IMPLEMENTATION.md) for how it works and
[SOURCES.md](SOURCES.md) for where the data comes from.

## Done

### Feed correctness

- **DTEND computed in UTC.** Both generators paired a system-timezone `Calendar`
  with a UTC `DateFormatter`, so `byAdding: .day` preserved local wall-clock time
  and lost an hour at spring forward. This was live, not theoretical: the
  published feed carried `DTSTART 20270328` with `DTEND 20270328`, a zero-length
  all-day event most clients will not render.
- **Stable, content-derived UIDs.** UIDs embedded the array index, so any change
  to the event set renumbered every later event and subscribers lost per-event
  state. They are now the date plus a digest of an internal identifier. The digest
  is an explicit FNV-1a, not `Hashable.hashValue`, which Swift seeds per process
  and would have made UIDs unstable on every single run.
- **Titles decoupled from UIDs.** The displayed title and the internal id are
  separate, so rewording a title costs no UID churn. Proven by test.
- **Weekends omitted from the school feed.** The source colours all 94 weekend
  days of the school year with the same generic label it gives real holidays, and
  never names them, so those 95 events told subscribers only that Saturdays and
  Sundays are not school days. 134 events down to 39.
- **Sentence-case titles with accents restored.** The source writes labels in
  caps and drops the accents Spanish omits there.
- **Feeds rewritten only when their content changed.** `DTSTAMP` regenerates every
  run, so writing unconditionally produced an `Auto-update` commit on every
  scheduled run even when nothing moved. Also the correct reading of RFC 5545.
- **Summaries escaped.** The holiday builder emitted `SUMMARY` unescaped; a name
  containing a comma would have produced broken ICS.

### Build and test

- **Converted to a Swift package** with library targets and thin executables.
  The two scripts had duplicated helpers and colliding global names (`request`,
  `dateFormatter`, `userAgent`, `outputPath` existed in both).
- **30 tests, no mocking.** Parsing and generation are pure, so the tests run the
  same code the generators do against the real archived page.
- **Sanity floor.** `noEvents` only caught total failure; a single changed cell
  colour would have silently dropped a whole category while the run stayed green.
  Generation now requires at least 30 events.
- **Linux portability.** The conversion introduced `path as NSString`, which
  swift-corelibs-foundation does not provide - it would not have compiled in CI.
  Verified on the runner: Swift 6.0.3, all tests passing, and output byte-identical
  to macOS apart from `DTSTAMP`.
- **CI runs the tests before generating**, so a broken parser cannot publish a
  truncated feed.

### Automation

- **Manual trigger** (`workflow_dispatch`) on the feed workflow.
- **The two feeds build in separate steps.** A single step meant one failure threw
  away the other feed's output before the commit step ran - which is exactly what
  happened on the first real run.
- **`actions/checkout` v4 → v7.** `swift-actions/setup-swift` was removed
  entirely: every released version including the v3 beta still declares `node20`,
  which GitHub removes from runners on 2026-09-23. Swift is preinstalled on the
  runner image, so CI uses that and logs the version on each run.
- **Next-school-year alarm.** `check-next-school-year.yml` watches the Comunidad
  de Madrid listing page monthly and fails on purpose when a newer calendar
  appears. It reads the tracked year from the generator, so re-pointing the
  generator disarms it.
- **The pinned year is consistency-checked.** The year appeared in several files
  while only `Sources/SchoolCalendar` was authoritative, so updating the
  generator and forgetting `docs/index.html` would have left the site
  advertising the wrong year with nothing to catch it. Tests now assert that
  `docs/index.html` and the 403 diagnostic match the tracked year, that the
  archive the generator points at exists, and that the alarm's grep path is
  still valid. Verified by simulating the drift. Prose docs that legitimately
  mention future years are excluded and stay manual.

### The EducaMadrid 403, closed

- **Diagnosed and documented.** The block is address-based: identical stock Apache
  403 for every user agent, header set, referer, cookie and HTTP version, plus
  `external.educa2.madrid.org`, the Internet Archive (whose only two captures of
  the page are the 403 itself) and public fetch proxies. GitHub runners are not in
  Spain; ours was in Phoenix.
- **Decision: we do not work around it.** A Spanish egress - VPS, scraping API or
  cloud function - would cost money and a credential to re-download a document
  that changes once a year. The probe matrix is recorded in
  `diagnose-educamadrid.yml` so this is not re-investigated.
- **`RefreshSchoolArchive`** replaces the live check for the machine that *can*
  reach the source: your own.

## Pending

### Small

- **`docs/index.html` duplicates prose from the README** and is maintained by
  hand. The year is now guarded by tests, so what is left is ordinary
  duplication, not a correctness risk.

- **Period label wording.** "Inicio periodo lectivo para los alumnos enseñanzas
  correspondientes" is missing prepositions. It is the source's own phrasing, so
  it was left alone, but titles no longer affect UIDs - this is a one-line change
  with no churn.

### Recurring, once a year

- **Re-archive the new school calendar.** The alarm will tell you. Steps are in
  [`SOURCES.md`](SOURCES.md).

## Explicitly not doing

- **Monitoring BOCM.** The authoritative order is published as a PDF on
  `comunidad.madrid`, which *is* reachable from CI, and it contains the whole
  calendar. But parsing it means extracting date ranges from legal prose, and
  PDFKit is Apple-only so Linux CI would need `poppler-utils`. Too much effort for
  a once-a-year document.
- **Paying for a Spanish egress** to fetch EducaMadrid. See above.
- **Choosing a CI region.** GitHub gives no region control on standard hosted
  runners; the only supported route is larger runners with Azure private
  networking, which needs an organization on a paid plan plus an Azure
  subscription. A self-hosted runner would work but this repository is public, and
  fork pull requests can execute code on a self-hosted runner.
- **DocC.** No public API and no consumers; it would be upkeep nobody reads.
