test_that("get_timeline_groups returns correct structure", {
  groups <- get_timeline_groups()

  expect_s3_class(groups, "data.frame")
  expect_true("id" %in% names(groups))
  expect_true("content" %in% names(groups))
  expect_equal(nrow(groups), 8)
  expect_true("encounters" %in% groups$id)
  expect_true("diagnoses" %in% groups$id)
  expect_true("procedures" %in% groups$id)
  expect_true("labs" %in% groups$id)
})

test_that("transform_all_to_timevis handles empty data", {
  empty_data <- list(
    demographic = data.frame(),
    encounters = data.frame(),
    diagnoses = data.frame(),
    procedures = data.frame(),
    labs = data.frame(),
    prescribing = data.frame(),
    dispensing = data.frame(),
    vitals = data.frame(),
    conditions = data.frame(),
    death = data.frame(),
    death_cause = data.frame()
  )

  result <- transform_all_to_timevis(empty_data)
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
})

test_that("transform_all_to_timevis returns correct columns", {
  skip_if_not_installed("duckdb")

  # Load sample data
  cdw_path <- get_sample_data_path("cdw")
  skip_if(cdw_path == "", "Sample data not available")

  con <- DBI::dbConnect(duckdb::duckdb(), cdw_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con))

  # Get a patient with data
  patid <- DBI::dbGetQuery(con, "SELECT PATID FROM DEMOGRAPHIC LIMIT 1")$PATID[1]
  skip_if(is.na(patid), "No patients in sample data")

  # Load patient data manually
  patient_data <- list(
    demographic = DBI::dbGetQuery(con, paste0("SELECT * FROM DEMOGRAPHIC WHERE PATID = '", patid, "'")),
    encounters = DBI::dbGetQuery(con, paste0("SELECT * FROM ENCOUNTER WHERE PATID = '", patid, "'")),
    diagnoses = DBI::dbGetQuery(con, paste0("SELECT * FROM DIAGNOSIS WHERE PATID = '", patid, "'")),
    procedures = DBI::dbGetQuery(con, paste0("SELECT * FROM PROCEDURES WHERE PATID = '", patid, "'")),
    labs = DBI::dbGetQuery(con, paste0("SELECT * FROM LAB_RESULT_CM WHERE PATID = '", patid, "'")),
    prescribing = DBI::dbGetQuery(con, paste0("SELECT * FROM PRESCRIBING WHERE PATID = '", patid, "'")),
    dispensing = DBI::dbGetQuery(con, paste0("SELECT * FROM DISPENSING WHERE PATID = '", patid, "'")),
    vitals = DBI::dbGetQuery(con, paste0("SELECT * FROM VITAL WHERE PATID = '", patid, "'")),
    conditions = DBI::dbGetQuery(con, paste0("SELECT * FROM CONDITION WHERE PATID = '", patid, "'")),
    death = DBI::dbGetQuery(con, paste0("SELECT * FROM DEATH WHERE PATID = '", patid, "'")),
    death_cause = DBI::dbGetQuery(con, paste0("SELECT * FROM DEATH_CAUSE WHERE PATID = '", patid, "'"))
  )

  result <- transform_all_to_timevis(patient_data)

  expect_s3_class(result, "data.frame")
  expect_true("id" %in% names(result))
  expect_true("content" %in% names(result))
  expect_true("start" %in% names(result))
  expect_true("group" %in% names(result))
  expect_true("event_type" %in% names(result))
})
