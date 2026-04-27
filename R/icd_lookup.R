# icd_lookup.R
# ICD code description lookup functions using bundled official lookup data

# Package-level cache for ICD lookup tables
.icd_cache <- new.env(parent = emptyenv())

bundled_icd_path <- function(filename) {
  path <- system.file("extdata", filename, package = "PatientTimelineViewer")
  if (path == "" || !file.exists(path)) {
    dev_path <- file.path("inst", "extdata", filename)
    if (file.exists(dev_path)) {
      path <- dev_path
    }
  }

  if (path == "" || !file.exists(path)) {
    return(NULL)
  }

  path
}

#' Check if ICD description lookup data is available
#' @return Logical TRUE if bundled data is available
icd_data_available <- function() {
  !is.null(bundled_icd_path("icd10cm_diagnosis_lookup.csv")) ||
    !is.null(bundled_icd_path("icd9cm_diagnosis_lookup.csv"))
}

load_bundled_icd_lookup <- function(filename) {
  path <- bundled_icd_path(filename)
  if (is.null(path)) {
    return(NULL)
  }

  lookup <- utils::read.csv(path, stringsAsFactors = FALSE)
  lookup[, c("code", "short_desc")]
}

#' Get ICD-10-CM lookup table (cached)
#' @return Data frame with code and short_desc columns, or NULL if unavailable
get_icd10cm_lookup <- function() {
  if (is.null(.icd_cache$icd10cm)) {
    .icd_cache$icd10cm <- load_bundled_icd_lookup("icd10cm_diagnosis_lookup.csv")
    if (!is.null(.icd_cache$icd10cm)) {
      names(.icd_cache$icd10cm) <- c("code", "description")
    }
  }

  .icd_cache$icd10cm
}

#' Get ICD-9-CM lookup table (cached)
#' @return Data frame with code and description columns, or NULL if unavailable
get_icd9cm_lookup <- function() {
  if (is.null(.icd_cache$icd9cm)) {
    .icd_cache$icd9cm <- load_bundled_icd_lookup("icd9cm_diagnosis_lookup.csv")
    if (!is.null(.icd_cache$icd9cm)) {
      names(.icd_cache$icd9cm) <- c("code", "description")
    }
  }

  .icd_cache$icd9cm
}

#' Normalize ICD code for lookup
#'
#' Removes dots and converts to uppercase for consistent matching
#' @param code ICD code (character)
#' @return Normalized code
normalize_icd_code <- function(code) {
  if (is.null(code) || is.na(code) || code == "") {
    return(NA_character_)
  }
  # Remove dots, spaces, and convert to uppercase
  gsub("[.\\s]", "", toupper(as.character(code)))
}

#' Look up ICD code description
#'
#' Looks up the description for an ICD-9 or ICD-10 code using bundled lookup data.
#' Falls back to the code itself if no description is found.
#'
#' @param code ICD code (character)
#' @param code_type ICD code type: "09" for ICD-9, "10" for ICD-10 (from PCORnet DX_TYPE)
#' @return Description string or NA if not found
#' @export
lookup_icd_description <- function(code, code_type = "10") {
  if (is.null(code) || is.na(code) || code == "") {
    return(NA_character_)
  }

  # Normalize the code for lookup
  normalized_code <- normalize_icd_code(code)

  # Get the appropriate lookup table
  lookup <- if (code_type == "09") {
    get_icd9cm_lookup()
  } else {
    get_icd10cm_lookup()
  }

  if (is.null(lookup)) {
    return(NA_character_)
  }

  # Find matching code
  idx <- match(normalized_code, lookup$code)

  if (!is.na(idx)) {
    return(lookup$description[idx])
  }

  NA_character_
}

#' Look up descriptions for multiple ICD codes (vectorized)
#'
#' Efficiently looks up descriptions for multiple codes at once.
#'
#' @param codes Character vector of ICD codes
#' @param code_types Character vector of code types (same length as codes)
#' @return Character vector of descriptions
#' @export
lookup_icd_descriptions <- function(codes, code_types) {
  if (!icd_data_available()) {
    return(rep(NA_character_, length(codes)))
  }

  # Ensure same length
  if (length(code_types) == 1) {
    code_types <- rep(code_types, length(codes))
  }

  # Get lookup tables once
  icd9_lookup <- get_icd9cm_lookup()
  icd10_lookup <- get_icd10cm_lookup()

  # Process each code
  descriptions <- mapply(function(code, code_type) {
    if (is.na(code) || code == "") {
      return(NA_character_)
    }

    normalized <- normalize_icd_code(code)

    lookup <- if (code_type == "09") icd9_lookup else icd10_lookup

    if (is.null(lookup)) {
      return(NA_character_)
    }

    idx <- match(normalized, lookup$code)
    if (!is.na(idx)) lookup$description[idx] else NA_character_
  }, codes, code_types, SIMPLIFY = TRUE, USE.NAMES = FALSE)

  as.character(descriptions)
}

#' Format ICD code with description
#'
#' Returns a formatted string with both code and description if available.
#'
#' @param code ICD code
#' @param code_type ICD code type
#' @param include_code Whether to include the code in output (default TRUE)
#' @return Formatted string
#' @export
format_icd_with_description <- function(code, code_type = "10", include_code = TRUE) {
  if (is.null(code) || is.na(code) || code == "") {
    return(NA_character_)
  }

  description <- lookup_icd_description(code, code_type)

  if (!is.na(description) && description != "") {
    if (include_code) {
      paste0(code, " - ", description)
    } else {
      description
    }
  } else {
    as.character(code)
  }
}
