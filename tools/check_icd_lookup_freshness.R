#!/usr/bin/env Rscript

# Check bundled ICD lookup integrity and whether CDC has published a newer
# ICD-10-CM release directory than the metadata records.

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg) > 0) {
  sub("^--file=", "", script_arg[[1]])
} else {
  file.path(getwd(), "tools", "check_icd_lookup_freshness.R")
}
root_dir <- normalizePath(file.path(dirname(normalizePath(script_path, mustWork = FALSE)), ".."), mustWork = TRUE)
extdata_dir <- file.path(root_dir, "inst", "extdata")
metadata_path <- file.path(extdata_dir, "icd_lookup_metadata.yml")

read_metadata_value <- function(lines, key) {
  pattern <- paste0("^[[:space:]]*", key, ":[[:space:]]*")
  hit <- grep(pattern, lines, value = TRUE)
  if (length(hit) == 0) return(NA_character_)
  value <- sub(pattern, "", hit[[1]])
  gsub('^"|"$', "", value)
}

fail <- function(...) {
  stop(paste0(...), call. = FALSE)
}

if (!file.exists(metadata_path)) {
  fail("Missing ICD metadata: ", metadata_path)
}

metadata <- readLines(metadata_path, warn = FALSE)

check_file_checksum <- function(filename, metadata_key) {
  path <- file.path(extdata_dir, filename)
  if (!file.exists(path)) {
    fail("Missing bundled ICD lookup: ", path)
  }

  expected <- read_metadata_value(metadata, metadata_key)
  actual <- as.character(tools::sha256sum(path)[[1]])
  if (!is.na(expected) && expected != actual) {
    fail("Checksum mismatch for ", filename, ": expected ", expected, ", got ", actual)
  }
}

check_file_checksum("icd10cm_diagnosis_lookup.csv", "lookup_sha256")

# The metadata contains two lookup_sha256 entries; validate ICD-9 explicitly by
# reading the second one to avoid depending on a YAML parser.
lookup_hashes <- sub("^[[:space:]]*lookup_sha256:[[:space:]]*\"?([^\"]+)\"?.*$", "\\1",
                     grep("^[[:space:]]*lookup_sha256:", metadata, value = TRUE))
if (length(lookup_hashes) >= 2) {
  icd9_path <- file.path(extdata_dir, "icd9cm_diagnosis_lookup.csv")
  if (!file.exists(icd9_path)) {
    fail("Missing bundled ICD lookup: ", icd9_path)
  }
  actual_icd9 <- as.character(tools::sha256sum(icd9_path)[[1]])
  if (lookup_hashes[[2]] != actual_icd9) {
    fail("Checksum mismatch for icd9cm_diagnosis_lookup.csv: expected ",
         lookup_hashes[[2]], ", got ", actual_icd9)
  }
}

cdc_index_url <- "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/ICD10CM/"
allow_offline <- identical(Sys.getenv("PTV_ICD_ALLOW_OFFLINE"), "1")
index <- tryCatch(readLines(cdc_index_url, warn = FALSE), error = function(e) e)

if (inherits(index, "error")) {
  msg <- paste("Could not read CDC ICD-10-CM index:", index$message)
  if (allow_offline) {
    warning(msg)
    quit(status = 0)
  }
  fail(msg)
}

dirs <- unique(unlist(regmatches(index, gregexpr("\\b[0-9]{4}(-update|-Update)?\\b", index))))

year <- as.integer(read_metadata_value(metadata, "fiscal_year"))
release <- read_metadata_value(metadata, "release")

latest_year <- max(as.integer(sub("^([0-9]{4}).*$", "\\1", dirs)), na.rm = TRUE)
if (!is.na(year) && latest_year > year) {
  fail("Bundled ICD-10-CM fiscal year ", year, " is older than CDC directory year ", latest_year)
}

current_update_dir <- paste0(year, "-update")
has_update_dir <- any(tolower(dirs) == tolower(current_update_dir))
if (has_update_dir && !grepl("April", release, ignore.case = TRUE)) {
  fail("CDC has an update directory for ", year,
       ", but bundled ICD-10-CM release is recorded as '", release, "'")
}

message("ICD lookup files are present, checksums match metadata, and CDC freshness check passed.")
