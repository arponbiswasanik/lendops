library(DBI)
library(duckdb)

# 1. Connect to (or create) the DuckDB database file
# This will create lendops.duckdb in your project root
con <- dbConnect(duckdb::duckdb(), dbdir = "inst/testdata/lendops.duckdb")

# 2. Execute the DDL script to create tables, indexes, and views
schema_sql <- readLines("inst/sql/01_schema.sql", warn = FALSE)
dbExecute(con, paste(schema_sql, collapse = "\n"))

# 3. Load the generated data
load("data/app_data.rda")
load("data/stage_data.rda")
load("data/perf_data.rda")

# 4. Write data to the database (overwrite if exists)
dbWriteTable(con, "applications", app_data, overwrite = TRUE)
dbWriteTable(con, "application_stages", stage_data, overwrite = TRUE)
dbWriteTable(con, "loan_performance", perf_data, overwrite = TRUE)

# 5. Generate dummy targets data for KPI Cockpit
# Target: 800M disbursement per branch per month, 60% approval rate
targets <- expand.grid(
  target_month = seq(as.Date("2023-01-01"), as.Date("2024-06-01"), by="month"),
  branch = unique(app_data$branch)
) |>
  dplyr::mutate(
    target_disbursement_amt = 80000000,
    target_approval_rate = 0.60
  )
dbWriteTable(con, "targets", targets, overwrite = TRUE)

# 6. Re-run DDL to apply indexes and view after data is loaded
dbExecute(con, paste(schema_sql, collapse = "\n"))

# 7. Verify
print(dbListTables(con))
print(dbGetQuery(con, "SELECT COUNT(*) AS total_loans FROM applications WHERE final_status = 'Disbursed'"))

# 8. Disconnect
dbDisconnect(con, shutdown = TRUE)

cat("DuckDB database built successfully at inst/testdata/lendops.duckdb\n")