test_that("get_event_type_counts returns correct structure", {
  patient_data <- list(
    encounters = data.frame(ENCOUNTERID = 1:5),
    diagnoses = data.frame(DIAGNOSISID = 1:10),
    procedures = data.frame(PROCEDURESID = 1:3),
    labs = data.frame(LAB_RESULT_CM_ID = 1:8),
    prescribing = data.frame(PRESCRIBINGID = 1:2),
    dispensing = data.frame(DISPENSINGID = 1:4),
    vitals = data.frame(VITALID = 1:6),
    conditions = data.frame(CONDITIONID = 1:1)
  )

  counts <- get_event_type_counts(patient_data)

  expect_type(counts, "list")
  expect_equal(counts$encounters, 5)
  expect_equal(counts$diagnoses, 10)
  expect_equal(counts$procedures, 3)
  expect_equal(counts$labs, 8)
  expect_equal(counts$prescribing, 2)
  expect_equal(counts$dispensing, 4)
  expect_equal(counts$vitals, 6)
  expect_equal(counts$conditions, 1)
})

test_that("apply_all_filters handles empty filters", {
  events <- data.frame(
    id = c("1", "2", "3"),
    start = c("2020-01-01", "2020-02-01", "2020-03-01"),
    event_type = c("diagnosis", "encounter", "lab"),
    stringsAsFactors = FALSE
  )

  patient_data <- list(
    encounters = data.frame(),
    diagnoses = data.frame(),
    procedures = data.frame(),
    labs = data.frame(),
    prescribing = data.frame(),
    dispensing = data.frame()
  )

  # Empty filters should return all events
  result <- apply_all_filters(events, patient_data, list())
  expect_equal(nrow(result), 3)
})

test_that("get_date_range returns correct structure", {
  patient_data <- list(
    demographic = data.frame(BIRTH_DATE = as.Date("1980-01-01")),
    encounters = data.frame(ADMIT_DATE = as.Date(c("2020-01-01", "2021-06-15"))),
    diagnoses = data.frame(DX_DATE = as.Date("2020-03-01"), ADMIT_DATE = NA),
    procedures = data.frame(PX_DATE = as.Date("2020-05-01"), ADMIT_DATE = NA),
    labs = data.frame(RESULT_DATE = as.Date("2021-01-01")),
    prescribing = data.frame(RX_START_DATE = NA, RX_ORDER_DATE = as.Date("2020-08-01")),
    dispensing = data.frame(DISPENSE_DATE = as.Date("2020-09-01")),
    vitals = data.frame(MEASURE_DATE = as.Date("2020-04-01")),
    conditions = data.frame(ONSET_DATE = NA, REPORT_DATE = as.Date("2020-02-01")),
    death = data.frame()
  )

  range <- get_date_range(patient_data)

  expect_type(range, "list")
  expect_true("min" %in% names(range))
  expect_true("max" %in% names(range))
  expect_s3_class(range$min, "Date")
  expect_s3_class(range$max, "Date")
  expect_equal(range$min, as.Date("1980-01-01"))
  expect_equal(range$max, as.Date("2021-06-15"))
})
