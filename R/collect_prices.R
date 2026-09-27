# Every 6 hours: current price and discount for every game in the panel.
# Uses the public store endpoint 'appdetails'. With filters=price_overview it
# accepts several appids per request, so we query in batches and go slowly.
source("R/db.R")
suppressPackageStartupMessages(library(httr2))

BATCH   <- 50
COUNTRY <- "at"        # fixed store region -> prices in EUR, consistent over time

started <- Sys.time()
ts      <- run_timestamp()
con     <- db_connect()
on.exit(DBI::dbDisconnect(con))
appids  <- active_panel(con)

fetch_prices <- function(ids) {
  req <- request("https://store.steampowered.com/api/appdetails") |>
    req_url_query(appids = paste(ids, collapse = ","),
                  filters = "price_overview", cc = COUNTRY) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(30) |>
    req_retry(max_tries = 3, backoff = function(i) 5 * 2^i) |>
    req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(req_perform(req), error = function(e) NULL)
  if (is.null(resp) || resp_status(resp) != 200) return(NULL)
  tryCatch(resp_body_json(resp), error = function(e) NULL)
}

parse_one <- function(id, x) {
  if (is.null(x) || !isTRUE(x$success)) return(NULL)
  po <- if (is.list(x$data)) x$data$price_overview else NULL
  if (is.null(po)) {
    return(data.frame(appid = as.integer(id), ts = ts, has_price = FALSE,
                      currency = NA_character_, initial_cents = NA_integer_,
                      final_cents = NA_integer_, discount_pct = NA_integer_))
  }
  data.frame(appid = as.integer(id), ts = ts, has_price = TRUE,
             currency      = as.character(po$currency %||% NA),
             initial_cents = as.integer(po$initial %||% NA),
             final_cents   = as.integer(po$final %||% NA),
             discount_pct  = as.integer(po$discount_percent %||% NA))
}

rows    <- list()
batches <- split(appids, ceiling(seq_along(appids) / BATCH))
for (b in batches) {
  body <- fetch_prices(b)
  if (is.null(body)) {
    # Fallback: the batch failed -> try its games one by one
    for (id in b) {
      Sys.sleep(1.5)
      one <- fetch_prices(id)
      if (!is.null(one)) rows[[length(rows) + 1]] <- parse_one(id, one[[as.character(id)]])
    }
  } else {
    for (id in names(body)) rows[[length(rows) + 1]] <- parse_one(id, body[[id]])
  }
  Sys.sleep(3)
}

out  <- do.call(rbind, rows)
n_ok <- if (is.null(out)) 0L else nrow(out)
n    <- insert_new(con, "prices", out, c("appid", "ts"))
log_run(con, "prices", started, n_ok = n_ok, n_fail = length(appids) - n_ok)
cat(sprintf("[%s] prices: %d ok, %d failed, %d new rows, %d currently discounted\n",
            format(ts), n_ok, length(appids) - n_ok, n,
            if (is.null(out)) 0L else sum(out$discount_pct > 0, na.rm = TRUE)))
