# Hourly job: current player count for every game in the panel.
# Official Steam Web API endpoint, no key required.
source("R/db.R")
suppressPackageStartupMessages(library(httr2))

started <- Sys.time()
ts      <- run_timestamp()
con     <- db_connect()
on.exit(DBI::dbDisconnect(con))
appids  <- active_panel(con)

get_players <- function(appid) {
  req <- request("https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/") |>
    req_url_query(appid = appid) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(20) |>
    req_retry(max_tries = 3, backoff = function(i) 2^i) |>
    req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(req_perform(req), error = function(e) NULL)
  if (is.null(resp) || resp_status(resp) != 200) return(NA_integer_)
  r <- tryCatch(resp_body_json(resp)$response, error = function(e) NULL)
  if (is.null(r) || !identical(as.integer(r$result %||% 0), 1L) || is.null(r$player_count)) {
    return(NA_integer_)
  }
  as.integer(r$player_count)
}

counts <- vapply(appids, function(a) { Sys.sleep(0.15); get_players(a) }, integer(1))

ok  <- !is.na(counts)
out <- data.frame(appid = appids[ok], ts = rep(ts, sum(ok)), player_count = counts[ok])
n   <- insert_new(con, "player_counts", out, c("appid", "ts"))
log_run(con, "players", started, n_ok = sum(ok), n_fail = sum(!ok))
cat(sprintf("[%s] players: %d ok, %d failed, %d new rows\n",
            format(ts), sum(ok), sum(!ok), n))
