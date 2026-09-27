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
  # RPostgres does not expand a URI passed as dbname, so split it into parts
  m <- regmatches(url, regexec(
    "^postgres(?:ql)?://([^:@/]+)(?::([^@]*))?@([^:/?]+)(?::(\\d+))?/([^?]*)(?:\\?(.*))?$",
    url, perl = TRUE))[[1]]
  if (length(m) == 0) stop("DATABASE_URL is not a valid postgresql:// URI.")
  args <- list(RPostgres::Postgres(), host = m[4],
               port = if (nzchar(m[5])) m[5] else "5432",
               user = URLdecode(m[2]), password = URLdecode(m[3]),
               dbname = URLdecode(m[6]))
  # query parameters (sslmode, channel_binding, ...) are passed on to libpq
  for (kv in strsplit(m[7], "&", fixed = TRUE)[[1]]) {
    p <- strsplit(kv, "=", fixed = TRUE)[[1]]
    if (length(p) == 2) args[[p[1]]] <- URLdecode(p[2])
  }
  if (is.null(args$sslmode)) args$sslmode <- "require"
  do.call(DBI::dbConnect, args)
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
