# One-time: release date for every game in the panel (covariate "game age",
# and to check the 30-day sale-eligibility rule).
# Source: store endpoint 'appdetails' with filters=release_date. Batching several
# appids returns HTTP 400 with this filter, so we query one game at a time.
# Only games without release_date_raw are queried, so it is safe to re-run.
# Run locally from the project root:  Rscript R/fetch_release_dates.R
source("R/db.R")
suppressPackageStartupMessages(library(httr2))
invisible(Sys.setlocale("LC_TIME", "C"))   # English month names

con <- db_connect()
appids <- DBI::dbGetQuery(
  con, "SELECT appid FROM games WHERE release_date_raw IS NULL ORDER BY appid")$appid
cat(length(appids), "games without a release date yet\n")

get_release <- function(appid) {
  req <- request("https://store.steampowered.com/api/appdetails") |>
    req_url_query(appids = appid, filters = "release_date", l = "english", cc = "at") |>
    req_user_agent(USER_AGENT) |>
    req_timeout(20) |>
    req_retry(max_tries = 3, backoff = function(i) 5 * 2^i) |>
    req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(req_perform(req), error = function(e) NULL)
  if (is.null(resp) || resp_status(resp) != 200) return(NULL)
  x <- tryCatch(resp_body_json(resp)[[as.character(appid)]], error = function(e) NULL)
  if (is.null(x) || !isTRUE(x$success) || !is.list(x$data)) return(NULL)
  x$data$release_date
}

# Only the two formats Steam uses ("21 Aug, 2012", "Aug 21, 2012"); anything
# else ("Q4 2026", "Coming soon", ...) stays NA -- never guess.
parse_release <- function(raw) {
  fmt <- if (grepl("^[0-9]{1,2} [A-Za-z]+, [0-9]{4}$", raw)) "%d %b, %Y"
         else if (grepl("^[A-Za-z]+ [0-9]{1,2}, [0-9]{4}$", raw)) "%b %d, %Y"
         else return(as.Date(NA))
  as.Date(raw, format = fmt)
}

n_parsed <- 0L; n_unparsed <- 0L; n_failed <- 0L
for (a in appids) {
  Sys.sleep(1.5)
  rd <- get_release(a)
  if (is.null(rd)) { n_failed <- n_failed + 1L; next }
  raw <- as.character(rd$date %||% "")
  d   <- if (isTRUE(rd$coming_soon)) as.Date(NA) else parse_release(raw)
  if (is.na(d)) n_unparsed <- n_unparsed + 1L else n_parsed <- n_parsed + 1L
  DBI::dbExecute(con,
    "UPDATE games SET release_date_raw = $1, release_date = $2 WHERE appid = $3",
    params = list(raw, d, a))
}

cat(sprintf("This run: %d parsed, %d unparsed, %d failed\n", n_parsed, n_unparsed, n_failed))
cat("Whole panel:\n")
print(DBI::dbGetQuery(con, "
  SELECT count(release_date) AS parsed,
         count(*) FILTER (WHERE release_date_raw IS NOT NULL AND release_date IS NULL) AS unparsed,
         count(*) FILTER (WHERE release_date_raw IS NULL) AS not_fetched,
         min(release_date) AS earliest, max(release_date) AS latest,
         count(*) FILTER (WHERE release_date > current_date - 30) AS released_last_30_days
  FROM games WHERE active"))
unparsed <- DBI::dbGetQuery(con, "
  SELECT appid, name, release_date_raw FROM games
  WHERE active AND release_date_raw IS NOT NULL AND release_date IS NULL ORDER BY appid")
if (nrow(unparsed) > 0) { cat("Unparsed raw strings:\n"); print(unparsed) }
DBI::dbDisconnect(con)
