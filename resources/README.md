# Source snapshots

`calendario-escolar-26-27.html` is **not a reference copy - it is the source the
school feed is built from.** `Sources/SchoolCalendar` parses this file and does no
networking at all.

It was downloaded from:

https://www.educa2.madrid.org/web/calendario-escolar-de-la-comunidad-de-madrid/calendario-escolar-26-27

## Why the generator does not fetch that page

EducaMadrid blocks access from outside Spain, and GitHub's hosted runners are not
in Spain. Every request from a runner returns 403, whatever the user agent,
headers, referer, cookies or HTTP version - and `external.educa2.madrid.org`, the
Internet Archive and public fetch proxies all return 403 too. The full probe
matrix is at the top of
[`../.github/workflows/diagnose-educamadrid.yml`](../.github/workflows/diagnose-educamadrid.yml).

From a Spanish connection the page is reachable, so refreshing this snapshot is a
local job.

## Refreshing it

From the repository root, on a Spanish connection:

```
swift run RefreshSchoolArchive           # fetch, compare, report; changes nothing
swift run RefreshSchoolArchive --write   # update this file and regenerate the feed
```

The comparison is on parsed events, not raw bytes: Liferay varies about 60 bytes
of page chrome between requests, so a byte comparison differs on every run.

## When a new school year is published

The [`Check for next school year`](../.github/workflows/check-next-school-year.yml)
workflow fails on purpose when it spots a newer calendar, so you will be told.
Then:

1. Save the new page here as `calendario-escolar-27-28.html`.
2. Update `archivePath` and `sourceURL` in
   [`../Sources/SchoolCalendar/SchoolCalendar.swift`](../Sources/SchoolCalendar/SchoolCalendar.swift).
3. Update the year shown in [`../docs/index.html`](../docs/index.html) and this file.
4. Run `swift test`, then `swift run GenerateSchoolFeed`, and review the diff.

Step 2 also disarms the alarm, because it reads the tracked year from that file.
