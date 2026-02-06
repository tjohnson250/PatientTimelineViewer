# Test script for cancellation feature
# This script demonstrates that the cancellation mechanism works correctly

library(DBI)
library(dplyr)

# Source the necessary files
source("R/db_queries.R")

# Connect to the sample database directly
cat("Connecting to sample database...\n")
cdw_path <- "inst/extdata/pcornet_cdw.duckdb"
mpi_path <- "inst/extdata/mpi.duckdb"

if (!file.exists(cdw_path)) {
  stop("Sample CDW database not found at: ", cdw_path)
}

# Create connections manually
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
cat("Finding a sample patient...\n")
sample_patients <- DBI::dbGetQuery(conns$cdw, "SELECT PATID FROM DEMOGRAPHIC LIMIT 5")
if (nrow(sample_patients) == 0) {
  stop("No patients found in database")
}
patid <- sample_patients$PATID[1]
cat("Using patient ID:", patid, "\n\n")

# Test 1: Load without cancellation (normal operation)
cat("===== Test 1: Normal load (no cancellation) =====\n")
start_time <- Sys.time()
data1 <- load_patient_data(conns, patid)
end_time <- Sys.time()
cat("Load completed in", round(difftime(end_time, start_time, units = "secs"), 2), "seconds\n")
cat("Result is NULL:", is.null(data1), "\n")
if (!is.null(data1)) {
  cat("Demographic records:", nrow(data1$demographic), "\n")
  cat("Encounter records:", nrow(data1$encounters), "\n")
  cat("Diagnosis records:", nrow(data1$diagnoses), "\n")
}
cat("\n")

# Test 2: Load with cancellation flag set immediately
cat("===== Test 2: Immediate cancellation =====\n")
cancel_flag <- TRUE
start_time <- Sys.time()
data2 <- load_patient_data(
  conns,
  patid,
  cancel_check = function() cancel_flag
)
end_time <- Sys.time()
cat("Load completed in", round(difftime(end_time, start_time, units = "secs"), 2), "seconds\n")
cat("Result is NULL:", is.null(data2), "\n")
cat("(Should be NULL because cancellation was requested)\n\n")

# Test 3: Load with delayed cancellation
cat("===== Test 3: Delayed cancellation =====\n")
cancel_flag <- FALSE
# Set up a timer to cancel after 0.1 seconds
start_time <- Sys.time()
future_time <- start_time + 0.1

data3 <- load_patient_data(
  conns,
  patid,
  cancel_check = function() {
    # Cancel after 0.1 seconds
    should_cancel <- Sys.time() > future_time
    if (should_cancel && !cancel_flag) {
      cat("  [Cancellation triggered after",
          round(difftime(Sys.time(), start_time, units = "secs"), 3),
          "seconds]\n")
      cancel_flag <<- TRUE
    }
    cancel_flag
  }
)
end_time <- Sys.time()
cat("Load completed in", round(difftime(end_time, start_time, units = "secs"), 2), "seconds\n")
cat("Result is NULL:", is.null(data3), "\n")
cat("(May or may not be NULL depending on timing)\n\n")

# Test 4: Verify cancellation doesn't break subsequent loads
cat("===== Test 4: Load after cancellation =====\n")
cancel_flag <- FALSE
start_time <- Sys.time()
data4 <- load_patient_data(conns, patid)
end_time <- Sys.time()
cat("Load completed in", round(difftime(end_time, start_time, units = "secs"), 2), "seconds\n")
cat("Result is NULL:", is.null(data4), "\n")
if (!is.null(data4)) {
  cat("Demographic records:", nrow(data4$demographic), "\n")
  cat("(Successfully loaded after previous cancellation)\n")
}
cat("\n")

# Clean up
DBI::dbDisconnect(conns$cdw, shutdown = TRUE)
if (!identical(conns$cdw, conns$mpi)) {
  DBI::dbDisconnect(conns$mpi, shutdown = TRUE)
}

cat("===== All tests completed =====\n")
cat("Summary:\n")
cat("- Test 1 (normal): ", if(is.null(data1)) "FAILED" else "PASSED", "\n")
cat("- Test 2 (immediate cancel): ", if(is.null(data2)) "PASSED" else "FAILED", "\n")
cat("- Test 3 (delayed cancel): ", if(is.null(data3)) "PASSED (cancelled)" else "COMPLETED (faster than 0.1s)", "\n")
cat("- Test 4 (after cancel): ", if(is.null(data4)) "FAILED" else "PASSED", "\n")
