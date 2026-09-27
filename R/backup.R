# Weekly: export every table to a gzipped CSV in backup/ (read-only).
# Run from the project root:  Rscript R/backup.R
source("R/db.R")
con <- db_connect()
on.exit(DBI::dbDisconnect(con))
# the session cannot write, so a backup can never change the data
invisible(DBI::dbExecute(con, "SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY"))

dir.create("backup", showWarnings = FALSE)
day <- format(Sys.time(), "%Y-%m-%d", tz = "UTC")
for (tbl in c("games", "player_counts", "prices", "runs")) {
  df <- DBI::dbReadTable(con, tbl)
  f  <- file.path("backup", sprintf("%s_%s.csv.gz", tbl, day))
  gz <- gzfile(f, "w")
  write.csv(df, gz, row.names = FALSE)
  close(gz)
  cat(sprintf("%-14s %8d rows -> %s\n", tbl, nrow(df), f))
}
