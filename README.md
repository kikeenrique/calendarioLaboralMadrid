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
Holidays, non-teaching days, assessments, review days, and the start and end of
each teaching period. Weekends are omitted.

```
webcal://calendar.lemambo.com/calendario-escolar-comunidad-madrid.ics
```

Both are also reachable over plain HTTPS
([holidays](https://calendar.lemambo.com/madrid-festivos.ics),
[school](https://calendar.lemambo.com/calendario-escolar-comunidad-madrid.ics))
and tracked in [`docs/`](docs/).

The feeds refresh automatically on the 1st and 15th of every month.

## Documentation

- [Sources](documentation/SOURCES.md) — where the data comes from, and how the
  school calendar is kept current
- [Implementation](documentation/IMPLEMENTATION.md) — the Swift package, how to
  run it, and the decisions behind it
- [Roadmap](documentation/ROADMAP.md) — what is done, pending, and ruled out
