# filter_helpers.R
# Filtering functions for timeline events

#' @importFrom dplyr `%>%` filter pull
#' @importFrom stringr str_detect str_to_lower
NULL

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
  
  # Always include death and birth markers if present
  active_types <- c(type_mapping[selected_types], "death", "birth")

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
  # Always keep birth and death markers
  events %>%
    filter(
      (event_type == "encounter" & source_key %in% valid_enc_ids) |
      (event_type %in% c("diagnosis", "procedure", "lab", "vital") &
         # This requires looking up the encounter ID - simplified version
         TRUE) |
      (event_type %in% c("prescribing", "dispensing", "condition", "death", "birth"))
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
#'
#' Count the number of events of each type in the patient data.
#'
#' @param patient_data List of patient data frames from \code{\link{load_patient_data}}
#'
#' @return Named list with counts for each event type:
#'   encounters, diagnoses, procedures, labs, prescribing,
#'   dispensing, vitals, conditions
#'
#' @examples
#' \dontrun{
#' data <- load_patient_data(conns, "PAT0000001")
#' counts <- get_event_type_counts(data)
#' print(counts$diagnoses)
#' }
#'
#' @export
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
#' @export
get_encounter_types <- function(encounters) {
  if (nrow(encounters) == 0) return(character(0))

  enc_types <- unique(encounters$ENC_TYPE)
  enc_types <- enc_types[!is.na(enc_types)]
  sort(enc_types)
}

#' Get unique source systems from patient data
#'
#' Collects unique CDW_Source values from all clinical event tables
#' and returns a summary with counts and descriptions.
#'
#' @param patient_data List of patient data frames from \code{\link{load_patient_data}}
#'
#' @return Data frame with columns:
#'   \describe{
#'     \item{source_code}{CDW_Source code}
#'     \item{count}{Number of events from this source}
#'     \item{source_description}{Human-readable description (if available)}
#'     \item{display_label}{Formatted label for UI display}
#'   }
#'
#' @examples
#' \dontrun{
#' data <- load_patient_data(conns, "PAT0000001")
#' sources <- get_source_systems(data)
#' print(sources)
#' }
#'
#' @export
get_source_systems <- function(patient_data) {
  # Collect CDW_Source from all clinical event tables
  all_sources <- c(
    patient_data$encounters$CDW_Source,
    patient_data$diagnoses$CDW_Source,
    patient_data$procedures$CDW_Source,
    patient_data$labs$CDW_Source,
    patient_data$prescribing$CDW_Source,
    patient_data$dispensing$CDW_Source,
    patient_data$vitals$CDW_Source,
    patient_data$conditions$CDW_Source
  )

  # Remove NAs and empty strings
  all_sources <- all_sources[!is.na(all_sources) & all_sources != ""]

  if (length(all_sources) == 0) {
    return(data.frame(
      source_code = character(),
      count = integer(),
      source_description = character(),
      display_label = character(),
      stringsAsFactors = FALSE
    ))
  }

  # Count by source
  source_counts <- table(all_sources)

  result <- data.frame(
    source_code = names(source_counts),
    count = as.integer(source_counts),
    stringsAsFactors = FALSE
  )

  # Add descriptions if available
  if (!is.null(patient_data$source_descriptions) &&
      nrow(patient_data$source_descriptions) > 0) {
    result <- result %>%
      dplyr::left_join(
        patient_data$source_descriptions %>%
          dplyr::select(SRC, SourceDescription),
        by = c("source_code" = "SRC")
      ) %>%
      dplyr::rename(source_description = SourceDescription)
  } else {
    result$source_description <- NA_character_
  }

  # Create display label with both description and raw code
  result <- result %>%
    dplyr::mutate(
      display_label = dplyr::if_else(
        !is.na(source_description),
        paste0(source_description, " (", source_code, ") - ", count, " events"),
        paste0(source_code, " - ", count, " events")
      )
    ) %>%
    dplyr::arrange(dplyr::desc(count))

  result
}

#' Filter events by source system
#'
#' Filter timeline events to include only those from selected source systems.
#' Birth and death markers are always kept regardless of filter.
#'
#' @param events Data frame of timeline events
#' @param selected_sources Character vector of selected CDW_Source codes.
#'   If NULL, empty, or contains "ALL", returns all events.
#'
#' @return Filtered data frame
#'
#' @examples
#' \dontrun{
#' events <- transform_all_to_timevis(data)
#' filtered <- filter_by_source_system(events, c("EPIC", "CERNER"))
#' }
#'
#' @export
filter_by_source_system <- function(events, selected_sources) {
  # If no filter or "ALL" selected, return all events

if (is.null(selected_sources) || length(selected_sources) == 0 ||
      "ALL" %in% selected_sources) {
    return(events)
  }

  events %>%
    dplyr::filter(
      # Keep events matching selected sources
      cdw_source %in% selected_sources |
      # Always keep birth and death markers
      event_type %in% c("death", "birth") |
      # Keep events with no source (if any)
      is.na(cdw_source)
    )
}

#' Filter events by semantic filter results
#' @param events Data frame of timeline events
#' @param semantic_results Data frame from semantic SQL query
#' @param table_name Which table was queried (encounters, diagnoses, etc., or "medications" for UNION)
#' @return Filtered data frame
filter_by_semantic_results <- function(events, semantic_results, table_name) {
  if (is.null(semantic_results) || is.null(table_name) || nrow(semantic_results) == 0) {
    return(events)
  }

  # Special case: "medications" means UNION of prescribing and dispensing
  if (table_name == "medications") {
    # The UNION query returns results with a SOURCE_TABLE column and ID column
    # Extract IDs for each table type
    rx_ids <- c()
    disp_ids <- c()

    if ("SOURCE_TABLE" %in% names(semantic_results)) {
      # Results have SOURCE_TABLE indicator
      rx_rows <- semantic_results[semantic_results$SOURCE_TABLE == "prescribing", ]
      disp_rows <- semantic_results[semantic_results$SOURCE_TABLE == "dispensing", ]

      if (nrow(rx_rows) > 0 && "ID" %in% names(rx_rows)) {
        rx_ids <- rx_rows$ID
      }
      if (nrow(disp_rows) > 0 && "ID" %in% names(disp_rows)) {
        disp_ids <- disp_rows$ID
      }
    } else {
      # Fallback: try to detect by column names
      if ("PRESCRIBINGID" %in% names(semantic_results)) {
        rx_ids <- semantic_results$PRESCRIBINGID
      }
      if ("DISPENSINGID" %in% names(semantic_results)) {
        disp_ids <- semantic_results$DISPENSINGID
      }
    }

    # Filter to show only matching prescribing and dispensing events
    return(events %>%
      filter(
        (event_type == "prescribing" & source_key %in% rx_ids) |
        (event_type == "dispensing" & source_key %in% disp_ids)
      ))
  }

  # Map table names to event types and ID columns
  table_mapping <- list(
    encounters = list(event_type = "encounter", id_col = "ENCOUNTERID", source_key_col = "source_key"),
    diagnoses = list(event_type = "diagnosis", id_col = "DIAGNOSISID", source_key_col = "source_key"),
    procedures = list(event_type = "procedure", id_col = "PROCEDURESID", source_key_col = "source_key"),
    labs = list(event_type = "lab", id_col = "LAB_RESULT_CM_ID", source_key_col = "source_key"),
    prescribing = list(event_type = "prescribing", id_col = "PRESCRIBINGID", source_key_col = "source_key"),
    dispensing = list(event_type = "dispensing", id_col = "DISPENSINGID", source_key_col = "source_key"),
    vitals = list(event_type = "vital", id_col = "VITALID", source_key_col = "source_key"),
    conditions = list(event_type = "condition", id_col = "CONDITIONID", source_key_col = "source_key")
  )

  mapping <- table_mapping[[table_name]]
  if (is.null(mapping)) {
    warning(paste("Unknown table name for semantic filter:", table_name))
    return(events)
  }

  # Get IDs from semantic results
  if (!mapping$id_col %in% names(semantic_results)) {
    warning(paste("ID column", mapping$id_col, "not found in semantic results"))
    return(events)
  }

  matching_ids <- semantic_results[[mapping$id_col]]

  # Filter events: ONLY keep events of the target type that match the semantic results
  # This means when a semantic filter is active, we hide all other event types
  # and only show the filtered results from the queried table
  events %>%
    filter(
      event_type == mapping$event_type &
      source_key %in% matching_ids
    )
}

#' Apply all filters to events
#'
#' Apply multiple filter criteria to timeline events. Filters are applied
#' in order: semantic filter, event type, date range, diagnosis pattern,
#' procedure pattern, lab name, medication name, encounter type.
#'
#' @param events Data frame of timeline events from \code{\link{transform_all_to_timevis}}
#' @param patient_data Full patient data list from \code{\link{load_patient_data}}
#' @param filters Named list of filter values:
#'   \describe{
#'     \item{event_types}{Character vector of event types to include}
#'     \item{start_date}{Start of date range (Date or character)}
#'     \item{end_date}{End of date range (Date or character)}
#'     \item{dx_pattern}{Diagnosis code pattern (SQL LIKE syntax)}
#'     \item{px_pattern}{Procedure code pattern (SQL LIKE syntax)}
#'     \item{lab_name}{Lab name text filter}
#'     \item{med_name}{Medication name text filter}
#'     \item{enc_types}{Encounter types to include}
#'     \item{semantic_results}{Results from semantic filter (optional)}
#'     \item{semantic_table}{Table for semantic filter (optional)}
#'   }
#'
#' @return Filtered data frame of timeline events
#'
#' @examples
#' \dontrun{
#' events <- transform_all_to_timevis(data)
#' filtered <- apply_all_filters(events, data, list(
#'   event_types = c("encounters", "diagnoses"),
#'   dx_pattern = "E11%"
#' ))
#' }
#'
#' @export
apply_all_filters <- function(events, patient_data, filters) {
  result <- events

  # Semantic filter (applied first, if active)
  if (!is.null(filters$semantic_results) && !is.null(filters$semantic_table)) {
    result <- filter_by_semantic_results(result, filters$semantic_results, filters$semantic_table)
  }

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

  # Source system filter
  if (!is.null(filters$source_systems)) {
    result <- filter_by_source_system(result, filters$source_systems)
  }

  result
}

#' Get date range from events
#'
#' Calculate the minimum and maximum dates across all patient data.
#' Includes birth date, death date, and all event dates.
#'
#' @param patient_data List of patient data frames from \code{\link{load_patient_data}}
#'
#' @return List with components:
#'   \describe{
#'     \item{min}{Minimum date (Date object)}
#'     \item{max}{Maximum date (Date object)}
#'   }
#'
#' @examples
#' \dontrun{
#' data <- load_patient_data(conns, "PAT0000001")
#' range <- get_date_range(data)
#' print(paste("Data spans", range$min, "to", range$max))
#' }
#'
#' @export
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
  
  # Collect all dates (including birth and death dates for full patient lifespan)
  all_dates <- c(
    extract_dates(patient_data$demographic, "BIRTH_DATE"),
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
