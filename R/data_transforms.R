# data_transforms.R
# Convert query results to timevis format

library(dplyr)
library(lubridate)
library(htmltools)

#' Define timeline groups
#' @return Data frame with group definitions
get_timeline_groups <- function() {
  data.frame(
    id = c("encounters", "diagnoses", "procedures", "labs", 
           "prescribing", "dispensing", "vitals", "conditions"),
    content = c("Encounters", "Diagnoses", "Procedures", "Labs",
                "Prescriptions", "Dispensing", "Vitals", "Conditions"),
    stringsAsFactors = FALSE
  )
}

#' Create tooltip HTML for an event
#' @param ... Named parameters for tooltip content
#' @return HTML string
create_tooltip <- function(...) {
  items <- list(...)
  html_parts <- lapply(names(items), function(name) {
    value <- items[[name]]
    if (!is.null(value) && length(value) > 0 && !is.na(value) && as.character(value) != "") {
      paste0("<b>", htmlEscape(name), ":</b> ", htmlEscape(as.character(value)))
    } else {
      NULL
    }
  })
  html_parts <- Filter(Negate(is.null), html_parts)
  if (length(html_parts) == 0) return("")
  paste(html_parts, collapse = "<br>")
}

#' Safe coalesce that handles NULL
#' @param ... Values to coalesce
#' @return First non-NA value or NA
safe_coalesce <- function(...) {
  tryCatch({
    coalesce(...)
  }, error = function(e) NA)
}

#' Safely parse dates from various formats
#' @param x Date value (could be Date, POSIXct, character, or numeric)
#' @return Date object or NA
safe_parse_date <- function(x) {
  # Handle NULL or empty
  if (is.null(x) || length(x) == 0) return(as.Date(NA))
  
  # For vectors, process first non-NA value to determine format, then apply to all
  # For single values (rowwise context), just process directly
  if (length(x) == 1) {
    if (is.na(x)) return(as.Date(NA))
    
    # If already a Date, return as-is
    if (inherits(x, "Date")) return(x)
    
    # If POSIXct/POSIXlt, convert to Date
    if (inherits(x, "POSIXt")) return(as.Date(x))
    
    # If character, try to parse
    if (is.character(x)) {
      # Try ISO format first (most common from databases)
      result <- tryCatch({
        as.Date(x)
      }, error = function(e) NULL)
      if (!is.null(result) && !is.na(result)) return(result)
      
      # Try other formats
      for (fmt in c("%Y-%m-%d", "%Y/%m/%d", "%m/%d/%Y", "%d-%b-%Y")) {
        result <- tryCatch({
          as.Date(x, format = fmt)
        }, error = function(e) NULL)
        if (!is.null(result) && !is.na(result)) return(result)
      }
      return(as.Date(NA))
    }
    
    # If numeric and looks reasonable, convert
    if (is.numeric(x)) {
      # Reasonable range for days since 1970: -25567 to 47482 (1900-2100)
      if (!is.na(x) && x > -25567 && x < 47482) {
        return(as.Date(x, origin = "1970-01-01"))
      }
    }
    
    return(as.Date(NA))
  }
  
  # For vectors (length > 1)
  if (all(is.na(x))) return(as.Date(rep(NA, length(x))))
  
  # If already Date, return as-is
  if (inherits(x, "Date")) return(x)
  
  # If POSIXct/POSIXlt, convert to Date
  if (inherits(x, "POSIXt")) return(as.Date(x))
  
  # If character vector
  if (is.character(x)) {
    result <- tryCatch({
      as.Date(x)
    }, error = function(e) {
      as.Date(rep(NA, length(x)))
    })
    return(result)
  }
  
  # If numeric vector
  if (is.numeric(x)) {
    # Check if values are in reasonable date range
    valid <- !is.na(x) & x > -25567 & x < 47482
    result <- as.Date(rep(NA, length(x)))
    result[valid] <- as.Date(x[valid], origin = "1970-01-01")
    return(result)
  }
  
  as.Date(rep(NA, length(x)))
}

#' Transform encounters to timevis format
#' @param encounters Data frame from query_encounters
#' @return Data frame in timevis format
transform_encounters <- function(encounters) {
  if (is.null(encounters) || nrow(encounters) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Parse dates vectorized FIRST, before rowwise
  # Convert to character immediately to avoid rowwise coercion issues
  encounters <- encounters %>%
    mutate(
      parsed_start = safe_parse_date(ADMIT_DATE),
      parsed_end = safe_parse_date(DISCHARGE_DATE),
      start_char = if_else(is.na(parsed_start), NA_character_, format(parsed_start, "%Y-%m-%d")),
      end_char = if_else(is.na(parsed_end), NA_character_, format(parsed_end, "%Y-%m-%d"))
    )
  
  # Now build the output with rowwise for tooltips only
  result <- encounters %>%
    rowwise() %>%
    mutate(
      id = paste0("ENC_", ENCOUNTERID),
      content = as.character(ENC_TYPE),
      start = start_char,
      end = end_char,
      group = "encounters",
      type = ifelse(is.na(parsed_end), "box", "range"),
      className = "event-encounter",
      title = create_tooltip(
        "Encounter Type" = ENC_TYPE,
        "Admit Date" = format(parsed_start, "%Y-%m-%d"),
        "Discharge Date" = if(is.na(parsed_end)) NA_character_ else format(parsed_end, "%Y-%m-%d"),
        "Facility" = FACILITY_LOCATION,
        "DRG" = DRG,
        "Discharge Status" = RAW_DISCHARGE_STATUS,
        "Payer" = PAYER_TYPE_PRIMARY
      ),
      source_table = "ENCOUNTER",
      source_key = as.character(ENCOUNTERID),
      event_type = "encounter"
    ) %>%
    ungroup() %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type)

  result
}

#' Transform diagnoses to timevis format
#' @param diagnoses Data frame from query_diagnoses
#' @return Data frame in timevis format
transform_diagnoses <- function(diagnoses) {
  if (is.null(diagnoses) || nrow(diagnoses) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Parse dates vectorized FIRST
  diagnoses <- diagnoses %>%
    mutate(
      parsed_date = safe_parse_date(coalesce(DX_DATE, ADMIT_DATE)),
      start_char = if_else(is.na(parsed_date), NA_character_, format(parsed_date, "%Y-%m-%d"))
    ) %>%
    filter(!is.na(parsed_date))
  
  if (nrow(diagnoses) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  diagnoses %>%
    rowwise() %>%
    mutate(
      pdx_desc = case_when(
        PDX == "P" ~ "Principal",
        PDX == "S" ~ "Secondary",
        PDX == "X" ~ "Unable to classify",
        TRUE ~ as.character(PDX)
      ),
      # Use description if available, otherwise fall back to code
      dx_display = if (!is.na(RAW_DX) && RAW_DX != "") {
        as.character(RAW_DX)
      } else {
        as.character(DX)
      },
      id = paste0("DX_", DIAGNOSISID),
      content = dx_display,
      start = start_char,
      end = NA_character_,
      group = "diagnoses",
      type = "box",
      className = "event-diagnosis",
      title = create_tooltip(
        "Diagnosis Code" = DX,
        "Description" = RAW_DX,
        "Type" = DX_TYPE,
        "PDX" = pdx_desc,
        "Date" = format(parsed_date, "%Y-%m-%d"),
        "Encounter" = ENCOUNTERID
      ),
      source_table = "DIAGNOSIS",
      source_key = as.character(DIAGNOSISID),
      event_type = "diagnosis"
    ) %>%
    ungroup() %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type)
}

#' Transform procedures to timevis format
#' @param procedures Data frame from query_procedures
#' @return Data frame in timevis format
transform_procedures <- function(procedures) {
  if (is.null(procedures) || nrow(procedures) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Parse dates vectorized FIRST
  procedures <- procedures %>%
    mutate(
      parsed_date = safe_parse_date(coalesce(PX_DATE, ADMIT_DATE)),
      start_char = if_else(is.na(parsed_date), NA_character_, format(parsed_date, "%Y-%m-%d"))
    ) %>%
    filter(!is.na(parsed_date))
  
  if (nrow(procedures) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  procedures %>%
    rowwise() %>%
    mutate(
      # Use description if available, otherwise fall back to code
      px_display = if (!is.na(RAW_PX_NAME) && RAW_PX_NAME != "") {
        as.character(RAW_PX_NAME)
      } else {
        as.character(PX)
      },
      id = paste0("PX_", PROCEDURESID),
      content = px_display,
      start = start_char,
      end = NA_character_,
      group = "procedures",
      type = "box",
      className = "event-procedure",
      title = create_tooltip(
        "Procedure Code" = PX,
        "Description" = RAW_PX_NAME,
        "Type" = PX_TYPE,
        "Date" = format(parsed_date, "%Y-%m-%d"),
        "Encounter" = ENCOUNTERID
      ),
      source_table = "PROCEDURES",
      source_key = as.character(PROCEDURESID),
      event_type = "procedure"
    ) %>%
    ungroup() %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type)
}

#' Format lab result with modifiers and abnormal flags
#' @param result_num Numeric result
#' @param result_qual Qualitative result
#' @param result_modifier Result modifier (<, >, etc.)
#' @param result_unit Result unit
#' @param abn_ind Abnormal indicator
#' @return Formatted string
format_lab_result <- function(result_num, result_qual, result_modifier, 
                               result_unit, abn_ind) {
  result <- ""
  
  # Handle modifier
  modifier_prefix <- case_when(
    is.na(result_modifier) ~ "",
    result_modifier == "LT" ~ "<",
    result_modifier == "LE" ~ "<=",
    result_modifier == "GT" ~ ">",
    result_modifier == "GE" ~ ">=",
    result_modifier == "EQ" ~ "",
    TRUE ~ ""
  )
  
  # Build result string
  if (!is.na(result_num)) {
    result <- paste0(modifier_prefix, result_num)
    if (!is.na(result_unit) && result_unit != "") {
      result <- paste(result, result_unit)
    }
  } else if (!is.na(result_qual) && result_qual != "") {
    result <- as.character(result_qual)
  }
  
  # Add abnormal flag
  abn_flag <- case_when(
    is.na(abn_ind) ~ "",
    abn_ind == "AB" ~ " [Abnormal]",
    abn_ind == "AH" ~ " [High]",
    abn_ind == "AL" ~ " [Low]",
    abn_ind == "CH" ~ " [Crit High]",
    abn_ind == "CL" ~ " [Crit Low]",
    abn_ind == "CR" ~ " [Critical]",
    TRUE ~ ""
  )
  
  paste0(result, abn_flag)
}

#' Transform labs to timevis format
#' @param labs Data frame from query_labs
#' @return Data frame in timevis format
transform_labs <- function(labs) {
  if (is.null(labs) || nrow(labs) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Parse dates vectorized FIRST
  labs <- labs %>%
    mutate(
      parsed_date = safe_parse_date(RESULT_DATE),
      start_char = if_else(is.na(parsed_date), NA_character_, format(parsed_date, "%Y-%m-%d"))
    ) %>%
    filter(!is.na(parsed_date))
  
  if (nrow(labs) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  labs %>%
    rowwise() %>%
    mutate(
      formatted_result = format_lab_result(
        RESULT_NUM, RESULT_QUAL, RESULT_MODIFIER, RESULT_UNIT, ABN_IND
      ),
      lab_display = safe_coalesce(as.character(RAW_LAB_NAME), as.character(LAB_LOINC), "Lab"),
      norm_range = if (!is.na(NORM_RANGE_LOW) && !is.na(NORM_RANGE_HIGH)) {
        paste0(NORM_RANGE_LOW, " - ", NORM_RANGE_HIGH)
      } else {
        NA_character_
      },
      id = paste0("LAB_", LAB_RESULT_CM_ID),
      content = substr(lab_display, 1, 30),
      start = start_char,
      end = NA_character_,
      group = "labs",
      type = "box",
      className = ifelse(!is.na(ABN_IND) & ABN_IND != "NI", 
                         "event-lab event-lab-abnormal", "event-lab"),
      title = create_tooltip(
        "Lab Name" = RAW_LAB_NAME,
        "LOINC" = LAB_LOINC,
        "Result" = formatted_result,
        "Date" = format(parsed_date, "%Y-%m-%d"),
        "Normal Range" = norm_range,
        "Specimen" = SPECIMEN_SOURCE
      ),
      source_table = "LAB_RESULT_CM",
      source_key = as.character(LAB_RESULT_CM_ID),
      event_type = "lab"
    ) %>%
    ungroup() %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type)
}

#' Transform prescribing to timevis format
#' @param prescribing Data frame from query_prescribing
#' @return Data frame in timevis format
transform_prescribing <- function(prescribing) {
  if (is.null(prescribing) || nrow(prescribing) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Parse dates vectorized FIRST
  prescribing <- prescribing %>%
    mutate(
      parsed_start = safe_parse_date(coalesce(RX_START_DATE, RX_ORDER_DATE)),
      parsed_end_raw = safe_parse_date(RX_END_DATE),
      # Calculate end date based on logic from design doc
      parsed_end = case_when(
        !is.na(parsed_end_raw) ~ parsed_end_raw,
        !is.na(RX_DAYS_SUPPLY) & !is.na(parsed_start) ~
          parsed_start + as.numeric(RX_DAYS_SUPPLY),
        TRUE ~ as.Date(NA)
      ),
      start_char = if_else(is.na(parsed_start), NA_character_, format(parsed_start, "%Y-%m-%d")),
      end_char = if_else(is.na(parsed_end), NA_character_, format(parsed_end, "%Y-%m-%d"))
    ) %>%
    filter(!is.na(parsed_start))
  
  if (nrow(prescribing) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  prescribing %>%
    rowwise() %>%
    mutate(
      med_display = safe_coalesce(
        as.character(RAW_RX_MED_NAME), 
        as.character(RXNORM_CUI), 
        "Rx"
      ),
      dose_display = if (!is.na(RX_DOSE_ORDERED)) {
        paste(RX_DOSE_ORDERED, RX_DOSE_ORDERED_UNIT)
      } else {
        NA_character_
      },
      id = paste0("RX_", PRESCRIBINGID),
      content = substr(med_display, 1, 30),
      start = start_char,
      end = end_char,
      group = "prescribing",
      type = ifelse(is.na(parsed_end), "box", "range"),
      className = "event-prescribing",
      title = create_tooltip(
        "Medication" = RAW_RX_MED_NAME,
        "RxNorm" = RXNORM_CUI,
        "Dose" = dose_display,
        "Frequency" = RAW_RX_FREQUENCY,
        "Route" = RAW_RX_ROUTE,
        "Start Date" = format(parsed_start, "%Y-%m-%d"),
        "End Date" = if(is.na(parsed_end)) NA_character_ else format(parsed_end, "%Y-%m-%d"),
        "Days Supply" = as.character(RX_DAYS_SUPPLY),
        "Refills" = as.character(RX_REFILLS)
      ),
      source_table = "PRESCRIBING",
      source_key = as.character(PRESCRIBINGID),
      event_type = "prescribing"
    ) %>%
    ungroup() %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type)
}

#' Transform dispensing to timevis format
#' @param dispensing Data frame from query_dispensing
#' @return Data frame in timevis format
transform_dispensing <- function(dispensing) {
  if (is.null(dispensing) || nrow(dispensing) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Parse dates vectorized FIRST
  dispensing <- dispensing %>%
    mutate(
      parsed_date = safe_parse_date(DISPENSE_DATE),
      start_char = if_else(is.na(parsed_date), NA_character_, format(parsed_date, "%Y-%m-%d"))
    ) %>%
    filter(!is.na(parsed_date))
  
  if (nrow(dispensing) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  dispensing %>%
    rowwise() %>%
    mutate(
      med_display = safe_coalesce(as.character(RAW_DISP_MED_NAME), as.character(NDC), "Dispensed"),
      id = paste0("DISP_", DISPENSINGID),
      content = substr(med_display, 1, 30),
      start = start_char,
      end = NA_character_,
      group = "dispensing",
      type = "box",
      className = "event-dispensing",
      title = create_tooltip(
        "Medication" = RAW_DISP_MED_NAME,
        "NDC" = NDC,
        "Quantity" = as.character(DISPENSE_AMT),
        "Days Supply" = as.character(DISPENSE_SUP),
        "Date" = format(parsed_date, "%Y-%m-%d")
      ),
      source_table = "DISPENSING",
      source_key = as.character(DISPENSINGID),
      event_type = "dispensing"
    ) %>%
    ungroup() %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type)
}

#' Format vital signs for display
#' @param systolic Systolic BP
#' @param diastolic Diastolic BP
#' @param ht Height
#' @param wt Weight
#' @param bmi BMI
#' @return Formatted string
format_vital_content <- function(systolic, diastolic, ht, wt, bmi) {
  parts <- c()
  
  if (!is.na(systolic) && !is.na(diastolic)) {
    parts <- c(parts, paste0("BP:", systolic, "/", diastolic))
  }
  if (!is.na(ht)) {
    parts <- c(parts, paste0("Ht:", ht))
  }
  if (!is.na(wt)) {
    parts <- c(parts, paste0("Wt:", wt))
  }
  if (!is.na(bmi)) {
    parts <- c(parts, paste0("BMI:", round(as.numeric(bmi), 1)))
  }
  
  if (length(parts) == 0) return("Vitals")
  paste(parts, collapse = " ")
}

#' Transform vitals to timevis format
#' @param vitals Data frame from query_vitals
#' @return Data frame in timevis format
transform_vitals <- function(vitals) {
  if (is.null(vitals) || nrow(vitals) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Parse dates vectorized FIRST
  vitals <- vitals %>%
    mutate(
      parsed_date = safe_parse_date(MEASURE_DATE),
      start_char = if_else(is.na(parsed_date), NA_character_, format(parsed_date, "%Y-%m-%d"))
    ) %>%
    filter(!is.na(parsed_date))
  
  if (nrow(vitals) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  vitals %>%
    rowwise() %>%
    mutate(
      vital_content = format_vital_content(SYSTOLIC, DIASTOLIC, HT, WT, ORIGINAL_BMI),
      bp_display = if (!is.na(SYSTOLIC) && !is.na(DIASTOLIC)) {
        bp_str <- paste0(SYSTOLIC, "/", DIASTOLIC)
        if (!is.na(BP_POSITION)) paste0(bp_str, " (", BP_POSITION, ")") else bp_str
      } else {
        NA_character_
      },
      id = paste0("VIT_", VITALID),
      content = substr(vital_content, 1, 40),
      start = start_char,
      end = NA_character_,
      group = "vitals",
      type = "box",
      className = "event-vital",
      title = create_tooltip(
        "Date" = format(parsed_date, "%Y-%m-%d"),
        "Blood Pressure" = bp_display,
        "Height" = as.character(HT),
        "Weight" = as.character(WT),
        "BMI" = as.character(ORIGINAL_BMI),
        "Smoking" = SMOKING,
        "Tobacco" = TOBACCO
      ),
      source_table = "VITAL",
      source_key = as.character(VITALID),
      event_type = "vital"
    ) %>%
    ungroup() %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type)
}

#' Transform conditions to timevis format
#' @param conditions Data frame from query_conditions
#' @return Data frame in timevis format
transform_conditions <- function(conditions) {
  if (is.null(conditions) || nrow(conditions) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Parse dates vectorized FIRST
  conditions <- conditions %>%
    mutate(
      parsed_date = safe_parse_date(coalesce(ONSET_DATE, REPORT_DATE)),
      start_char = if_else(is.na(parsed_date), NA_character_, format(parsed_date, "%Y-%m-%d"))
    ) %>%
    filter(!is.na(parsed_date))
  
  if (nrow(conditions) == 0) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  conditions %>%
    rowwise() %>%
    mutate(
      status_desc = case_when(
        is.na(CONDITION_STATUS) ~ NA_character_,
        CONDITION_STATUS == "AC" ~ "Active",
        CONDITION_STATUS == "RS" ~ "Resolved",
        CONDITION_STATUS == "IN" ~ "Inactive",
        TRUE ~ as.character(CONDITION_STATUS)
      ),
      # Use description if available, otherwise fall back to code
      cond_display = if (!is.na(RAW_CONDITION) && RAW_CONDITION != "") {
        as.character(RAW_CONDITION)
      } else {
        as.character(CONDITION)
      },
      id = paste0("COND_", CONDITIONID),
      content = cond_display,
      start = start_char,
      end = NA_character_,
      group = "conditions",
      type = "box",
      className = "event-condition",
      title = create_tooltip(
        "Condition Code" = CONDITION,
        "Description" = RAW_CONDITION,
        "Status" = status_desc,
        "Onset Date" = format(parsed_date, "%Y-%m-%d"),
        "Report Date" = if(!is.na(REPORT_DATE)) format(safe_parse_date(REPORT_DATE), "%Y-%m-%d") else NA_character_,
        "Resolve Date" = if(!is.na(RESOLVE_DATE)) format(safe_parse_date(RESOLVE_DATE), "%Y-%m-%d") else NA_character_
      ),
      source_table = "CONDITION",
      source_key = as.character(CONDITIONID),
      event_type = "condition"
    ) %>%
    ungroup() %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type)
}

#' Create death marker for timeline
#' @param death Data frame from query_death
#' @return Data frame in timevis format (background type spanning all groups)
transform_death <- function(death) {
  if (is.null(death) || nrow(death) == 0 || is.na(death$DEATH_DATE[1])) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  death_date <- safe_parse_date(death$DEATH_DATE[1])
  death_date_str <- format(death_date, "%Y-%m-%d")
  
  data.frame(
    id = "DEATH_MARKER",
    content = paste("Death:", death_date_str),
    start = death_date_str,
    end = NA_character_,
    group = NA_character_,
    type = "point",
    className = "event-death",
    title = create_tooltip(
      "Death Date" = death_date_str,
      "Source" = death$DEATH_SOURCE[1],
      "Confidence" = death$DEATH_MATCH_CONFIDENCE[1]
    ),
    source_table = "DEATH",
    source_key = as.character(death$PATID[1]),
    event_type = "death",
    stringsAsFactors = FALSE
  )
}

#' Create birth date marker for timeline
#' @param demographic Data frame from query_demographic
#' @return Data frame in timevis format (background type spanning all groups)
transform_birth_date <- function(demographic) {
  if (is.null(demographic) || nrow(demographic) == 0 || is.na(demographic$BIRTH_DATE[1])) {
    return(data.frame(
      id = character(), content = character(), start = character(),
      end = character(), group = character(), type = character(),
      className = character(), title = character(), source_table = character(),
      source_key = character(), event_type = character(),
      stringsAsFactors = FALSE
    ))
  }

  birth_date <- safe_parse_date(demographic$BIRTH_DATE[1])
  birth_date_str <- format(birth_date, "%Y-%m-%d")

  data.frame(
    id = "BIRTH_MARKER",
    content = "",  # No content for background markers
    start = birth_date_str,
    end = birth_date_str,
    group = NA_character_,  # NA means spans all groups
    type = "background",  # Background type creates a vertical line
    className = "event-birth",
    title = create_tooltip(
      "Birth Date" = birth_date_str
    ),
    source_table = "DEMOGRAPHIC",
    source_key = as.character(demographic$PATID[1]),
    event_type = "birth",
    stringsAsFactors = FALSE
  )
}

#' Transform all patient data to timevis format
#' @param patient_data List of patient data frames
#' @return Data frame with all events in timevis format
transform_all_to_timevis <- function(patient_data) {
  
  # Transform each type with error handling
  transform_safe <- function(transform_fn, data, name) {
    tryCatch({
      result <- transform_fn(data)
      # Debug: print date info
      if (nrow(result) > 0) {
        message(paste(name, "- rows:", nrow(result), 
                      "- start class:", class(result$start)[1],
                      "- first start:", result$start[1]))
      }
      result
    }, error = function(e) {
      warning(paste("Error transforming", name, ":", e$message))
      data.frame(
        id = character(), content = character(), start = character(),
        end = character(), group = character(), type = character(),
        className = character(), title = character(), source_table = character(),
        source_key = character(), event_type = character(),
        stringsAsFactors = FALSE
      )
    })
  }
  
  events <- bind_rows(
    transform_safe(transform_encounters, patient_data$encounters, "encounters"),
    transform_safe(transform_diagnoses, patient_data$diagnoses, "diagnoses"),
    transform_safe(transform_procedures, patient_data$procedures, "procedures"),
    transform_safe(transform_labs, patient_data$labs, "labs"),
    transform_safe(transform_prescribing, patient_data$prescribing, "prescribing"),
    transform_safe(transform_dispensing, patient_data$dispensing, "dispensing"),
    transform_safe(transform_vitals, patient_data$vitals, "vitals"),
    transform_safe(transform_conditions, patient_data$conditions, "conditions"),
    transform_safe(transform_death, patient_data$death, "death")
  )
  
  # Ensure proper types - dates should already be character from transforms
  if (nrow(events) > 0) {
    # Force conversion: if start column contains pure numbers as strings, convert them
    if (is.character(events$start)) {
      # Check if values are numeric strings (like "18500")
      needs_conversion <- !is.na(events$start) & grepl("^[0-9]+$", events$start)
      if (any(needs_conversion)) {
        events$start[needs_conversion] <- format(
          as.Date(as.numeric(events$start[needs_conversion]), origin = "1970-01-01"),
          "%Y-%m-%d"
        )
      }
    }

    # Only convert if dates are still numeric (bind_rows can do this)
    if (is.numeric(events$start)) {
      events$start <- format(as.Date(events$start, origin = "1970-01-01"), "%Y-%m-%d")
    }
    if (is.numeric(events$end)) {
      events$end <- format(as.Date(events$end, origin = "1970-01-01"), "%Y-%m-%d")
    }

    # If still Date class, convert to character
    if (inherits(events$start, "Date")) {
      events$start <- format(events$start, "%Y-%m-%d")
    }
    if (inherits(events$end, "Date")) {
      events$end <- format(events$end, "%Y-%m-%d")
    }

    # Ensure character types
    events$id <- as.character(events$id)
    events$content <- as.character(events$content)
    events$source_key <- as.character(events$source_key)
  }
  
  events
}

#' Calculate age from birth date
#' @param birth_date Date of birth
#' @param ref_date Reference date (default today)
#' @return Integer age in years
calculate_age <- function(birth_date, ref_date = Sys.Date()) {
  if (is.na(birth_date)) return(NA)
  floor(as.numeric(difftime(ref_date, birth_date, units = "days")) / 365.25)
}

#' Format demographic display
#' @param demographic Data frame with demographic info
#' @param source_systems Data frame with source system mappings
#' @param total_events Total event count
#' @param death Data frame with death info (optional)
#' @return HTML string for demographic display
format_demographic_html <- function(demographic, source_systems, total_events, death = NULL) {
  if (is.null(demographic) || nrow(demographic) == 0) {
    return("<p>No demographic data available</p>")
  }

  d <- demographic[1, ]

  # Calculate age (use death date if available, otherwise current date)
  death_date <- NULL
  if (!is.null(death) && nrow(death) > 0 && !is.na(death$DEATH_DATE[1])) {
    death_date <- safe_parse_date(death$DEATH_DATE[1])
  }

  ref_date <- if (!is.null(death_date)) death_date else Sys.Date()
  age <- calculate_age(d$BIRTH_DATE, ref_date)

  # Format age string differently if deceased
  if (!is.null(death_date)) {
    age_str <- if (!is.na(age)) paste0(" (Age at death: ", age, ")") else ""
  } else {
    age_str <- if (!is.na(age)) paste0(" (Age ", age, ")") else ""
  }
  
  # Sex mapping
  sex <- case_when(
    is.na(d$SEX) ~ "Unknown",
    d$SEX == "M" ~ "Male",
    d$SEX == "F" ~ "Female",
    d$SEX == "A" ~ "Ambiguous",
    d$SEX == "NI" ~ "No Information",
    d$SEX == "UN" ~ "Unknown",
    d$SEX == "OT" ~ "Other",
    TRUE ~ as.character(d$SEX)
  )
  
  # Race mapping (simplified)
  race <- case_when(
    is.na(d$RACE) ~ "Unknown",
    d$RACE == "01" ~ "American Indian or Alaska Native",
    d$RACE == "02" ~ "Asian",
    d$RACE == "03" ~ "Black or African American",
    d$RACE == "04" ~ "Native Hawaiian or Other Pacific Islander",
    d$RACE == "05" ~ "White",
    d$RACE == "06" ~ "Multiple Race",
    d$RACE == "07" ~ "Refuse to Answer",
    d$RACE == "NI" ~ "No Information",
    d$RACE == "UN" ~ "Unknown",
    d$RACE == "OT" ~ "Other",
    TRUE ~ if (!is.na(d$RAW_RACE)) as.character(d$RAW_RACE) else as.character(d$RACE)
  )
  
  # Ethnicity
  ethnicity <- case_when(
    is.na(d$HISPANIC) ~ "Unknown",
    d$HISPANIC == "Y" ~ "Hispanic/Latino",
    d$HISPANIC == "N" ~ "Not Hispanic/Latino",
    d$HISPANIC == "R" ~ "Refuse to Answer",
    d$HISPANIC == "NI" ~ "No Information",
    d$HISPANIC == "UN" ~ "Unknown",
    TRUE ~ as.character(d$HISPANIC)
  )
  
  # Build source systems list
  sources_html <- ""
  if (!is.null(source_systems) && nrow(source_systems) > 0) {
    source_items <- sapply(1:nrow(source_systems), function(i) {
      src <- source_systems[i, ]
      desc <- if (!is.na(src$SourceDescription)) src$SourceDescription else src$Src
      paste0("<li><strong>", htmlEscape(as.character(desc)), "</strong> LID: ", 
             htmlEscape(as.character(src$Lid)), "</li>")
    })
    sources_html <- paste0(
      "<div class='demo-section'><strong>Source Systems:</strong><ul>",
      paste(source_items, collapse = ""),
      "</ul></div>"
    )
  }
  
  # Format death date row if available
  death_row <- ""
  if (!is.null(death_date)) {
    death_source <- if (!is.null(death) && !is.na(death$DEATH_SOURCE[1])) {
      paste0(" (Source: ", death$DEATH_SOURCE[1], ")")
    } else {
      ""
    }
    death_row <- paste0(
      "<div class='demo-row death-indicator' style='background-color: #f8d7da; border-left: 4px solid #d32f2f; padding: 10px 12px; margin: 10px -5px; border-radius: 4px;'>",
      "<span class='demo-label' style='color: #721c24; font-weight: 700;'>Death Date:</span> ",
      "<span class='demo-value' style='color: #721c24; font-weight: 600;'>",
      format(death_date, "%Y-%m-%d"), death_source, "</span>",
      "</div>"
    )
  }

  paste0(
    "<div class='demographics-panel'>",
    "<div class='demo-row'>",
    "<span class='demo-label'>PATID:</span> <span class='demo-value'>",
    htmlEscape(as.character(d$PATID)), "</span>",
    "</div>",
    "<div class='demo-row'>",
    "<span class='demo-label'>DOB:</span> <span class='demo-value'>",
    as.character(d$BIRTH_DATE), age_str, "</span>",
    "<span class='demo-label'>Sex:</span> <span class='demo-value'>", sex, "</span>",
    "<span class='demo-label'>Race:</span> <span class='demo-value'>", race, "</span>",
    "</div>",
    death_row,
    "<div class='demo-row'>",
    "<span class='demo-label'>Ethnicity:</span> <span class='demo-value'>",
    ethnicity, "</span>",
    "</div>",
    sources_html,
    "<div class='demo-row'>",
    "<span class='demo-label'>Total Events:</span> <span class='demo-value'>",
    format(total_events, big.mark = ","), "</span>",
    "</div>",
    "</div>"
  )
}
