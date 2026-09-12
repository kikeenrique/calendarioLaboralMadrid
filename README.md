# Madrid calendar feeds

An automatically maintained iCalendar (`.ics`) feed of Madrid's official
non-working days. It combines national holidays, Comunidad de Madrid regional
holidays, and the local holidays set by the Ayuntamiento de Madrid.

Subscribe to the calendar with:

```
webcal://calendar.lemambo.com/madrid-festivos.ics
```

The HTTPS endpoint is
[`https://calendar.lemambo.com/madrid-festivos.ics`](https://calendar.lemambo.com/madrid-festivos.ics).
The generated file is also tracked at
[`docs/madrid-festivos.ics`](docs/madrid-festivos.ics).

## Calendario Escolar Comunidad de Madrid

This feed covers the official 2026-27 school calendar published by EducaMadrid,
including holidays, non-teaching days, ordinary final assessments, review days,
and the start and end dates of each listed teaching period.

Subscribe with:

```
webcal://calendar.lemambo.com/calendario-escolar-comunidad-madrid.ics
```

The HTTPS endpoint is
[`https://calendar.lemambo.com/calendario-escolar-comunidad-madrid.ics`](https://calendar.lemambo.com/calendario-escolar-comunidad-madrid.ics).

## Source and updates

The Madrid holiday feed comes from the Ayuntamiento de Madrid's [Calendario
laboral open-data dataset](https://datos.madrid.es/dataset/300082-0-calendario_laboral),
licensed under CC BY 4.0. The school-calendar feed comes from EducaMadrid's
[Calendario escolar 26-27](https://www.educa2.madrid.org/web/calendario-escolar-de-la-comunidad-de-madrid/calendario-escolar-26-27).

The GitHub Actions workflow runs on the 1st and 15th of every month. It fetches
the currently published sources and refreshes both generated calendars.

## Implementation

[`src/main.swift`](src/main.swift) queries the CKAN API, selects the holiday
ICS resources, and writes `docs/madrid-festivos.ics`.

[`src/school_calendar.swift`](src/school_calendar.swift) downloads and parses
the official school-calendar page, then writes
`docs/calendario-escolar-comunidad-madrid.ics`.
