# Changes to the original bootstrap collector

| # | File | What | Why |
|---|---|---|---|
| 1 | `R/db.R` | `db_connect()` parses `DATABASE_URL` and passes `host`, `port`, `user`, `password`, `dbname` and the URI's query parameters (`sslmode`, `channel_binding`) separately; `sslmode` defaults to `require`. | RPostgres did not expand the URI passed as `dbname` and tried to connect to `localhost:5432`. |
