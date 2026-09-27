# Shared helpers: database connection, idempotent inserts, run logging.
Sys.setenv(TZ = "UTC")
suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})

`%||%` <- function(x, y) if (is.null(x)) y else x

db_connect <- function() {
  url <- Sys.getenv("DATABASE_URL")
  if (!nzchar(url)) stop("DATABASE_URL is not set (see README).")
  # libpq accepts a full connection URI in place of a database name
  DBI::dbConnect(RPostgres::Postgres(), dbname = url)
}

# Insert rows, silently skipping rows whose primary key already exists.
# This makes every job safe to re-run.
insert_new <- function(con, table, df, key_cols) {
  if (is.null(df) || nrow(df) == 0) return(0L)
  tmp <- paste0("tmp_", table)
  DBI::dbWriteTable(con, tmp, df, temporary = TRUE, overwrite = TRUE)
  cols <- paste(DBI::dbQuoteIdentifier(con, names(df)), collapse = ", ")
  sql <- sprintf(
    "INSERT INTO %s (%s) SELECT %s FROM %s ON CONFLICT (%s) DO NOTHING",
    table, cols, cols, tmp, paste(key_cols, collapse = ", ")
  )
  n <- DBI::dbExecute(con, sql)
  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", tmp))
  n
}

log_run <- function(con, job, started_at, n_ok, n_fail, note = NA_character_) {
  DBI::dbExecute(
    con,
    "INSERT INTO runs (job, started_at, finished_at, n_ok, n_fail, note)
     VALUES ($1, $2, now(), $3, $4, $5)",
    params = list(job, started_at, as.integer(n_ok), as.integer(n_fail), note)
  )
}

active_panel <- function(con) {
  DBI::dbGetQuery(con, "SELECT appid FROM games WHERE active ORDER BY appid")$appid
}

# All observations of one run share one timestamp, truncated to the full hour,
# so the panel lines up cleanly across games even if a run starts late.
run_timestamp <- function() as.POSIXct(trunc(Sys.time(), "hours"), tz = "UTC")

USER_AGENT <- "uibk-data-lab-steam-panel (student research project)"
