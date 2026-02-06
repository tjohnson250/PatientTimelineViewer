# Verbose test to show cancellation happening mid-load
# This demonstrates that the cancellation checks work between queries

library(DBI)
library(dplyr)

# Source the necessary files
source("R/db_queries.R")

# Connect to the sample database directly
cat("Connecting to sample database...\n")
cdw_path <- "inst/extdata/pcornet_cdw.duckdb"
mpi_path <- "inst/extdata/mpi.duckdb"

cdw_conn <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = cdw_path,
  read_only = TRUE
)

if (file.exists(mpi_path)) {
  mpi_conn <- DBI::dbConnect(
    duckdb::duckdb(),
    dbdir = mpi_path,
    read_only = TRUE
  )
} else {
  mpi_conn <- cdw_conn
}

conns <- list(
  cdw = cdw_conn,
  mpi = mpi_conn,
  db_type = "duckdb"
)

# Set the db_type in package state
.pkg_state$db_type <- "duckdb"

# Get a sample patient ID
sample_patients <- DBI::dbGetQuery(conns$cdw, "SELECT PATID FROM DEMOGRAPHIC LIMIT 1")
patid <- sample_patients$PATID[1]

cat("\n===== Demonstrating Mid-Load Cancellation =====\n")
cat("Patient ID:", patid, "\n")
cat("Loading will be cancelled after 3 checks...\n\n")

# Create a counter to track how many times the cancel check is called
check_count <- 0
cancel_after <- 3

start_time <- Sys.time()
result <- load_patient_data(
  conns,
  patid,
  cancel_check = function() {
    check_count <<- check_count + 1
    should_cancel <- check_count >= cancel_after

    if (should_cancel && check_count == cancel_after) {
      cat("\n>>> CANCELLATION REQUESTED after", check_count, "queries <<<\n\n")
    } else {
      cat("Cancel check", check_count, "- continuing...\n")
    }

    return(should_cancel)
  }
)
end_time <- Sys.time()

cat("\n===== Results =====\n")
cat("Total cancel checks performed:", check_count, "\n")
cat("Time elapsed:", round(difftime(end_time, start_time, units = "secs"), 3), "seconds\n")
cat("Result is NULL:", is.null(result), "\n")
cat("\nExpected: NULL (TRUE) because we cancelled after", cancel_after, "queries\n")
cat("Actual: ", if(is.null(result)) "PASSED ✓" else "FAILED ✗", "\n")

# Test that subsequent loads still work
cat("\n===== Verify Normal Load Still Works =====\n")
result2 <- load_patient_data(conns, patid)
cat("Result is NULL:", is.null(result2), "\n")
if (!is.null(result2)) {
  cat("Successfully loaded", nrow(result2$demographic), "demographic record(s)\n")
  cat("Status: PASSED ✓\n")
} else {
  cat("Status: FAILED ✗\n")
}

# Clean up
DBI::dbDisconnect(conns$cdw, shutdown = TRUE)
if (!identical(conns$cdw, conns$mpi)) {
  DBI::dbDisconnect(conns$mpi, shutdown = TRUE)
}

cat("\n===== Cancellation Feature Test Complete =====\n")
