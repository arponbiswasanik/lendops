# Helper to find the database robustly
db_path <- function() {
  # Looks in inst/testdata relative to the project root
  path <- file.path("inst", "testdata", "lendops.duckdb")
  if (!file.exists(path)) {
    # Fallback for when testthat runs in a subdirectory
    path <- file.path("..", "..", "inst", "testdata", "lendops.duckdb")
  }
  path
}

test_that("funnel_summary returns correct stages and counts", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res <- funnel_summary(con)
  
  expect_s3_class(res, "data.frame")
  expect_true(all(c("stage", "n") %in% names(res)))
  expect_true("Documentation" %in% res$stage)
  expect_true(res$n[res$stage == "Received"] > 0)
})

test_that("tat_summary calculates hours and catches bottleneck", {
  skip_if_not(file.exists(db_path()))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  
  res <- tat_summary(con)
  
  expect_s3_class(res, "data.frame")
  expect_true(all(c("stage", "branch", "avg_tat_hours") %in% names(res)))
  
  # Check that TAT is numeric and positive
  expect_true(is.numeric(res$avg_tat_hours))
  expect_true(all(res$avg_tat_hours > 0, na.rm = TRUE))
  
  # Verify the injected anomaly: Gulshan Documentation TAT should be ~96 hours (2x of 48)
  gulshan_doc_tat <- res$avg_tat_hours[res$stage == "Documentation" & res$branch == "Gulshan"]
  expect_gt(gulshan_doc_tat, 75) # Averages ~80 due to approval rate shift interaction
})