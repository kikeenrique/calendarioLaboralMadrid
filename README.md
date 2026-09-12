# madrid-holidays-feed

Auto-updating `.ics` calendar feed of Madrid's official non-working days
("días festivos / no laborables"), sourced live from the Ayuntamiento de
Madrid's open-data portal:
https://datos.madrid.es/dataset/300082-0-calendario_laboral

That dataset already covers exactly what you want for the *city* of
Madrid: national holidays + the Comunidad de Madrid regional holidays
+ the 2 local festivos set by the Ayuntamiento (San Isidro, La
Almudena). No manual filtering needed.

## How it works

- `src/main.swift` calls the portal's CKAN `package_show` API to
  list the dataset's current resources, finds every ICS-format
  "solo festivos" resource (one per year), downloads each, and merges
  them into a single combined feed at `docs/madrid-festivos.ics`.
- It deliberately does **not** hardcode per-year resource IDs, since
  the portal assigns a new, non-sequential ID each year (e.g. 2024,
  2025, 2026 all have different IDs). Whatever years are published
  now get pulled in automatically.
- A GitHub Actions workflow (`.github/workflows/update.yml`) runs only
  on the 1st and 15th of each month, commits the refreshed file if it
  changed, and GitHub Pages serves it as a stable URL.

## Setup (one-time)

1. Create a new GitHub repo and push this project to it.
2. In the repo, go to **Settings → Pages**, set **Source: Deploy from
   a branch**, branch `main`, folder `/docs`. Save.
3. Wait for the first Pages deploy, then note your URL — it'll look
   like `https://<your-username>.github.io/<repo-name>/`.
4. Edit `docs/index.html` and replace `REPLACE_WITH_YOUR_GHPAGES_HOST`
   with `<your-username>.github.io/<repo-name>` in both links.
5. Run `swift src/main.swift` locally once if you want
   `docs/madrid-festivos.ics` to exist before the next scheduled
   GitHub Actions run.

## Subscribing from Apple Calendar / iOS

Once Pages is live, subscribe with the **webcal** version of your URL,
e.g.:

```
webcal://<your-username>.github.io/<repo-name>/madrid-festivos.ics
```

On iPhone/iPad: Settings → Calendar → Accounts → Add Account →
Other → Add Subscribed Calendar, paste that URL.
On Mac: Calendar app → File → New Calendar Subscription, paste the
`https://` version (Calendar converts it).

Because it's a subscription (not a one-time import), Calendar will
periodically re-fetch it and pick up new years automatically once the
Ayuntamiento publishes them and the Action refreshes the feed.

## Notes / caveats

- The portal's `robots.txt` blocks generic crawling of the HTML site,
  but the CKAN `package_show`/`datastore_search` endpoints are the
  documented, intended way to consume this open data programmatically
  (the dataset page itself advertises the API). This script only
  calls the JSON API and the resource file URLs it returns — not the
  general website.
- Runs twice a month, well within any reasonable rate limit.
- If the Ayuntamiento ever renames resources or changes format away
  from ICS for a given year, `src/main.swift` will fail loudly
  (non-zero exit) rather than silently publishing a stale/incomplete
  feed — check the Actions log if a run fails.
- Data license: CC BY 4.0, Ayuntamiento de Madrid.
