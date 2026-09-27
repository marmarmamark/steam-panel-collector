# Changes to the original bootstrap collector

| # | File | What | Why |
|---|---|---|---|
| 1 | `R/db.R` | `db_connect()` parses `DATABASE_URL` and passes `host`, `port`, `user`, `password`, `dbname` and the URI's query parameters (`sslmode`, `channel_binding`) separately; `sslmode` defaults to `require`. | RPostgres did not expand the URI passed as `dbname` and tried to connect to `localhost:5432`. |
| 2 | `sql/schema.sql` (+ live DB) | Added nullable columns `games.release_date` (date) and `games.release_date_raw` (text) via `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`. Existing columns unchanged. | Addition 1 (approved schema change): release date as covariate and for the 30-day sale-eligibility rule. |
| 3 | `R/fetch_release_dates.R` (new) | One-time script: `appdetails?filters=release_date&l=english&cc=at`, one appid per request with 1.5 s sleep (batching returns HTTP 400 with this filter). Stores the raw string; parses only `"21 Aug, 2012"` / `"Aug 21, 2012"` in the C locale, NULL otherwise or if `coming_soon`. Parameterised `UPDATE`, only rows with `release_date_raw IS NULL`. | Addition 1. |
| 4 | `R/backup.R` (new) | Exports `games`, `player_counts`, `prices`, `runs` to `backup/<table>_<UTC date>.csv.gz`. The session is set to `READ ONLY`, so it cannot write to the database. | Addition 2: the panel cannot be re-collected. |
| 5 | `.github/workflows/backup.yml` (new) | Weekly (`15 3 * * 1`) + manual trigger; same R setup as `collect.yml`; runs `R/backup.R` and uploads `backup/` as an artifact (90 days). `collect.yml` unchanged. | Addition 2. |
| 6 | `.gitignore` | Added `backup/`. | Backups must never be committed. |
| 7 | `sql/schema.sql` (+ live DB) | New table `reviews (appid, ts, total_positive, total_negative, total_reviews)`, PK `(appid, ts)`. Existing tables unchanged. | Reviews addition (approved schema change). |
| 8 | `R/collect_reviews.R` (new) | Daily job: `appreviews/<appid>?json=1&num_per_page=0&language=all&purchase_type=all&filter=all`, one game per request, 1.5 s sleep, reads `query_summary` totals, idempotent insert, logs `job = 'reviews'`. `success` is checked as the number 1 (the endpoint does not return a JSON boolean). Disconnects after reading the panel and reconnects for the insert: the first local run lost its data because Neon closed the connection after ~15 min idle. | Reviews addition. |
| 9 | `.github/workflows/collect.yml` | Added cron `23 12 * * *` and a `Collect reviews` step (runs on that schedule or `job=reviews`); input description mentions `reviews`. Existing crons and steps unchanged. | Reviews addition. |
| 10 | `R/backup.R` | Also exports `reviews`. | Reviews addition. |
