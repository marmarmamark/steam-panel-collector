# One-time: choose the fixed panel of games and store it in the database.
# Source: SteamSpy "all" endpoint (games ranked by owners, 1000 per page).
# Only paid games are kept (free games cannot be discounted), and the panel is
# stratified by current players so it is not just the biggest hits.
# Run locally from the project root:  Rscript R/build_panel.R
source("R/db.R")
suppressPackageStartupMessages(library(httr2))

N_TARGET <- 500
N_STRATA <- 5
MIN_CCU  <- 20        # drop near-dead games (too few players to measure anything)
PAGES    <- 0:1       # 2 pages = up to 2000 candidates
set.seed(20260927)

fetch_page <- function(page) {
  resp <- request("https://steamspy.com/api.php") |>
    req_url_query(request = "all", page = page) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(120) |>
    req_perform()
  resp_body_json(resp)
}

to_row <- function(g) {
  data.frame(
    appid               = as.integer(g$appid),
    name                = as.character(g$name %||% NA),
    developer           = as.character(g$developer %||% NA),
    publisher           = as.character(g$publisher %||% NA),
    initial_price_cents = suppressWarnings(as.integer(g$initialprice %||% NA)),
    positive            = suppressWarnings(as.integer(g$positive %||% NA)),
    negative            = suppressWarnings(as.integer(g$negative %||% NA)),
    owners_band         = as.character(g$owners %||% NA),
    ccu_at_selection    = suppressWarnings(as.integer(g$ccu %||% NA)),
    stringsAsFactors    = FALSE
  )
}

games_raw <- list()
for (p in PAGES) {
  cat("Fetching SteamSpy page", p, "...\n")
  games_raw <- c(games_raw, unname(fetch_page(p)))
  if (p != tail(PAGES, 1)) Sys.sleep(65)   # SteamSpy allows ~1 'all' request per minute
}
cand <- do.call(rbind, lapply(games_raw, to_row))
cand <- cand[!duplicated(cand$appid), ]

cand <- subset(cand, !is.na(initial_price_cents) & initial_price_cents > 0 &
                     !is.na(ccu_at_selection) & ccu_at_selection >= MIN_CCU)
cat(nrow(cand), "paid candidates with at least", MIN_CCU, "concurrent players\n")

# Stratify on log(concurrent players) and sample evenly from each stratum
brks <- unique(quantile(log(cand$ccu_at_selection),
                        probs = seq(0, 1, length.out = N_STRATA + 1)))
cand$stratum <- as.integer(cut(log(cand$ccu_at_selection),
                               breaks = brks, include.lowest = TRUE))
per_stratum <- ceiling(N_TARGET / N_STRATA)
panel <- do.call(rbind, lapply(split(cand, cand$stratum), function(d) {
  d[sample(nrow(d), min(nrow(d), per_stratum)), ]
}))
panel <- head(panel[order(panel$stratum, -panel$ccu_at_selection), ], N_TARGET)
panel$selected_at <- Sys.time()

con <- db_connect()
on.exit(DBI::dbDisconnect(con))
n <- insert_new(con, "games", panel, "appid")
cat("Inserted", n, "games into the panel.\n")
print(table(panel$stratum))

dir.create("data", showWarnings = FALSE)
write.csv(panel, "data/panel.csv", row.names = FALSE)
cat("Panel also saved to data/panel.csv (commit this file).\n")
