db_path <- function() {
  path <- file.path("inst", "testdata", "lendops.duckdb")
  if (!file.exists(path)) {
    path <- file.path("..", "..", "inst", "testdata", "lendops.duckdb")
  }
  path
}

test_that("vintage_curve calculates MOB and delinquency rates", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res <- vintage_curve(con)
  
  expect_s3_class(res, "data.frame")
  expect_true(all(c("app_month", "mob", "delinq_rate") %in% names(res)))
  
  # Delinquency rate should be between 0 and 1
  expect_true(all(res$delinq_rate >= 0 & res$delinq_rate <= 1))
})

test_that("roll_rate_matrix calculates transition probabilities", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res <- roll_rate_matrix(con)
  
  expect_s3_class(res, "data.frame")
  expect_true(all(c("prev_dpd", "dpd", "transition_rate") %in% names(res)))
  
  # Transition rates for each prev_dpd state should sum to ~1.0
  summed_rates <- res |> 
    dplyr::group_by(prev_dpd) |> 
    dplyr::summarise(total = sum(transition_rate))
  
  # Check all prev_dpd states to ensure they sum to 1.0
  expect_true(all(dplyr::between(summed_rates$total, 0.99, 1.01)))
})

test_that("vintage_curve detects March 2023 spike", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res <- vintage_curve(con)
  
  # Anomaly 3: March 2023 cohort should have >6% delinquency in MOB 1
  # Use month/year extraction to avoid POSIXct vs Date comparison issues
  march_mob1 <- res |> 
    dplyr::filter(lubridate::month(app_month) == 3, 
                  lubridate::year(app_month) == 2023, 
                  mob == 1)
  
  # Ensure we actually got rows before checking the value
  expect_gt(nrow(march_mob1), 0)
  expect_gt(march_mob1$delinq_rate[1], 0.06)
})