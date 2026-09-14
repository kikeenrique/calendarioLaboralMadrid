# Sources and how they are kept current

## Madrid holidays

The Ayuntamiento de Madrid's [Calendario laboral open-data
dataset](https://datos.madrid.es/dataset/300082-0-calendario_laboral), licensed
under CC BY 4.0, queried through the CKAN API.

Fetched live on every run. Nothing manual.

## Comunidad de Madrid school calendar

EducaMadrid's [Calendario escolar
26-27](https://www.educa2.madrid.org/web/calendario-escolar-de-la-comunidad-de-madrid/calendario-escolar-26-27).

**Not fetched.** The feed is generated from an archived copy of that page in
[`../resources/`](../resources/), refreshed by hand once per school year.

### Why it is not fetched

EducaMadrid blocks access from outside Spain, and GitHub's hosted runners are not
in Spain - ours ran in Phoenix, Arizona. Probed from a runner, every request
returns a byte-identical stock Apache 403:

| Probe | Result |
| --- | --- |
| Root path | 301 - the host itself is reachable |
| Target path, script user agent | 403 |
| Target path, browser user agent | 403 |
| Target path, no user agent | 403 |
| Target path, full browser headers | 403 |
| Target path, HTTP/1.1 | 403 |
| Target path, same-site referer | 403 |
| Target path, load-balancer cookies | 403 |
| `external.educa2.madrid.org` | 403 |

`external.educa2.madrid.org` is EducaMadrid's own documented host for access from
outside Spain, and it refuses runners too. So does the Internet Archive, whose
only two captures of the page are the 403 page itself, and so do public fetch
proxies. The rejection is address-based; nothing on the client side reaches it.

Getting through would mean paying for a Spanish egress - a VPS, a scraping API
with country targeting, or a cloud function in a Spanish region - to re-download a
document that changes once a year. That is not worth the cost, the credential, or
the extra way for the pipeline to fail quietly.

The full probe matrix is recorded at the top of
[`../.github/workflows/diagnose-educamadrid.yml`](../.github/workflows/diagnose-educamadrid.yml).
That workflow is manual-only; run it to check whether the block has lifted.

### Refreshing the archive

From a Spanish connection, at the repository root:

```
swift run RefreshSchoolArchive           # fetch, compare, report; changes nothing
swift run RefreshSchoolArchive --write   # update resources/ and regenerate the feed
```

It compares the live page against the archive by **parsed events**, not raw bytes:
Liferay varies about 60 bytes of page chrome between requests, so a byte
comparison differs on every run. Exit code 0 means no change, 2 means something
changed, and it prints exactly which events were added or removed.

### When a new school year is published

You do not have to watch for it. The [`Check for next school
year`](../.github/workflows/check-next-school-year.yml) workflow runs monthly,
watches the Comunidad de Madrid [calendar listing
page](https://www.comunidad.madrid/educacion/calendario-escolar) - which *is*
reachable from CI - and **fails on purpose** when it finds a calendar newer than
the one the generator tracks. A red run there is a reminder, not a breakage. It
also fails if the listing becomes unreadable, since a silent alarm is worse than
a noisy one.

Then:

1. Save the new page into `resources/` as `calendario-escolar-27-28.html`.
2. Update `archivePath` and `sourceURL` in
   [`../Sources/SchoolCalendar/SchoolCalendar.swift`](../Sources/SchoolCalendar/SchoolCalendar.swift).
3. Update the year shown in [`../docs/index.html`](../docs/index.html).
4. Run `swift test`, then `swift run GenerateSchoolFeed`, and review the diff.

Step 2 disarms the alarm, because it reads the tracked year from that file. Steps
2 and 3 are enforced: `swift test` fails until they agree.
