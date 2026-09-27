#' Get Origination Funnel Summary
#'
#' @param con A DBI connection object
#' @param branch Branch name to filter by (or "All")
#' @param sector Sector name to filter by (or "All")
#' @return A dataframe with stage names and counts of applications
#' @export
funnel_summary <- function(con, branch = "All", sector = "All") {
  apps_tbl <- dplyr::tbl(con, "applications")
  stages_tbl <- dplyr::tbl(con, "application_stages")
  
  # Apply filters if not "All"
  if (branch != "All") {
    apps_tbl <- apps_tbl |> dplyr::filter(branch == !!branch)
  }
  if (sector != "All") {
    apps_tbl <- apps_tbl |> dplyr::filter(sector == !!sector)
  }
  
  stages_tbl |>
    dplyr::inner_join(apps_tbl, by = "app_id") |>
    dplyr::count(stage) |>
    dplyr::collect()
}

#' Get Turnaround Time (TAT) Summary
#'
#' @param con A DBI connection object
#' @param branch Branch name to filter by (or "All")
#' @param sector Sector name to filter by (or "All")
#' @return A dataframe with average TAT in hours by stage and branch
#' @export
tat_summary <- function(con, branch = "All", sector = "All") {
  apps_tbl <- dplyr::tbl(con, "applications")
  stages_tbl <- dplyr::tbl(con, "application_stages")
  
  if (branch != "All") {
    apps_tbl <- apps_tbl |> dplyr::filter(branch == !!branch)
  }
  if (sector != "All") {
    apps_tbl <- apps_tbl |> dplyr::filter(sector == !!sector)
  }
  
  stages_tbl |>
    dplyr::filter(!is.na(exit_ts)) |>
    dplyr::inner_join(apps_tbl, by = "app_id") |>
    dplyr::mutate(tat_hours = (dbplyr::sql("EPOCH(exit_ts)") - dbplyr::sql("EPOCH(entry_ts)")) / 3600) |>
    dplyr::group_by(stage, branch) |>
    dplyr::summarise(avg_tat_hours = mean(tat_hours, na.rm = TRUE), .groups = "drop") |>
    dplyr::collect()
}