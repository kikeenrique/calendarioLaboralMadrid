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
`gh workflow run "Update Madrid Calendar Feeds"`.

## Implementation

[`src/main.swift`](src/main.swift) queries the CKAN API, selects the holiday ICS
resources, and writes `docs/madrid-festivos.ics`.

[`src/school_calendar.swift`](src/school_calendar.swift) downloads and parses the
official school-calendar page, then writes
`docs/calendario-escolar-comunidad-madrid.ics`.

Event UIDs are built from the date plus an internal identifier, never from the
displayed title, so rewording a title does not force subscribers' calendar apps
to delete and recreate every event.

The 2026-27 source page is preserved in
[`resources/calendario-escolar-26-27.html`](resources/calendario-escolar-26-27.html)
for future parser maintenance. The generator still uses the live EducaMadrid page
when the workflow runs.
