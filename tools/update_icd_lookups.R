#!/usr/bin/env Rscript

# Download official ICD diagnosis code description files and normalize them for
# bundled package lookup. This script has no package dependencies beyond base R.

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg) > 0) {
  sub("^--file=", "", script_arg[[1]])
} else {
  file.path(getwd(), "tools", "update_icd_lookups.R")
}
root_dir <- normalizePath(file.path(dirname(normalizePath(script_path, mustWork = FALSE)), ".."), mustWork = TRUE)
extdata_dir <- file.path(root_dir, "inst", "extdata")
dir.create(extdata_dir, recursive = TRUE, showWarnings = FALSE)

icd10_url <- "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/ICD10CM/2026-update/icd10cm-April-1-2026-XML.zip"
icd9_url <- "https://www.cms.gov/Medicare/Coding/ICD9ProviderDiagnosticCodes/Downloads/ICD-9-CM-v32-master-descriptions.zip"

tmp_dir <- tempfile("ptv_icd_")
dir.create(tmp_dir, recursive = TRUE)
on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

download_zip <- function(url, destfile) {
  message("Downloading ", url)
  utils::download.file(url, destfile, mode = "wb", quiet = FALSE)
  destfile
}

normalize_code <- function(x) {
  gsub("[.[:space:]]", "", toupper(trimws(x)))
}

xml_unescape <- function(x) {
  x <- gsub("&amp;", "&", x, fixed = TRUE)
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x <- gsub("&quot;", "\"", x, fixed = TRUE)
  gsub("&apos;", "'", x, fixed = TRUE)
}

parse_icd10_tabular_xml <- function(path) {
  lines <- readLines(path, warn = FALSE)
  code <- character()
  desc <- character()
  pending_code <- NULL

  for (line in lines) {
    if (grepl("<name>[A-Z][A-Z0-9.]+</name>", line)) {
      pending_code <- sub(".*<name>([A-Z][A-Z0-9.]+)</name>.*", "\\1", line)
    } else if (!is.null(pending_code) && grepl("<desc>", line)) {
      code <- c(code, pending_code)
      desc <- c(desc, sub(".*<desc>([^<]+)</desc>.*", "\\1", line))
      pending_code <- NULL
    }
  }

  desc <- xml_unescape(desc)

  data.frame(
    code = normalize_code(code),
    billable = NA,
    short_desc = desc,
    long_desc = desc,
    code_system = "ICD-10-CM",
    version = "2026-April-1",
    stringsAsFactors = FALSE
  )
}

parse_icd9_titles <- function(short_path, long_path) {
  parse_file <- function(path, col_name) {
    lines <- readLines(path, warn = FALSE, encoding = "latin1")
    lines <- iconv(lines, from = "latin1", to = "UTF-8", sub = "")
    data.frame(
      code = normalize_code(substr(lines, 1, 5)),
      value = trimws(substr(lines, 7, nchar(lines))),
      stringsAsFactors = FALSE
    ) |>
      stats::setNames(c("code", col_name))
  }

  short <- parse_file(short_path, "short_desc")
  long <- parse_file(long_path, "long_desc")
  merged <- merge(short, long, by = "code", all = TRUE, sort = TRUE)
  merged$billable <- TRUE
  merged$code_system <- "ICD-9-CM"
  merged$version <- "32"
  merged[, c("code", "billable", "short_desc", "long_desc", "code_system", "version")]
}

write_lookup <- function(df, path) {
  df <- df[!is.na(df$code) & df$code != "", , drop = FALSE]
  utils::write.csv(df, path, row.names = FALSE, na = "")
  message("Wrote ", path, " (", nrow(df), " rows)")
}

sha256 <- function(path) {
  as.character(tools::sha256sum(path)[[1]])
}

icd10_zip <- file.path(tmp_dir, "icd10.zip")
icd9_zip <- file.path(tmp_dir, "icd9.zip")
download_zip(icd10_url, icd10_zip)
download_zip(icd9_url, icd9_zip)

icd10_dir <- file.path(tmp_dir, "icd10")
icd9_dir <- file.path(tmp_dir, "icd9")
utils::unzip(icd10_zip, exdir = icd10_dir)
utils::unzip(icd9_zip, exdir = icd9_dir)

icd10_lookup <- parse_icd10_tabular_xml(file.path(icd10_dir, "icd10c-tabular-April-1-2026.xml"))
icd9_lookup <- parse_icd9_titles(
  short_path = file.path(icd9_dir, "CMS32_DESC_SHORT_DX.txt"),
  long_path = file.path(icd9_dir, "CMS32_DESC_LONG_DX.txt")
)

icd10_path <- file.path(extdata_dir, "icd10cm_diagnosis_lookup.csv")
icd9_path <- file.path(extdata_dir, "icd9cm_diagnosis_lookup.csv")
metadata_path <- file.path(extdata_dir, "icd_lookup_metadata.yml")

write_lookup(icd10_lookup, icd10_path)
write_lookup(icd9_lookup, icd9_path)

metadata <- c(
  "icd10cm:",
  "  source: CDC/NCHS",
  "  fiscal_year: 2026",
  "  release: April 1 2026",
  "  effective_from: 2026-04-01",
  "  effective_to: 2026-09-30",
  paste0("  source_url: \"", icd10_url, "\""),
  paste0("  source_sha256: \"", sha256(icd10_zip), "\""),
  paste0("  lookup_sha256: \"", sha256(icd10_path), "\""),
  paste0("  row_count: ", nrow(icd10_lookup)),
  "icd9cm:",
  "  source: CMS",
  "  version: 32",
  "  effective_from: 2014-10-01",
  "  final_release: true",
  paste0("  source_url: \"", icd9_url, "\""),
  paste0("  source_sha256: \"", sha256(icd9_zip), "\""),
  paste0("  lookup_sha256: \"", sha256(icd9_path), "\""),
  paste0("  row_count: ", nrow(icd9_lookup)),
  paste0("generated_at: ", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
)
writeLines(metadata, metadata_path)
message("Wrote ", metadata_path)
