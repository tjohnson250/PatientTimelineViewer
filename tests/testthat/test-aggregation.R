test_that("aggregate_events returns unchanged data for individual level", {
  events <- data.frame(
    id = c("1", "2", "3"),
    content = c("Event 1", "Event 2", "Event 3"),
    start = c("2020-01-01", "2020-01-01", "2020-01-02"),
    end = c(NA, NA, NA),
    group = c("diagnoses", "diagnoses", "labs"),
    type = c("box", "box", "box"),
    className = c("event-diagnosis", "event-diagnosis", "event-lab"),
    title = c("", "", ""),
    source_table = c("DIAGNOSIS", "DIAGNOSIS", "LAB_RESULT_CM"),
    source_key = c("D1", "D2", "L1"),
    event_type = c("diagnosis", "diagnosis", "lab"),
    stringsAsFactors = FALSE
  )

  result <- aggregate_events(events, "individual")
  expect_equal(nrow(result), 3)
  expect_equal(result$id, events$id)
})

test_that("aggregate_events handles empty events", {
  events <- data.frame(
    id = character(),
    content = character(),
    start = character(),
    end = character(),
    group = character(),
    type = character(),
    className = character(),
    title = character(),
    source_table = character(),
    source_key = character(),
    event_type = character(),
    stringsAsFactors = FALSE
  )

  result <- aggregate_events(events, "daily")
  expect_equal(nrow(result), 0)
})

test_that("aggregate_events preserves range events", {
  events <- data.frame(
    id = c("1", "2"),
    content = c("Encounter", "Diagnosis"),
    start = c("2020-01-01", "2020-01-01"),
    end = c("2020-01-05", NA),
    group = c("encounters", "diagnoses"),
    type = c("range", "box"),
    className = c("event-encounter", "event-diagnosis"),
    title = c("", ""),
    source_table = c("ENCOUNTER", "DIAGNOSIS"),
    source_key = c("E1", "D1"),
    event_type = c("encounter", "diagnosis"),
    stringsAsFactors = FALSE
  )

  result <- aggregate_events(events, "daily")

  # Range event should be preserved
  range_events <- result[result$type == "range", ]
  expect_equal(nrow(range_events), 1)
  expect_equal(range_events$event_type, "encounter")
})

test_that("aggregate_events preserves death and birth markers", {
  events <- data.frame(
    id = c("1", "2", "3"),
    content = c("Birth", "Death", "Diagnosis"),
    start = c("1980-01-01", "2020-12-31", "2020-01-01"),
    end = c(NA, NA, NA),
    group = c(NA, NA, "diagnoses"),
    type = c("box", "box", "box"),
    className = c("event-birth", "event-death", "event-diagnosis"),
    title = c("", "", ""),
    source_table = c("DEMOGRAPHIC", "DEATH", "DIAGNOSIS"),
    source_key = c("B1", "D1", "DX1"),
    event_type = c("birth", "death", "diagnosis"),
    stringsAsFactors = FALSE
  )

  result <- aggregate_events(events, "daily")

  # Birth and death should be preserved
  special_events <- result[result$event_type %in% c("birth", "death"), ]
  expect_equal(nrow(special_events), 2)
})
