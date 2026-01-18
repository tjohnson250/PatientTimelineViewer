# db_queries.R
# SQL queries for retrieving patient data from PCORnet CDM tables
# Supports both MS SQL Server and DuckDB backends

library(DBI)
library(config)
library(dplyr)

# Global variable to track database type
.db_type <- NULL

#' Get the current database type
#' @return Character string: "mssql" or "duckdb"
get_db_type <- function() {
  if (is.null(.db_type)) {
    cfg <- config::get()
    .db_type <<- cfg$db_type %||% "mssql"
  }
  .db_type
}

#' Establish database connections
#' @return List with cdw and mpi connection objects
get_db_connections <- function() {
  cfg <- config::get()
  db_type <- cfg$db_type %||% "mssql"
  .db_type <<- db_type
  
  if (db_type == "duckdb") {
    # DuckDB connection
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      stop("DuckDB package not installed. Install with: install.packages('duckdb')")
    }
    
    duckdb_cfg <- cfg$duckdb
    
    # Resolve CDW path - handle relative paths from app directory
    cdw_path <- duckdb_cfg$cdw_path
    if (!file.exists(cdw_path)) {
      # Try relative to app directory
      app_dir <- getwd()
      alt_path <- file.path(app_dir, cdw_path)
      if (file.exists(alt_path)) {
        cdw_path <- alt_path
      } else {
        stop(paste0(
          "DuckDB CDW database file not found.\n",
          "  Configured path: ", duckdb_cfg$cdw_path, "\n",
          "  Working directory: ", app_dir, "\n",
          "  Checked: ", cdw_path, "\n",
          "  Also checked: ", alt_path, "\n",
          "Please verify the path in config.yml or use an absolute path."
        ))
      }
    }
    
    # Connect to CDW database (read_only = FALSE allows the file to be opened even if locked)
    cdw_conn <- DBI::dbConnect(
      duckdb::duckdb(),
      dbdir = cdw_path,
      read_only = FALSE
    )
    message(paste("Connected to CDW DuckDB:", cdw_path))
    
    # Connect to MPI database (may be same file or different)
    mpi_path <- duckdb_cfg$mpi_path %||% duckdb_cfg$cdw_path
    if (normalizePath(mpi_path, mustWork = FALSE) == normalizePath(cdw_path, mustWork = FALSE)) {
      # Same database file - reuse connection
      mpi_conn <- cdw_conn
      message("MPI using same connection as CDW")
    } else {
      # Resolve MPI path
      if (!file.exists(mpi_path)) {
        app_dir <- getwd()
        alt_path <- file.path(app_dir, mpi_path)
        if (file.exists(alt_path)) {
          mpi_path <- alt_path
        } else {
          stop(paste0(
            "DuckDB MPI database file not found.\n",
            "  Configured path: ", duckdb_cfg$mpi_path, "\n",
            "  Working directory: ", app_dir, "\n",
            "  Checked: ", mpi_path, "\n",
            "  Also checked: ", alt_path, "\n",
            "Please verify the path in config.yml or use an absolute path."
          ))
        }
      }
      
      mpi_conn <- DBI::dbConnect(
        duckdb::duckdb(),
        dbdir = mpi_path,
        read_only = FALSE
      )
      message(paste("Connected to MPI DuckDB:", mpi_path))
    }
    
    message("DuckDB connections established successfully")
    
  } else {
    # MS SQL Server connection via ODBC
    if (!requireNamespace("odbc", quietly = TRUE)) {
      stop("odbc package not installed. Install with: install.packages('odbc')")
    }
    
    mssql_cfg <- cfg$mssql %||% cfg  # Fallback for old config format
    
    # Connect using ODBC DSN and set database with USE statement
    cdw_cfg <- mssql_cfg$cdw %||% cfg$cdw
    cdw_conn <- DBI::dbConnect(odbc::odbc(), cdw_cfg$dsn)
    DBI::dbExecute(cdw_conn, paste("USE", cdw_cfg$database))
    
    mpi_cfg <- mssql_cfg$mpi %||% cfg$mpi
    mpi_conn <- DBI::dbConnect(odbc::odbc(), mpi_cfg$dsn)
    DBI::dbExecute(mpi_conn, paste("USE", mpi_cfg$database))
    
    message("Connected to MS SQL Server databases")
  }
  
  list(cdw = cdw_conn, mpi = mpi_conn, db_type = db_type)
}

#' Close database connections
#' @param conns List of connection objects
close_db_connections <- function(conns) {
  if (!is.null(conns$cdw)) {
    tryCatch(DBI::dbDisconnect(conns$cdw), error = function(e) NULL)
  }
  # Only disconnect MPI if it's a different connection
  if (!is.null(conns$mpi) && !identical(conns$cdw, conns$mpi)) {
    tryCatch(DBI::dbDisconnect(conns$mpi), error = function(e) NULL)
  }
}

#' Build schema-qualified table name based on database type
#' @param table_name Base table name
#' @param db_type Database type ("mssql" or "duckdb")
#' @return Schema-qualified table name
qualify_table <- function(table_name, db_type = get_db_type()) {
  if (db_type == "mssql") {
    paste0("dbo.", table_name)
  } else {
    # DuckDB - adjust schema as needed for your setup
    # By default, DuckDB uses 'main' schema
    table_name
  }
}

#' Execute a parameterized query with database-appropriate syntax
#' @param conn Database connection
#' @param sql SQL query with ? placeholders
#' @param params List of parameters
#' @return Query results as data frame
execute_query <- function(conn, sql, params = list()) {
  db_type <- get_db_type()
  
  # DuckDB uses $1, $2 style parameters, ODBC uses ?
  if (db_type == "duckdb" && length(params) > 0) {
    # Replace ? with $1, $2, etc. for DuckDB
    for (i in seq_along(params)) {
      sql <- sub("\\?", paste0("$", i), sql)
    }
  }
  
  # Adjust schema references
  if (db_type == "duckdb") {
    sql <- gsub("dbo\\.", "", sql)
  }
  
  DBI::dbGetQuery(conn, sql, params = params)
}

#' Query demographic data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with demographic information
query_demographic <- function(conn, patid) {
  sql <- "
    SELECT 
      PATID,
      BIRTH_DATE,
      BIRTH_TIME,
      SEX,
      RACE,
      HISPANIC,
      GENDER_IDENTITY,
      SEXUAL_ORIENTATION,
      PAT_PREF_LANGUAGE_SPOKEN,
      RAW_SEX,
      RAW_RACE,
      RAW_HISPANIC,
      UID,
      CDW_Source
    FROM dbo.DEMOGRAPHIC
    WHERE PATID = ?
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query source system mappings from MPI
#' @param mpi_conn MPI database connection
#' @param patid Patient ID (unified PATID)
#' @return Data frame with source system mappings
query_source_systems <- function(mpi_conn, patid) {
  # First get the UID from the CDW PATID
  # The MPI table links Src (source), Lid (local ID), and Uid (unified ID)
  sql <- "
    SELECT 
      m.Src,
      m.Lid,
      m.Uid,
      s.Description as SourceDescription
    FROM dbo.Mpi m
    LEFT JOIN dbo.MPI_Src s ON m.Src = s.SRC
    WHERE m.Uid = (
      SELECT DISTINCT Uid
      FROM dbo.EnterpriseRecords_Ext
      WHERE CDM_PATID = ?
    )
  "
  execute_query(mpi_conn, sql, params = list(patid))
}

#' Query encounter data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with encounter information
query_encounters <- function(conn, patid) {
  sql <- "
    SELECT 
      ENCOUNTERID,
      PATID,
      ADMIT_DATE,
      ADMIT_TIME,
      DISCHARGE_DATE,
      DISCHARGE_TIME,
      PROVIDERID,
      ENC_TYPE,
      FACILITY_LOCATION,
      FACILITYID,
      DISCHARGE_DISPOSITION,
      DISCHARGE_STATUS,
      DRG,
      DRG_TYPE,
      ADMITTING_SOURCE,
      RAW_ENC_TYPE,
      RAW_DISCHARGE_DISPOSITION,
      RAW_DISCHARGE_STATUS,
      PAYER_TYPE_PRIMARY,
      CDW_Source
    FROM dbo.ENCOUNTER
    WHERE PATID = ?
    ORDER BY ADMIT_DATE DESC
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query diagnosis data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with diagnosis information
query_diagnoses <- function(conn, patid) {
  sql <- "
    SELECT 
      DIAGNOSISID,
      PATID,
      ENCOUNTERID,
      DX,
      DX_TYPE,
      DX_DATE,
      DX_SOURCE,
      DX_ORIGIN,
      DX_POA,
      PDX,
      ADMIT_DATE,
      ENC_TYPE,
      PROVIDERID,
      RAW_DX,
      RAW_DX_TYPE,
      RAW_DX_SOURCE,
      RAW_PDX,
      CDW_Source
    FROM dbo.DIAGNOSIS
    WHERE PATID = ?
    ORDER BY COALESCE(DX_DATE, ADMIT_DATE) DESC
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query procedures data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with procedures information
query_procedures <- function(conn, patid) {
  sql <- "
    SELECT 
      PROCEDURESID,
      PATID,
      ENCOUNTERID,
      PX,
      PX_TYPE,
      PX_DATE,
      PX_SOURCE,
      PPX,
      ADMIT_DATE,
      ENC_TYPE,
      PROVIDERID,
      RAW_PX,
      RAW_PX_TYPE,
      RAW_PX_NAME,
      CDW_Source
    FROM dbo.PROCEDURES
    WHERE PATID = ?
    ORDER BY COALESCE(PX_DATE, ADMIT_DATE) DESC
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query lab results for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with lab result information
query_labs <- function(conn, patid) {
  sql <- "
    SELECT 
      LAB_RESULT_CM_ID,
      PATID,
      ENCOUNTERID,
      LAB_LOINC,
      LAB_PX,
      LAB_PX_TYPE,
      LAB_ORDER_DATE,
      RESULT_DATE,
      RESULT_TIME,
      RESULT_NUM,
      RESULT_QUAL,
      RESULT_MODIFIER,
      RESULT_UNIT,
      NORM_RANGE_LOW,
      NORM_RANGE_HIGH,
      NORM_MODIFIER_LOW,
      NORM_MODIFIER_HIGH,
      ABN_IND,
      SPECIMEN_SOURCE,
      SPECIMEN_DATE,
      PRIORITY,
      RESULT_LOC,
      LAB_LOINC_SOURCE,
      LAB_RESULT_SOURCE,
      RAW_LAB_NAME,
      RAW_LAB_CODE,
      RAW_RESULT,
      RAW_UNIT,
      CDW_Source
    FROM dbo.LAB_RESULT_CM
    WHERE PATID = ?
    ORDER BY RESULT_DATE DESC
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query prescribing data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with prescribing information
query_prescribing <- function(conn, patid) {
  sql <- "
    SELECT 
      PRESCRIBINGID,
      PATID,
      ENCOUNTERID,
      RX_PROVIDERID,
      RX_ORDER_DATE,
      RX_ORDER_TIME,
      RX_START_DATE,
      RX_END_DATE,
      RX_DAYS_SUPPLY,
      RX_REFILLS,
      RX_QUANTITY,
      RX_DOSE_ORDERED,
      RX_DOSE_ORDERED_UNIT,
      RX_DOSE_FORM,
      RX_FREQUENCY,
      RX_ROUTE,
      RX_BASIS,
      RX_PRN_FLAG,
      RX_DISPENSE_AS_WRITTEN,
      RX_SOURCE,
      RXNORM_CUI,
      RAW_RX_MED_NAME,
      RAW_RX_FREQUENCY,
      RAW_RX_DOSE_ORDERED,
      RAW_RX_DOSE_ORDERED_UNIT,
      RAW_RX_ROUTE,
      RAW_RX_REFILLS,
      RAW_RXNORM_CUI,
      RAW_RX_NDC,
      CDW_Source
    FROM dbo.PRESCRIBING
    WHERE PATID = ?
    ORDER BY COALESCE(RX_START_DATE, RX_ORDER_DATE) DESC
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query dispensing data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with dispensing information
query_dispensing <- function(conn, patid) {
  sql <- "
    SELECT 
      DISPENSINGID,
      PATID,
      PRESCRIBINGID,
      DISPENSE_DATE,
      NDC,
      DISPENSE_SUP,
      DISPENSE_AMT,
      DISPENSE_DOSE_DISP,
      DISPENSE_DOSE_DISP_UNIT,
      DISPENSE_ROUTE,
      DISPENSE_SOURCE,
      RAW_NDC,
      RAW_DISPENSE_DOSE_DISP,
      RAW_DISPENSE_DOSE_DISP_UNIT,
      RAW_DISPENSE_ROUTE,
      RAW_DISP_MED_NAME,
      CDW_Source
    FROM dbo.DISPENSING
    WHERE PATID = ?
    ORDER BY DISPENSE_DATE DESC
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query vital signs data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with vital signs information
query_vitals <- function(conn, patid) {
  sql <- "
    SELECT 
      VITALID,
      PATID,
      ENCOUNTERID,
      MEASURE_DATE,
      MEASURE_TIME,
      VITAL_SOURCE,
      HT,
      WT,
      ORIGINAL_BMI,
      SYSTOLIC,
      DIASTOLIC,
      BP_POSITION,
      SMOKING,
      TOBACCO,
      TOBACCO_TYPE,
      RAW_SYSTOLIC,
      RAW_DIASTOLIC,
      RAW_BP_POSITION,
      RAW_SMOKING,
      RAW_TOBACCO,
      RAW_TOBACCO_TYPE,
      CDW_Source
    FROM dbo.VITAL
    WHERE PATID = ?
    ORDER BY MEASURE_DATE DESC
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query condition data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with condition information
query_conditions <- function(conn, patid) {
  sql <- "
    SELECT 
      CONDITIONID,
      PATID,
      ENCOUNTERID,
      CONDITION,
      CONDITION_TYPE,
      CONDITION_STATUS,
      CONDITION_SOURCE,
      ONSET_DATE,
      REPORT_DATE,
      RESOLVE_DATE,
      RAW_CONDITION,
      RAW_CONDITION_TYPE,
      RAW_CONDITION_STATUS,
      RAW_CONDITION_SOURCE,
      CDW_Source
    FROM dbo.CONDITION
    WHERE PATID = ?
    ORDER BY COALESCE(ONSET_DATE, REPORT_DATE) DESC
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query death data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with death information (if exists)
query_death <- function(conn, patid) {
  sql <- "
    SELECT 
      PATID,
      DEATH_DATE,
      DEATH_DATE_IMPUTE,
      DEATH_SOURCE,
      DEATH_MATCH_CONFIDENCE
    FROM dbo.DEATH
    WHERE PATID = ?
  "
  execute_query(conn, sql, params = list(patid))
}

#' Query death cause data for a patient
#' @param conn Database connection
#' @param patid Patient ID
#' @return Data frame with death cause information (if exists)
query_death_cause <- function(conn, patid) {
  sql <- "
    SELECT 
      PATID,
      DEATH_CAUSE,
      DEATH_CAUSE_CODE,
      DEATH_CAUSE_TYPE,
      DEATH_CAUSE_SOURCE,
      DEATH_CAUSE_CONFIDENCE
    FROM dbo.DEATH_CAUSE
    WHERE PATID = ?
  "
  execute_query(conn, sql, params = list(patid))
}

#' Load all patient data
#' @param conns Database connections list
#' @param patid Patient ID
#' @return List of data frames for all clinical data
load_patient_data <- function(conns, patid) {
  list(
    demographic = query_demographic(conns$cdw, patid),
    source_systems = tryCatch(
      query_source_systems(conns$mpi, patid),
      error = function(e) data.frame()
    ),
    encounters = query_encounters(conns$cdw, patid),
    diagnoses = query_diagnoses(conns$cdw, patid),
    procedures = query_procedures(conns$cdw, patid),
    labs = query_labs(conns$cdw, patid),
    prescribing = query_prescribing(conns$cdw, patid),
    dispensing = query_dispensing(conns$cdw, patid),
    vitals = query_vitals(conns$cdw, patid),
    conditions = query_conditions(conns$cdw, patid),
    death = query_death(conns$cdw, patid),
    death_cause = query_death_cause(conns$cdw, patid)
  )
}

#' Get total event count across all tables
#' @param patient_data List of patient data frames
#' @return Integer count of total events
get_total_event_count <- function(patient_data) {
  sum(
    nrow(patient_data$encounters),
    nrow(patient_data$diagnoses),
    nrow(patient_data$procedures),
    nrow(patient_data$labs),
    nrow(patient_data$prescribing),
    nrow(patient_data$dispensing),
    nrow(patient_data$vitals),
    nrow(patient_data$conditions)
  )
}
