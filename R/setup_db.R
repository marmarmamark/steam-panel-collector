# One-time: create the tables. Run locally from the project root:
#   Rscript R/setup_db.R
source("R/db.R")
con <- db_connect()
on.exit(DBI::dbDisconnect(con))

sql <- paste(readLines("sql/schema.sql", warn = FALSE), collapse = "\n")
sql <- gsub("--[^\n]*", "", sql)                     # strip comments
stmts <- trimws(strsplit(sql, ";", fixed = TRUE)[[1]])
for (s in stmts[nzchar(stmts)]) DBI::dbExecute(con, s)

cat("Tables now in the database:\n")
print(DBI::dbListTables(con))
