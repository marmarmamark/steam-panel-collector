# Daily job: total review counts for every game in the panel.
# Store endpoint 'appreviews' with num_per_page=0 returns only the summary.
source("R/db.R")
suppressPackageStartupMessages(library(httr2))

started <- Sys.time()
ts      <- run_timestamp()
con     <- db_connect()
appids  <- active_panel(con)
# the fetch takes ~15 min; Neon drops idle connections, so reconnect afterwards
DBI::dbDisconnect(con)

get_reviews <- function(appid) {
  req <- request(paste0("https://store.steampowered.com/appreviews/", appid)) |>
    req_url_query(json = 1, num_per_page = 0, language = "all",
                  purchase_type = "all", filter = "all") |>
    req_user_agent(USER_AGENT) |>
    req_timeout(20) |>
    req_retry(max_tries = 3, backoff = function(i) 5 * 2^i) |>
    req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(req_perform(req), error = function(e) NULL)
  if (is.null(resp) || resp_status(resp) != 200) return(NULL)
  x <- tryCatch(resp_body_json(resp), error = function(e) NULL)
  # 'success' is the number 1, not a JSON boolean
  if (is.null(x) || !identical(as.integer(x$success %||% 0), 1L) ||
      is.null(x$query_summary$total_reviews)) return(NULL)
  qs <- x$query_summary
  data.frame(appid          = as.integer(appid),
             ts             = ts,
             total_positive = as.integer(qs$total_positive %||% NA),
             total_negative = as.integer(qs$total_negative %||% NA),
             total_reviews  = as.integer(qs$total_reviews))
}

rows <- lapply(appids, function(a) { Sys.sleep(1.5); get_reviews(a) })
out  <- do.call(rbind, rows)
n_ok <- if (is.null(out)) 0L else nrow(out)
con  <- db_connect()
on.exit(DBI::dbDisconnect(con))
n    <- insert_new(con, "reviews", out, c("appid", "ts"))
log_run(con, "reviews", started, n_ok = n_ok, n_fail = length(appids) - n_ok)
cat(sprintf("[%s] reviews: %d ok, %d failed, %d new rows\n",
            format(ts), n_ok, length(appids) - n_ok, n))
