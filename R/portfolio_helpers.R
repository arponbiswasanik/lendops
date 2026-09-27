#' Calculate Vintage Delinquency Curves
#'
#' Computes the percentage of loans delinquent (DPD > 0) by months-on-book (MOB)
#' for each origination cohort. Censors immature cohorts.
#'
#' @param con A DBI connection object
#' @return A dataframe with cohort_month, mob, and delinq_rate
#' @export
vintage_curve <- function(con) {
  tbl(con, "vw_disbursed_loans") |>
    mutate(
      # Use explicit SQL cast to ensure integer math for MOB
      mob = sql("CAST((YEAR(snapshot_month) - YEAR(app_month)) * 12 + (MONTH(snapshot_month) - MONTH(app_month)) AS INTEGER)")
    ) |>
    filter(mob >= 0) |>
    group_by(app_month, mob) |>
    summarise(
      total_loans = n(),
      delinq_loans = sum(dpd > 0, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(delinq_rate = delinq_loans / total_loans) |>
    collect()
}

#' Calculate Roll-Rate Migration Matrix
#'
#' Computes the month-over-month transition probabilities between DPD buckets.
#'
#' @param con A DBI connection object
#' @return A dataframe with from_dpd, to_dpd, count, and transition_rate
#' @export
roll_rate_matrix <- function(con) {
  tbl(con, "loan_performance") |>
    group_by(loan_id) |>
    # Use window_order instead of arrange to avoid SQL subquery errors
    dbplyr::window_order(snapshot_month) |>
    mutate(prev_dpd = lag(dpd)) |>
    ungroup() |>
    filter(!is.na(prev_dpd)) |>
    group_by(prev_dpd, dpd) |>
    summarise(count = n(), .groups = "drop") |>
    # Group by prev_dpd ONLY to calculate the transition probability
    group_by(prev_dpd) |>
    mutate(transition_rate = count / sum(count)) |>
    ungroup() |>
    collect()
}