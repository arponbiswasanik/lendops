library(dplyr)
library(lubridate)
library(tibble)

set.seed(5678) # Different seed for performance randomness

# --- 1. Load Origination Data ---
# We only care about disbursed loans for the performance table
load("data/app_data.rda") 
disbursed_loans <- app_data |>
  filter(final_status == "Disbursed") |>
  mutate(disb_month = app_month) # Assuming disbursement happens in the same month

# --- 2. Simulation Setup ---
# DPD States: 0=Current, 1=DPD 1-30, 2=DPD 31-60, 3=DPD 61-90, 4=DPD 90+
# Designed Ground Truth Probabilities (Markov transitions)
trans_prob <- matrix(
  c(0.96, 0.04, 0.00, 0.00, 0.00,  # From 0: 96% stay Current, 4% go to 1-30
    0.75, 0.00, 0.25, 0.00, 0.00,  # From 1: 75% Cure to 0, 25% worsen to 31-60
    0.00, 0.00, 0.60, 0.40, 0.00,  # From 2: 60% stay 31-60, 40% worsen to 61-90
    0.00, 0.00, 0.00, 0.40, 0.60,  # From 3: 40% stay 61-90, 60% worsen to 90+
    0.00, 0.00, 0.00, 0.00, 1.00), # From 4: 90+ is an absorbing state (Default)
  nrow = 5, byrow = TRUE
)

# --- 3. Inject Anomaly 3: Vintage Delinquency Spike ---
# March 2023 cohort has 8% chance of going delinquent in first 3 months instead of 4%
vintage_spike_month <- as.Date("2023-03-01")

# Simulate 18 months of performance for each loan
max_months <- 18

generate_performance <- function(loan) {
  current_state <- 0 # Start Current
  current_balance <- loan$requested_amt
  monthly_principal <- loan$requested_amt / 24 # Assume 2-year straight-line amortization
  
  history <- list()
  
  for (m in 1:max_months) {
    snap_month <- loan$disb_month %m+% months(m - 1)
    
    # Stop if balance is 0 (fully paid)
    if (current_balance <= 0) break
    
    # Apply Anomaly 3: Vintage Spike
    prob_0_to_1 <- ifelse(loan$app_month == vintage_spike_month && m <= 3, 0.08, 0.04)
    
    # Adjust transition matrix dynamically
    custom_trans <- trans_prob
    custom_trans[1, 2] <- prob_0_to_1
    custom_trans[1, 1] <- 1 - prob_0_to_1
    
    # Roll the dice for the next state
    current_state <- sample(1:5, 1, prob = custom_trans[(current_state + 1), ]) - 1
    
    # Update balance (loans in 90+ stop paying)
    if (current_state < 4) {
      current_balance <- max(0, current_balance - monthly_principal)
    }
    
    history[[m]] <- tibble(
      loan_id = loan$loan_id,
      snapshot_month = snap_month,
      dpd = current_state,
      outstanding_balance = round(current_balance, 2)
    )
  }
  bind_rows(history)
}

# --- 4. Run Simulation ---
# This might take a few seconds for 8,500 loans
cat("Simulating performance for", nrow(disbursed_loans), "loans...\n")
perf_data_list <- lapply(1:nrow(disbursed_loans), function(i) {
  if (i %% 1000 == 0) cat(i, "loans processed...\n")
  generate_performance(disbursed_loans[i, ])
})

perf_data <- dplyr::bind_rows(perf_data_list)

# --- 5. Invariants (Self-Checking) ---
stopifnot(nrow(perf_data) > 85000) # Should be ~100k+ rows
stopifnot(all(unique(perf_data$loan_id) %in% disbursed_loans$loan_id))

# --- 6. Save Data and Update Oracle ---
usethis::use_data(perf_data, overwrite = TRUE)

# Append to the existing oracle
oracle <- readRDS("inst/testdata/oracle.rds")
oracle$anomaly_3 <- list(
  type = "Vintage Delinquency Spike", 
  cohort_month = vintage_spike_month, 
  early_month_prob = 0.08, 
  base_prob = 0.04
)
saveRDS(oracle, "inst/testdata/oracle.rds")

cat("Portfolio performance data generated and Oracle updated.\n")