db_path <- function() {
  path <- file.path("inst", "testdata", "lendops.duckdb")
  if (!file.exists(path)) {
    path <- file.path("..", "..", "inst", "testdata", "lendops.duckdb")
  }
  path
}

test_that("Blind Detection: Finds origination TAT bottleneck", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res <- tat_summary(con)
  
  # Isolate the Documentation stage
  doc_tats <- res |> dplyr::filter(stage == "Documentation")
  
  # Compare the average TAT of the bottlenecked branches vs the normal branches
  # Without reading the oracle, we expect a significant variance.
  # The top 2 branches by TAT should be at least 50% higher than the average of the rest.
  sorted_tats <- sort(doc_tats$avg_tat_hours, decreasing = TRUE)
  
  top_2_avg <- mean(sorted_tats[1:2])
  rest_avg <- mean(sorted_tats[3:length(sorted_tats)])
  
  expect_gt(top_2_avg, rest_avg * 1.5)
})

test_that("Blind Detection: Finds approval rate shift", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  # Query to get approval rate before and after Sept 2023
  df <- dplyr::tbl(con, "applications") |>
    dplyr::mutate(period = dplyr::if_else(app_month < as.Date("2023-09-01"), "Before Shift", "After Shift")) |>
    dplyr::group_by(period) |>
    dplyr::summarise(approval_rate = sum(final_status == "Disbursed") / dplyr::n()) |>
    dplyr::collect()
  
  before_rate <- df$approval_rate[df$period == "Before Shift"]
  after_rate <- df$approval_rate[df$period == "After Shift"]
  
  # Expect a noticeable drop in approval rates
  expect_gt(before_rate, after_rate)
  expect_gt(before_rate - after_rate, 0.10) # Dropped by at least 10%
})

test_that("Blind Detection: Finds March 2023 vintage spike", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res <- vintage_curve(con)
  
  # Compare March 2023 MOB 1 delinq to average of all other cohorts MOB 1
  march <- res |> dplyr::filter(lubridate::month(app_month) == 3, lubridate::year(app_month) == 2023, mob == 1)
  others <- res |> dplyr::filter(mob == 1, !(lubridate::month(app_month) == 3 & lubridate::year(app_month) == 2023))
  
  # Expect March 2023 to be at least 1.25x higher than the average of the rest
  expect_gt(march$delinq_rate[1], mean(others$delinq_rate) * 1.25)
})