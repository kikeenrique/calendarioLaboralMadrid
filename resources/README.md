# Source snapshots

`calendario-escolar-26-27.html` is **not a reference copy — it is the source the
school feed is built from.** `Sources/SchoolCalendar` parses this file and does no
networking at all.

It was downloaded from
[EducaMadrid](https://www.educa2.madrid.org/web/calendario-escolar-de-la-comunidad-de-madrid/calendario-escolar-26-27),
which blocks access from outside Spain, so CI cannot fetch it and refreshing this
snapshot is a local job:

```
swift run RefreshSchoolArchive           # fetch, compare, report; changes nothing
swift run RefreshSchoolArchive --write   # update this file and regenerate the feed
```

Why it works this way, and the checklist for when a new school year is published:
[`../documentation/SOURCES.md`](../documentation/SOURCES.md).
