# semantic_filter.R
# Functions for generating and validating SQL from natural language queries using Claude API

library(httr2)

#' Load PCORnet schema context from file
#' @return Character string with schema documentation
load_schema_context <- function() {
  schema_file <- "R/pcornet_schema.txt"
  if (file.exists(schema_file)) {
    return(readLines(schema_file, warn = FALSE) |> paste(collapse = "\n"))
  } else {
    warning("Schema context file not found. Using minimal schema.")
    return("
    ENCOUNTER: PATID, ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, ENC_TYPE (IP/ED/AV/OA)
    DIAGNOSIS: PATID, DIAGNOSISID, DX, DX_TYPE (09=ICD9, 10=ICD10), DX_DATE, PDX
    LAB_RESULT_CM: PATID, LAB_RESULT_CM_ID, RAW_LAB_NAME, RESULT_NUM, RESULT_DATE, ABN_IND
    PRESCRIBING: PATID, PRESCRIBINGID, RAW_RX_MED_NAME, RX_START_DATE
    ")
  }
}

#' Generate SQL query from natural language using Claude API
#' @param natural_query User's natural language query
#' @param patid Patient ID to filter by
#' @param schema_context PCORnet schema documentation
#' @param db_type Database type ("mssql" or "duckdb")
#' @return Generated SQL query string
generate_filter_sql <- function(natural_query, patid, schema_context = NULL, db_type = "mssql") {
  # Check for API key
  api_key <- Sys.getenv("ANTHROPIC_API_KEY")
  if (api_key == "") {
    stop("ANTHROPIC_API_KEY environment variable not set")
  }

  # Load schema if not provided
  if (is.null(schema_context)) {
    schema_context <- load_schema_context()
  }

  # Build system prompt
  schema_prefix <- if (db_type == "mssql") "dbo." else ""

  system_prompt <- paste0(
'You are a SQL expert for PCORnet Common Data Model (CDM) databases running on ',
toupper(db_type), '.

Your task: Convert natural language queries into SQL that filters patient clinical data.

CRITICAL REQUIREMENTS:
1. ALWAYS include: WHERE PATID = \'', patid, '\' in your query
2. ONLY generate SELECT statements. NEVER use INSERT, UPDATE, DELETE, DROP, or other modifying commands
3. Return ONLY the SQL query - no explanations, no markdown, no code blocks
4. Use ', if (db_type == "mssql") '"dbo." prefix for all table names' else 'table names without schema prefix', '
5. The query should return rows from ONE clinical table that match the user\'s criteria
6. For code pattern searches (ICD codes, etc.), use LIKE with wildcards (%)
7. For text searches (lab names, medication names), use LIKE with wildcards on both sides (%term%)
8. IMPORTANT: For medication queries, search BOTH PRESCRIBING and DISPENSING tables using UNION ALL unless the user specifically mentions "prescriptions" or "dispensing" only
9. CRITICAL FOR MEDICATIONS: ONLY search the text name fields, NOT the code fields:
   - PRESCRIBING: ONLY search RAW_RX_MED_NAME (do NOT search RXNORM_CUI or NDC codes with drug names)
   - DISPENSING: ONLY search RAW_DISP_MED_NAME (do NOT search NDC or RAW_NDC with drug names)
   - Code fields contain numbers/codes, not medication names
10. For medication therapeutic class queries (like "pain relief"), translate to specific drug names:
   - "pain relief" or "pain" → search for aspirin, ibuprofen, acetaminophen, naproxen, etc.
   - "statins" → search for atorvastatin, simvastatin, rosuvastatin, pravastatin, lovastatin, etc.
   - "beta blockers" → search for metoprolol, atenolol, carvedilol, propranolol, etc.
   - Use OR conditions to search for multiple drug names in the same query

Available tables and columns:
', schema_context, '

EXAMPLES:

User: "Show encounters with A1c > 9"
Response:
SELECT * FROM ', schema_prefix, 'LAB_RESULT_CM
WHERE PATID = \'', patid, '\'
  AND RAW_LAB_NAME LIKE \'%hemoglobin A1c%\'
  AND RESULT_NUM > 9

User: "Show only inpatient encounters"
Response:
SELECT * FROM ', schema_prefix, 'ENCOUNTER
WHERE PATID = \'', patid, '\'
  AND ENC_TYPE = \'IP\'

User: "Show diagnoses containing diabetes"
Response:
SELECT * FROM ', schema_prefix, 'DIAGNOSIS
WHERE PATID = \'', patid, '\'
  AND (DX LIKE \'E11%\' OR RAW_DX LIKE \'%diabetes%\')

User: "Show statins"
Response:
SELECT PRESCRIBINGID as ID, PATID, RX_START_DATE as EVENT_DATE,
       RAW_RX_MED_NAME as MED_NAME, \'prescribing\' as SOURCE_TABLE
FROM ', schema_prefix, 'PRESCRIBING
WHERE PATID = \'', patid, '\'
  AND (RAW_RX_MED_NAME LIKE \'%atorvastatin%\'
       OR RAW_RX_MED_NAME LIKE \'%simvastatin%\'
       OR RAW_RX_MED_NAME LIKE \'%rosuvastatin%\'
       OR RAW_RX_MED_NAME LIKE \'%pravastatin%\'
       OR RAW_RX_MED_NAME LIKE \'%lovastatin%\')
UNION ALL
SELECT DISPENSINGID as ID, PATID, DISPENSE_DATE as EVENT_DATE,
       RAW_DISP_MED_NAME as MED_NAME, \'dispensing\' as SOURCE_TABLE
FROM ', schema_prefix, 'DISPENSING
WHERE PATID = \'', patid, '\'
  AND (RAW_DISP_MED_NAME LIKE \'%atorvastatin%\'
       OR RAW_DISP_MED_NAME LIKE \'%simvastatin%\'
       OR RAW_DISP_MED_NAME LIKE \'%rosuvastatin%\'
       OR RAW_DISP_MED_NAME LIKE \'%pravastatin%\'
       OR RAW_DISP_MED_NAME LIKE \'%lovastatin%\')

User: "Show medications for pain relief"
Response:
SELECT PRESCRIBINGID as ID, PATID, RX_START_DATE as EVENT_DATE,
       RAW_RX_MED_NAME as MED_NAME, \'prescribing\' as SOURCE_TABLE
FROM ', schema_prefix, 'PRESCRIBING
WHERE PATID = \'', patid, '\'
  AND (RAW_RX_MED_NAME LIKE \'%aspirin%\'
       OR RAW_RX_MED_NAME LIKE \'%ibuprofen%\'
       OR RAW_RX_MED_NAME LIKE \'%acetaminophen%\'
       OR RAW_RX_MED_NAME LIKE \'%naproxen%\'
       OR RAW_RX_MED_NAME LIKE \'%tylenol%\'
       OR RAW_RX_MED_NAME LIKE \'%advil%\'
       OR RAW_RX_MED_NAME LIKE \'%motrin%\'
       OR RAW_RX_MED_NAME LIKE \'%aleve%\')
UNION ALL
SELECT DISPENSINGID as ID, PATID, DISPENSE_DATE as EVENT_DATE,
       RAW_DISP_MED_NAME as MED_NAME, \'dispensing\' as SOURCE_TABLE
FROM ', schema_prefix, 'DISPENSING
WHERE PATID = \'', patid, '\'
  AND (RAW_DISP_MED_NAME LIKE \'%aspirin%\'
       OR RAW_DISP_MED_NAME LIKE \'%ibuprofen%\'
       OR RAW_DISP_MED_NAME LIKE \'%acetaminophen%\'
       OR RAW_DISP_MED_NAME LIKE \'%naproxen%\'
       OR RAW_DISP_MED_NAME LIKE \'%tylenol%\'
       OR RAW_DISP_MED_NAME LIKE \'%advil%\'
       OR RAW_DISP_MED_NAME LIKE \'%motrin%\'
       OR RAW_DISP_MED_NAME LIKE \'%aleve%\')

User: "Show prescriptions for metformin" (user specifically said "prescriptions")
Response:
SELECT * FROM ', schema_prefix, 'PRESCRIBING
WHERE PATID = \'', patid, '\'
  AND RAW_RX_MED_NAME LIKE \'%metformin%\'

Now generate the SQL for the user\'s query.')

  # Make API request
  tryCatch({
    # Model selection - change this to use a different Claude model
    # Available models:
    #   - claude-sonnet-4-20250514 (default: best balance of speed/accuracy/cost)
    #   - claude-opus-4-20250514 (highest accuracy, slower, more expensive)
    #   - claude-haiku-4-20250514 (fastest, cheapest, less accurate)
    # See https://docs.anthropic.com/en/docs/models-overview for latest models
    model_name <- "claude-sonnet-4-20250514"

    response <- request("https://api.anthropic.com/v1/messages") |>
      req_headers(
        `x-api-key` = api_key,
        `anthropic-version` = "2023-06-01",
        `content-type` = "application/json"
      ) |>
      req_body_json(list(
        model = model_name,
        max_tokens = 1024,
        system = system_prompt,
        messages = list(list(role = "user", content = natural_query))
      )) |>
      req_perform() |>
      resp_body_json()

    # Extract SQL from response
    sql <- response$content[[1]]$text

    # Clean up the SQL (remove markdown code blocks if present)
    sql <- gsub("```sql\\n?", "", sql)
    sql <- gsub("```\\n?", "", sql)
    sql <- trimws(sql)

    return(sql)

  }, error = function(e) {
    stop(paste("Claude API error:", e$message))
  })
}

#' Validate generated SQL for safety
#' @param sql SQL query to validate
#' @param patid Patient ID that must be referenced
#' @param db_type Database type ("mssql" or "duckdb")
#' @return TRUE if valid, stops with error if invalid
validate_sql <- function(sql, patid, db_type = "mssql") {
  sql_upper <- toupper(sql)

  # Block dangerous operations
  dangerous_keywords <- c(
    "INSERT", "UPDATE", "DELETE", "DROP", "TRUNCATE",
    "ALTER", "CREATE", "EXEC", "EXECUTE", "GRANT", "REVOKE",
    "MERGE", "RENAME", "REPLACE"
  )

  for (keyword in dangerous_keywords) {
    # Use word boundary regex to avoid false positives
    if (grepl(paste0("\\b", keyword, "\\b"), sql_upper)) {
      stop(paste("Security violation: SQL contains prohibited keyword:", keyword))
    }
  }

  # Must be a SELECT statement
  if (!grepl("^\\s*SELECT", sql_upper)) {
    stop("Only SELECT queries are allowed")
  }

  # Must reference the current patient ID
  if (!grepl(patid, sql, fixed = TRUE)) {
    stop(paste("SQL must filter by current PATID:", patid))
  }

  # Must have a WHERE clause with PATID
  if (!grepl("WHERE.*PATID", sql_upper)) {
    stop("SQL must include WHERE PATID = ... clause")
  }

  # Check for proper schema qualification based on db_type
  if (db_type == "mssql") {
    # MS SQL Server - should have dbo. prefix
    if (!grepl("FROM\\s+dbo\\.", sql_upper)) {
      # Add a warning but don't fail
      warning("SQL should use 'dbo.' schema prefix for MS SQL Server tables")
    }
  } else if (db_type == "duckdb") {
    # DuckDB - should NOT have dbo. prefix
    if (grepl("dbo\\.", sql_upper)) {
      stop("DuckDB queries should not use 'dbo.' schema prefix")
    }
  }

  # All checks passed
  invisible(TRUE)
}

#' Apply semantic filter to patient data
#' @param natural_query User's natural language query
#' @param patid Patient ID
#' @param db_conn Database connection
#' @param db_type Database type ("mssql" or "duckdb")
#' @return List with filtered_data (data frame), sql (query used), and error (if any)
apply_semantic_filter <- function(natural_query, patid, db_conn, db_type = "mssql") {
  result <- list(
    filtered_data = NULL,
    sql = NULL,
    error = NULL,
    message = NULL
  )

  tryCatch({
    # Generate SQL
    result$sql <- generate_filter_sql(natural_query, patid, db_type = db_type)

    # Validate SQL
    validate_sql(result$sql, patid, db_type = db_type)

    # Execute query
    result$filtered_data <- DBI::dbGetQuery(db_conn, result$sql)

    # Generate success message
    result$message <- paste(
      "Found", nrow(result$filtered_data), "matching record(s)"
    )

  }, error = function(e) {
    result$error <<- e$message
  })

  return(result)
}
