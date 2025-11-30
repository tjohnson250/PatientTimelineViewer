# filter_helpers.R
# Filtering functions for timeline events

library(dplyr)
library(stringr)

#' Filter events by event type
#' @param events Data frame of timeline events
#' @param selected_types Character vector of selected event types
#' @return Filtered data frame
filter_by_event_type <- function(events, selected_types) {
  if (is.null(selected_types) || length(selected_types) == 0) {
    return(events[0, ])  # Return empty if nothing selected
  }
  
  # Map UI checkboxes to event types
  type_mapping <- c(
    "encounters" = "encounter",
    "diagnoses" = "diagnosis",
    "procedures" = "procedure",
    "labs" = "lab",
    "prescribing" = "prescribing",
    "dispensing" = "dispensing",
    "vitals" = "vital",
    "conditions" = "condition"
  )
  
  # Always include death marker if present
  active_types <- c(type_mapping[selected_types], "death")
  
  events %>%
    filter(event_type %in% active_types)
}

#' Filter events by date range
#' @param events Data frame of timeline events
#' @param start_date Start of date range
#' @param end_date End of date range
#' @return Filtered data frame
filter_by_date_range <- function(events, start_date, end_date) {
  if (is.null(start_date) && is.null(end_date)) return(events)
  
  events %>%
    filter(
      (is.null(start_date) | start >= start_date) &
      (is.null(end_date) | start <= end_date)
    )
}

#' Filter events by encounter type
#' @param events Data frame of timeline events
#' @param patient_data Full patient data list (needed to get encounter info)
#' @param enc_types Character vector of encounter types to include
#' @return Filtered data frame
filter_by_encounter_type <- function(events, patient_data, enc_types) {
  if (is.null(enc_types) || length(enc_types) == 0 || 
      "ALL" %in% enc_types || length(enc_types) == 0) {
    return(events)
  }
  
  # Get encounter IDs matching the selected types
  valid_enc_ids <- patient_data$encounters %>%
    filter(ENC_TYPE %in% enc_types) %>%
    pull(ENCOUNTERID)
  
  # Filter encounters directly
  enc_events <- events %>%
    filter(event_type == "encounter") %>%
    filter(source_key %in% valid_enc_ids)
  
  # For linked events (diagnoses, procedures, labs), filter by encounter
  linked_enc_ids <- c(
    patient_data$diagnoses$ENCOUNTERID,
    patient_data$procedures$ENCOUNTERID,
    patient_data$labs$ENCOUNTERID,
    patient_data$vitals$ENCOUNTERID
  )
  
  # Keep events that are either encounters matching type, 

  # or events linked to those encounters,
  # or events that don't have encounter linkage (prescribing, dispensing, conditions)
  events %>%
    filter(
      (event_type == "encounter" & source_key %in% valid_enc_ids) |
      (event_type %in% c("diagnosis", "procedure", "lab", "vital") & 
         # This requires looking up the encounter ID - simplified version
         TRUE) |
      (event_type %in% c("prescribing", "dispensing", "condition", "death"))
    )
}

#' Filter diagnoses by code pattern
#' @param events Data frame of timeline events
#' @param patient_data Full patient data list
#' @param pattern SQL LIKE pattern (e.g., "E11%")
#' @return Filtered data frame
filter_by_dx_pattern <- function(events, patient_data, pattern) {
  if (is.null(pattern) || pattern == "") return(events)
  
  # Convert SQL LIKE pattern to regex
  regex_pattern <- pattern %>%
    str_replace_all("%", ".*") %>%
    str_replace_all("_", ".") %>%
    paste0("^", ., "$")
  
  # Get diagnosis IDs matching pattern
  matching_dx_ids <- patient_data$diagnoses %>%
    filter(str_detect(DX, regex_pattern)) %>%
    pull(DIAGNOSISID)
  
  # Filter: keep non-diagnosis events + matching diagnoses
  events %>%
    filter(
      event_type != "diagnosis" |
      source_key %in% matching_dx_ids
    )
}

#' Filter procedures by code pattern
#' @param events Data frame of timeline events
#' @param patient_data Full patient data list
#' @param pattern SQL LIKE pattern
#' @return Filtered data frame
filter_by_px_pattern <- function(events, patient_data, pattern) {
  if (is.null(pattern) || pattern == "") return(events)
  
  regex_pattern <- pattern %>%
    str_replace_all("%", ".*") %>%
    str_replace_all("_", ".") %>%
    paste0("^", ., "$")
  
  matching_px_ids <- patient_data$procedures %>%
    filter(str_detect(PX, regex_pattern)) %>%
    pull(PROCEDURESID)
  
  events %>%
    filter(
      event_type != "procedure" |
      source_key %in% matching_px_ids
    )
}

#' Filter labs by name pattern
#' @param events Data frame of timeline events
#' @param patient_data Full patient data list
#' @param pattern Partial match pattern
#' @return Filtered data frame
filter_by_lab_name <- function(events, patient_data, pattern) {
  if (is.null(pattern) || pattern == "") return(events)
  
  pattern_lower <- tolower(pattern)
  
  matching_lab_ids <- patient_data$labs %>%
    filter(
      str_detect(tolower(coalesce(RAW_LAB_NAME, "")), pattern_lower) |
      str_detect(tolower(coalesce(LAB_LOINC, "")), pattern_lower)
    ) %>%
    pull(LAB_RESULT_CM_ID)
  
  events %>%
    filter(
      event_type != "lab" |
      source_key %in% matching_lab_ids
    )
}

#' Filter medications by name pattern
#' @param events Data frame of timeline events
#' @param patient_data Full patient data list
#' @param pattern Partial match pattern
#' @return Filtered data frame
filter_by_med_name <- function(events, patient_data, pattern) {
  if (is.null(pattern) || pattern == "") return(events)
  
  pattern_lower <- tolower(pattern)
  
  # Filter prescribing
  matching_rx_ids <- patient_data$prescribing %>%
    filter(str_detect(tolower(coalesce(RAW_RX_MED_NAME, "")), pattern_lower)) %>%
    pull(PRESCRIBINGID)
  
  # Filter dispensing
  matching_disp_ids <- patient_data$dispensing %>%
    filter(str_detect(tolower(coalesce(RAW_DISP_MED_NAME, "")), pattern_lower)) %>%
    pull(DISPENSINGID)
  
  events %>%
    filter(
      !(event_type %in% c("prescribing", "dispensing")) |
      (event_type == "prescribing" & source_key %in% matching_rx_ids) |
      (event_type == "dispensing" & source_key %in% matching_disp_ids)
    )
}

#' Get event type counts from raw data
#' @param patient_data List of patient data frames
#' @return Named list with counts
get_event_type_counts <- function(patient_data) {
  list(
    encounters = nrow(patient_data$encounters),
    diagnoses = nrow(patient_data$diagnoses),
    procedures = nrow(patient_data$procedures),
    labs = nrow(patient_data$labs),
    prescribing = nrow(patient_data$prescribing),
    dispensing = nrow(patient_data$dispensing),
    vitals = nrow(patient_data$vitals),
    conditions = nrow(patient_data$conditions)
  )
}

#' Get unique encounter types from data
#' @param encounters Encounters data frame
#' @return Character vector of unique encounter types
get_encounter_types <- function(encounters) {
  if (nrow(encounters) == 0) return(character(0))
  
  enc_types <- unique(encounters$ENC_TYPE)
  enc_types <- enc_types[!is.na(enc_types)]
  sort(enc_types)
}

#' Apply all filters to events
#' @param events Data frame of timeline events
#' @param patient_data Full patient data list
#' @param filters Named list of filter values
#' @return Filtered data frame
apply_all_filters <- function(events, patient_data, filters) {
  result <- events
  
  # Event type filter
  if (!is.null(filters$event_types)) {
    result <- filter_by_event_type(result, filters$event_types)
  }
  
  # Date range filter
  if (!is.null(filters$start_date) || !is.null(filters$end_date)) {
    result <- filter_by_date_range(result, filters$start_date, filters$end_date)
  }
  
  # Diagnosis pattern filter
  if (!is.null(filters$dx_pattern) && filters$dx_pattern != "") {
    result <- filter_by_dx_pattern(result, patient_data, filters$dx_pattern)
  }
  
  # Procedure pattern filter
  if (!is.null(filters$px_pattern) && filters$px_pattern != "") {
    result <- filter_by_px_pattern(result, patient_data, filters$px_pattern)
  }
  
  # Lab name filter
  if (!is.null(filters$lab_name) && filters$lab_name != "") {
    result <- filter_by_lab_name(result, patient_data, filters$lab_name)
  }
  
  # Medication name filter
  if (!is.null(filters$med_name) && filters$med_name != "") {
    result <- filter_by_med_name(result, patient_data, filters$med_name)
  }
  
  result
}

#' Get date range from events
#' @param patient_data List of patient data frames
#' @return List with min and max dates
get_date_range <- function(patient_data) {
  # Helper to safely extract dates from a column
  extract_dates <- function(df, col) {
    if (is.null(df) || nrow(df) == 0 || !col %in% names(df)) return(NULL)
    vals <- df[[col]]
    if (is.null(vals) || length(vals) == 0) return(NULL)
    # Convert to Date if POSIXt
    if (inherits(vals, "POSIXt")) vals <- as.Date(vals)
    # If character, try to parse
    if (is.character(vals)) {
      vals <- tryCatch(as.Date(vals), error = function(e) NULL)
    }
    if (!inherits(vals, "Date")) return(NULL)
    vals[!is.na(vals)]
  }
  
  # Collect all dates
  all_dates <- c(
    extract_dates(patient_data$encounters, "ADMIT_DATE"),
    extract_dates(patient_data$diagnoses, "DX_DATE"),
    extract_dates(patient_data$diagnoses, "ADMIT_DATE"),
    extract_dates(patient_data$procedures, "PX_DATE"),
    extract_dates(patient_data$procedures, "ADMIT_DATE"),
    extract_dates(patient_data$labs, "RESULT_DATE"),
    extract_dates(patient_data$prescribing, "RX_START_DATE"),
    extract_dates(patient_data$prescribing, "RX_ORDER_DATE"),
    extract_dates(patient_data$dispensing, "DISPENSE_DATE"),
    extract_dates(patient_data$vitals, "MEASURE_DATE"),
    extract_dates(patient_data$conditions, "ONSET_DATE"),
    extract_dates(patient_data$conditions, "REPORT_DATE"),
    extract_dates(patient_data$death, "DEATH_DATE")
  )
  
  # Convert back to Date class (c() drops the class)
  if (length(all_dates) > 0) {
    all_dates <- as.Date(all_dates, origin = "1970-01-01")
  }
  
  if (length(all_dates) == 0) {
    return(list(min = Sys.Date() - 365, max = Sys.Date()))
  }
  
  list(
    min = min(all_dates, na.rm = TRUE),
    max = max(all_dates, na.rm = TRUE)
  )
}
