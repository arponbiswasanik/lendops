#' Get Origination Funnel Summary
#'
#' @param con A DBI connection object
#' @return A dataframe with stage names and counts of applications
#' @export
funnel_summary <- function(con) {
  tbl(con, "application_stages") |>
    count(stage) |>
    collect()
}
#' Get Turnaround Time (TAT) Summary
#'
#' @param con A DBI connection object
#' @return A dataframe with average TAT in hours by stage and branch
#' @export
tat_summary <- function(con) {
  stages_tbl <- tbl(con, "application_stages")
  apps_tbl <- tbl(con, "applications")
  
  stages_tbl |>
    filter(!is.na(exit_ts)) |>
    inner_join(apps_tbl, by = "app_id") |>
    # Use DuckDB native EPOCH() to get difference in seconds, then convert to hours
    mutate(tat_hours = (dbplyr::sql("EPOCH(exit_ts)") - dbplyr::sql("EPOCH(entry_ts)")) / 3600) |>
    group_by(stage, branch) |>
    summarise(avg_tat_hours = mean(tat_hours, na.rm = TRUE), .groups = "drop") |>
    collect()
}