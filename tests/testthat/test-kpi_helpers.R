db_path <- function() {
  path <- file.path("inst", "testdata", "lendops.duckdb")
  if (!file.exists(path)) {
    path <- file.path("..", "..", "inst", "testdata", "lendops.duckdb")
  }
  path
}

test_that("kpi_summary calculates correct metrics", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res <- kpi_summary(con)
  
  expect_s3_class(res, "data.frame")
  expect_true(all(c("total_applications", "approval_rate", "total_disbursed_amt") %in% names(res)))
  
  # Total applications should be 12000
  expect_equal(res$total_applications, 12000)
  
  # Approval rate should be between 0.5 and 0.65 due to the injected shift
  expect_true(res$approval_rate > 0.50 & res$approval_rate < 0.65)
  
  # Average ticket size should be positive
  expect_gt(res$avg_ticket_size, 0)
})

test_that("kpi_summary filters work", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res_all <- kpi_summary(con)
  res_gulshan <- kpi_summary(con, branch = "Gulshan")
  
  # Gulshan should have fewer apps than all branches
  expect_lt(res_gulshan$total_applications, res_all$total_applications)
})