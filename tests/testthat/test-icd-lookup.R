test_that("bundled ICD lookup data is available", {
  expect_true(icd_data_available())
  expect_match(lookup_icd_description("E11.9", "10"), "diabetes", ignore.case = TRUE)
  expect_match(lookup_icd_description("250.00", "09"), "DMII|diabetes", ignore.case = TRUE)
})

test_that("vectorized ICD lookup handles mixed code systems", {
  descriptions <- lookup_icd_descriptions(c("I10", "401.9"), c("10", "09"))
  expect_length(descriptions, 2)
  expect_false(any(is.na(descriptions)))
})
