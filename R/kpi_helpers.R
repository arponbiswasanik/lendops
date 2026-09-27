#' Get KPI Summary for Credit-SME
#'
#' Computes high-level management KPIs from the applications table.
#'
#' @param con A DBI connection object
#' @param branch Branch name to filter by (or "All")
#' @param sector Sector name to filter by (or "All")
#' @return A 1-row dataframe with KPI values
#' @export
kpi_summary <- function(con, branch = "All", sector = "All") {
  apps_tbl <- dplyr::tbl(con, "applications")
  
  if (branch != "All") {
    apps_tbl <- apps_tbl |> dplyr::filter(branch == !!branch)
  }
  if (sector != "All") {
    apps_tbl <- apps_tbl |> dplyr::filter(sector == !!sector)
  }
  
  # Step 1: Get raw counts and sums
  apps_tbl |>
    dplyr::summarise(
      total_applications = dplyr::n(),
      disbursed_loans = sum(final_status == "Disbursed", na.rm = TRUE),
      total_disbursed_amt = sum(dplyr::case_when(
        final_status == "Disbursed" ~ requested_amt,
        TRUE ~ 0
      ), na.rm = TRUE)
    ) |>
    # Step 2: Calculate ratios in a separate mutate step (SQL-safe)
    dplyr::mutate(
      approval_rate = disbursed_loans / total_applications,
      avg_ticket_size = dplyr::if_else(disbursed_loans > 0, 
                                       total_disbursed_amt / disbursed_loans, 
                                       0)
    ) |>
    dplyr::collect()
}