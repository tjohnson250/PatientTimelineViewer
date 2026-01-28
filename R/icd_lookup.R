# icd_lookup.R
# ICD code description lookup functions using icd.data package

# Package-level cache for ICD lookup tables
.icd_cache <- new.env(parent = emptyenv())

#' Check if icd.data package is available
#' @return Logical TRUE if available
icd_data_available <- function() {

  requireNamespace("icd.data", quietly = TRUE)
}

#' Get ICD-10-CM lookup table (cached)
#' @return Data frame with code and short_desc columns, or NULL if unavailable
get_icd10cm_lookup <- function() {
  if (!icd_data_available()) {
    return(NULL)
  }

  if (is.null(.icd_cache$icd10cm)) {
    tryCatch({
      # Load icd10cm2016 data from icd.data package
      data("icd10cm2016", package = "icd.data", envir = .icd_cache)
      # Create simplified lookup with just code and description
      .icd_cache$icd10cm <- .icd_cache$icd10cm2016[, c("code", "short_desc")]
      names(.icd_cache$icd10cm) <- c("code", "description")
    }, error = function(e) {
      warning("Could not load ICD-10-CM data: ", e$message)
      .icd_cache$icd10cm <- NULL
    })
  }

  .icd_cache$icd10cm
}

#' Get ICD-9-CM lookup table (cached)
#' @return Data frame with code and description columns, or NULL if unavailable
get_icd9cm_lookup <- function() {
  if (!icd_data_available()) {
    return(NULL)
  }

  if (is.null(.icd_cache$icd9cm)) {
    tryCatch({
      # Load icd9cm_billable data from icd.data package
      # Use the most recent version (32)
      data("icd9cm_billable", package = "icd.data", envir = .icd_cache)
      # Get the most recent year's data
      icd9_data <- .icd_cache$icd9cm_billable[["32"]]
      .icd_cache$icd9cm <- icd9_data[, c("code", "short_desc")]
      names(.icd_cache$icd9cm) <- c("code", "description")
    }, error = function(e) {
      warning("Could not load ICD-9-CM data: ", e$message)
      .icd_cache$icd9cm <- NULL
    })
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
#' Looks up the description for an ICD-9 or ICD-10 code using the icd.data package.
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
