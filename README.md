# Steam discount panel

Collects a panel of ~500 paid Steam games to study the causal effect of
discounts on player numbers (Autumn Sale 1-8 Oct 2026, Winter Sale
17 Dec 2026 - 4 Jan 2027).

| Job | Source | Frequency |
|---|---|---|
| Player counts | Steam Web API `GetNumberOfCurrentPlayers` (official, no key) | hourly |
| Prices / discounts | Steam store `appdetails?filters=price_overview` | every 6 h |
| Panel selection | SteamSpy `request=all` (one-time) | once |

Storage: PostgreSQL on Neon (free tier). Scheduler: GitHub Actions.

## Setup

1. **Database:** create a free Neon project (region: Frankfurt), copy the
   connection string (`postgresql://...?sslmode=require`).
2. **Local R:** install packages
   `install.packages(c("httr2", "jsonlite", "DBI", "RPostgres"))`,
   then put the connection string into `.Renviron` in the project root:
   `DATABASE_URL=postgresql://...`  (this file is git-ignored)
3. **Create tables:** `Rscript R/setup_db.R`
4. **Choose the panel:** `Rscript R/build_panel.R` (takes ~2 min),
   then commit `data/panel.csv`.
5. **Test both jobs locally:** `Rscript R/collect_players.R` and
   `Rscript R/collect_prices.R`, then check the tables.
6. **Automate:** push to a *public* GitHub repo, add the secret
   `DATABASE_URL` under Settings > Secrets and variables > Actions,
   then Actions tab > `collect` > Run workflow to test.

## Notes

- All jobs are idempotent: re-running never creates duplicate rows.
- Every run is logged in the `runs` table (check it for gaps).
- GitHub disables scheduled workflows in public repos after 60 days
  without repository activity: push a commit at least monthly.
- Scheduled runs can start a few minutes late; timestamps are truncated
  to the full hour, so this does not matter.
