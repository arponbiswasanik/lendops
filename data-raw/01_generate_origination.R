library(dplyr)
library(lubridate)
library(tibble)

set.seed(1234) # Reproducibility

# --- 1. Static Dimensions (reused from scorewright context) ---
branches <- c("Gulshan", "Dhanmondi", "Motijheel", "Chattogram", "Sylhet", "Khulna", "Rajshahi", "Mirpur")
sectors <- c("Manufacturing", "Trading", "Services", "Agro", "Textile", "Construction")
purposes <- c("Working Capital", "Machinery", "Renovation", "Expansion")

n_apps <- 12000
start_date <- as.Date("2023-01-01")

# --- 2. Applications Header Table ---
# Simulating 12000 apps over 18 months
app_data <- tibble(
  app_id = sprintf("APP-%05d", 1:n_apps),
  app_month = start_date + months(sample(0:17, n_apps, replace = TRUE)),
  branch = sample(branches, n_apps, replace = TRUE),
  sector = sample(sectors, n_apps, replace = TRUE),
  rm_id = sprintf("RM-%03d", sample(1:50, n_apps, replace = TRUE)),
  purpose = sample(purposes, n_apps, replace = TRUE),
  requested_amt = round(runif(n_apps, 500000, 5000000), 2)
) |>
  arrange(app_month, app_id)

# --- 3. Inject Anomaly 2: Approval Rate Shift ---
# Pre-registration: Sept 2023 sees a policy shift, approval rate drops from 65% to 50%
approval_shift_date <- as.Date("2023-09-01")
app_data <- app_data |>
  mutate(
    is_approved = ifelse(app_month < approval_shift_date, 
                         sample(c(1,0), n(), replace = TRUE, prob = c(0.65, 0.35)),
                         sample(c(1,0), n(), replace = TRUE, prob = c(0.50, 0.50))),
    final_status = case_when(
      is_approved == 1 ~ "Disbursed",
      TRUE ~ sample(c("Declined", "Withdrawn"), n(), replace = TRUE, prob = c(0.7, 0.3))
    ),
    decline_reason = ifelse(final_status == "Declined", sample(c("Credit Risk", "Income", "Documentation"), n(), replace = TRUE), NA_character_),
    loan_id = ifelse(final_status == "Disbursed", sprintf("LOAN-%05d", 1:sum(is_approved == 1)), NA_character_)
  )

# --- 4. Application Stages Table (Event Log) ---
# Define the standard flow and terminal states
stages <- c("Received", "Screening", "Credit Assessment", "Decision", "Documentation", "Disbursement")
decline_stages <- c("Screening", "Credit Assessment", "Decision") # Stages where apps can be declined

# Base TAT in hours for normal branches (we will convert to timestamps)
tat_base <- c("Received"=2, "Screening"=24, "Credit Assessment"=72, "Decision"=12, "Documentation"=48, "Disbursement"=6)

# --- 5. Inject Anomaly 1: Documentation Bottleneck ---
# Pre-registration: Gulshan & Dhanmondi have ~2x TAT in Documentation from June 2023
doc_bottleneck_date <- as.Date("2023-06-01")

generate_stages <- function(row) {
  current_ts <- as.POSIXct(row$app_month, tz = "UTC") + runif(1, 0, 72) # Start within first 3 days of month
  
  app_stages <- list()
  
  if (row$final_status == "Withdrawn") {
    # Randomly withdraw at any stage before decision
    withdraw_at <- sample(c("Received", "Screening", "Credit Assessment"), 1)
    max_stage_idx <- which(stages == withdraw_at)
    app_stages[[1]] <- list(stage="Received", entry=current_ts, exit=current_ts + hours(tat_base["Received"]))
    if(max_stage_idx >= 2) app_stages[[2]] <- list(stage="Screening", entry=app_stages[[1]]$exit, exit=app_stages[[1]]$exit + hours(tat_base["Screening"]))
    if(max_stage_idx >= 3) app_stages[[3]] <- list(stage="Credit Assessment", entry=app_stages[[2]]$exit, exit=app_stages[[2]]$exit + hours(tat_base["Credit Assessment"]))
    app_stages[[length(app_stages)]]$exit <- NA # Mark as pending/withdrawn at current stage
    
  } else if (row$final_status == "Declined") {
    # Decline at a specific stage
    decline_at <- sample(decline_stages, 1)
    max_stage_idx <- which(stages == decline_at)
    app_stages[[1]] <- list(stage="Received", entry=current_ts, exit=current_ts + hours(tat_base["Received"]))
    if(max_stage_idx >= 2) app_stages[[2]] <- list(stage="Screening", entry=app_stages[[1]]$exit, exit=app_stages[[1]]$exit + hours(tat_base["Screening"]))
    if(max_stage_idx >= 3) app_stages[[3]] <- list(stage="Credit Assessment", entry=app_stages[[2]]$exit, exit=app_stages[[2]]$exit + hours(tat_base["Credit Assessment"]))
    if(max_stage_idx >= 4) app_stages[[4]] <- list(stage="Decision", entry=app_stages[[3]]$exit, exit=app_stages[[3]]$exit + hours(tat_base["Decision"]))
    # Record the declined stage explicitly
    app_stages[[length(app_stages)+1]] <- list(stage="Declined", entry=app_stages[[length(app_stages)]]$exit, exit=NA)
    
  } else {
    # Disbursed - goes through all stages
    for (i in 1:length(stages)) {
      stage_name <- stages[i]
      tat <- tat_base[stage_name]
      
      # Apply Anomaly 1
      if (stage_name == "Documentation" && 
          row$branch %in% c("Gulshan", "Dhanmondi") && 
          row$app_month >= doc_bottleneck_date) {
        tat <- tat * 2 # Double the TAT
      }
      
      entry_ts <- if (i == 1) current_ts else app_stages[[i-1]]$exit
      exit_ts <- entry_ts + hours(tat)
      
      # For the last stage (Disbursement), it stays open (exit = NA) for this demo's simplicity
      # Actually, disbursed means it's completed, so we give it an exit time
      app_stages[[i]] <- list(stage=stage_name, entry=entry_ts, exit=exit_ts)
    }
  }
  
  bind_rows(lapply(app_stages, as_tibble)) |>
    mutate(app_id = row$app_id)
}

# Apply the function using a simple, readable loop
stage_data_list <- lapply(1:nrow(app_data), function(i) {
  generate_stages(app_data[i, ])
})
stage_data <- dplyr::bind_rows(stage_data_list) |>
  dplyr::select(app_id, stage, entry_ts = entry, exit_ts = exit)

# --- 6. Invariants (Self-Checking) ---
# Stop if the data doesn't make sense
stopifnot(nrow(app_data) == 12000)
stopifnot(nrow(stage_data) > 0)
stopifnot(all(unique(stage_data$app_id) %in% app_data$app_id))

# --- 7. Save Data and Oracle ---
dir.create("inst/testdata", showWarnings = FALSE, recursive = TRUE)

# Save the actual data (the Shiny app will use this)
usethis::use_data(app_data, stage_data, overwrite = TRUE)

# Save the Oracle (Ground truth for the blind test - ONLY tests read this)
oracle <- list(
  anomaly_1 = list(type="TAT Bottleneck", branch=c("Gulshan", "Dhanmondi"), 
                   stage="Documentation", start_date=as.Date("2023-06-01"), impact_factor=2.0),
  anomaly_2 = list(type="Approval Rate Shift", start_date=as.Date("2023-09-01"), 
                   old_rate=0.65, new_rate=0.50)
)
saveRDS(oracle, "inst/testdata/oracle.rds")

cat("Origination data and Oracle generated successfully.\n")