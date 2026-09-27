#' Calculate Vintage Delinquency Curves
#'
#' @param con A DBI connection object
#' @return A dataframe with cohort_month, mob, and delinq_rate
#' @export
vintage_curve <- function(con) {
  dplyr::tbl(con, "vw_disbursed_loans") |>
    dplyr::mutate(
      mob = dbplyr::sql("CAST((YEAR(snapshot_month) - YEAR(app_month)) * 12 + (MONTH(snapshot_month) - MONTH(app_month)) AS INTEGER)")
    ) |>
    dplyr::filter(mob >= 0) |>
    dplyr::group_by(app_month, mob) |>
    dplyr::summarise(
      total_loans = dplyr::n(),
      delinq_loans = sum(dpd > 0, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(delinq_rate = delinq_loans / total_loans) |>
    dplyr::collect()
}

#' Calculate Roll-Rate Migration Matrix
#'
#' @param con A DBI connection object
#' @return A dataframe with from_dpd, to_dpd, count, and transition_rate
#' @export
roll_rate_matrix <- function(con) {
  dplyr::tbl(con, "loan_performance") |>
    dplyr::group_by(loan_id) |>
    dbplyr::window_order(snapshot_month) |>
    dplyr::mutate(prev_dpd = dplyr::lag(dpd)) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(prev_dpd)) |>
    dplyr::group_by(prev_dpd, dpd) |>
    dplyr::summarise(count = dplyr::n(), .groups = "drop") |>
    dplyr::group_by(prev_dpd) |>
    dplyr::mutate(transition_rate = count / sum(count)) |>
    dplyr::ungroup() |>
    dplyr::collect()
}