library(targets)
library(tarchetypes)
library(dplyr)
library(DBI)
library(duckdb)

tar_option_set(packages = c("dplyr", "DBI", "duckdb", "dbplyr", "ggplot2", "scales", "tidyr"))

list(
  # 1. Pull Rich KPI Data
  tar_target(
    kpi_data,
    {
      con <- DBI::dbConnect(duckdb::duckdb(), dbdir = "inst/testdata/lendops.duckdb")
      on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
      
      dplyr::tbl(con, "applications") |>
        # Step 1: Get raw counts and sums
        dplyr::summarise(
          total_applications = dplyr::n(),
          disbursed_loans = sum(final_status == "Disbursed", na.rm = TRUE),
          total_disbursed_amt = sum(dplyr::case_when(
            final_status == "Disbursed" ~ requested_amt, TRUE ~ 0
          ), na.rm = TRUE)
        ) |>
        # Step 2: Calculate ratios in a separate mutate step (SQL-safe)
        dplyr::mutate(
          approval_rate = disbursed_loans / total_applications,
          avg_ticket_size = total_disbursed_amt / disbursed_loans
        ) |>
        dplyr::collect()
    }
  ),
  
  # 2. Pull Decline Reasons
  tar_target(
    decline_reasons,
    {
      con <- DBI::dbConnect(duckdb::duckdb(), dbdir = "inst/testdata/lendops.duckdb")
      on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
      
      dplyr::tbl(con, "applications") |>
        dplyr::filter(final_status == "Declined") |>
        dplyr::group_by(decline_reason) |>
        dplyr::summarise(count = dplyr::n()) |>
        dplyr::arrange(dplyr::desc(count)) |>
        dplyr::collect()
    }
  ),
  
  # 3. Pull TAT Data
  tar_target(
    tat_data,
    {
      con <- DBI::dbConnect(duckdb::duckdb(), dbdir = "inst/testdata/lendops.duckdb")
      on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
      
      dplyr::tbl(con, "application_stages") |>
        dplyr::filter(!is.na(exit_ts)) |>
        dplyr::inner_join(dplyr::tbl(con, "applications"), by = "app_id") |>
        dplyr::mutate(tat_hours = (dbplyr::sql("EPOCH(exit_ts)") - dbplyr::sql("EPOCH(entry_ts)")) / 3600) |>
        dplyr::group_by(stage, branch) |>
        dplyr::summarise(avg_tat_hours = mean(tat_hours, na.rm = TRUE), .groups = "drop") |>
        dplyr::collect()
    }
  ),
  
  # 4. Render Quarto Report
  tar_quarto(
    report,
    path = "report.qmd",
    execute_params = list(month = "Latest")
  )
)