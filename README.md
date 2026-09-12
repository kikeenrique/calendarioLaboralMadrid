# Madrid holidays calendar

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

## Source and updates

Data comes from the Ayuntamiento de Madrid's [Calendario laboral open-data
dataset](https://datos.madrid.es/dataset/300082-0-calendario_laboral), licensed
under CC BY 4.0.

The GitHub Actions workflow runs on the 1st and 15th of every month. It fetches
the currently published ICS resources and commits an updated combined calendar
only when the feed has changed.

## Implementation

[`src/main.swift`](src/main.swift) queries the dataset's CKAN API, selects the
holiday ICS resources, and writes the merged calendar to
`docs/madrid-festivos.ics`.
