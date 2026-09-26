-- Create Tables
CREATE TABLE IF NOT EXISTS applications (
    app_id VARCHAR,
    app_month DATE,
    branch VARCHAR,
    sector VARCHAR,
    rm_id VARCHAR,
    purpose VARCHAR,
    requested_amt DOUBLE,
    final_status VARCHAR,
    decline_reason VARCHAR,
    loan_id VARCHAR
);

CREATE TABLE IF NOT EXISTS application_stages (
    app_id VARCHAR,
    stage VARCHAR,
    entry_ts TIMESTAMP,
    exit_ts TIMESTAMP
);

CREATE TABLE IF NOT EXISTS loan_performance (
    loan_id VARCHAR,
    snapshot_month DATE,
    dpd INTEGER,
    outstanding_balance DOUBLE
);

CREATE TABLE IF NOT EXISTS targets (
    target_month DATE,
    branch VARCHAR,
    target_disbursement_amt DOUBLE,
    target_approval_rate DOUBLE
);

-- Create Indexes for query performance (important for SQL skill demonstration)
CREATE INDEX IF NOT EXISTS idx_app_id ON applications(app_id);
CREATE INDEX IF NOT EXISTS idx_stage_app_id ON application_stages(app_id);
CREATE INDEX IF NOT EXISTS idx_perf_loan_id ON loan_performance(loan_id);

-- Create a View for the Shiny app to consume easily
CREATE VIEW IF NOT EXISTS vw_disbursed_loans AS
SELECT 
    a.app_id, 
    a.app_month, 
    a.branch, 
    a.sector, 
    a.loan_id, 
    a.requested_amt,
    p.snapshot_month,
    p.dpd,
    p.outstanding_balance
FROM applications a
JOIN loan_performance p ON a.loan_id = p.loan_id;