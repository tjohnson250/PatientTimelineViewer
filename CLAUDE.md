# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Patient Timeline Viewer is a Shiny application for visualizing comprehensive temporal patient data from a PCORnet CDM data warehouse. It supports both MS SQL Server (production) and DuckDB (development/testing) backends.

## Running the Application

```r
# Run with default configuration profile
shiny::runApp()

# Run with specific configuration profile
Sys.setenv(R_CONFIG_ACTIVE = "production")
shiny::runApp()

# Or for local development
Sys.setenv(R_CONFIG_ACTIVE = "local")
shiny::runApp()
```

## Configuration System

The application uses `config.yml` with profile-based configuration. Configuration is managed through the `config` R package:

- `db_type`: Either `"mssql"` or `"duckdb"`
- `mssql`: Configuration for MS SQL Server connections (DSN and database names)
- `duckdb`: Configuration for DuckDB file paths

**Important**: The application establishes database connections on startup and maintains them throughout the session. Connection management is handled in `R/db_queries.R` through:
- `get_db_connections()`: Establishes connections based on config
- `close_db_connections()`: Cleanup on session end

## Architecture

### Modular Design

The application follows a modular architecture with clear separation of concerns:

1. **app.R**: Main Shiny application (UI + Server)
2. **R/db_queries.R**: Database abstraction layer
3. **R/data_transforms.R**: Data transformation to timeline format
4. **R/aggregation.R**: Event aggregation logic
5. **R/filter_helpers.R**: Filtering operations

### Data Flow

```
Database (MS SQL Server or DuckDB)
    ↓
db_queries.R: load_patient_data() → Returns list of data frames
    ↓
data_transforms.R: transform_all_to_timevis() → Timeline event format
    ↓
filter_helpers.R: apply_all_filters() → Filtered events
    ↓
aggregation.R: aggregate_events() → Daily/weekly aggregated events
    ↓
timevis library renders the timeline
```

### Database Abstraction

The `db_queries.R` module provides database-agnostic queries:

- **execute_query()**: Handles parameter binding differences between DuckDB ($1, $2) and ODBC (?)
- **qualify_table()**: Adds schema qualifiers for MS SQL Server (dbo.) but not DuckDB
- All queries use the same SQL syntax with automatic adaptations

When adding new queries:
1. Use `execute_query()` instead of `DBI::dbGetQuery()` directly
2. Use `?` placeholders for parameters (automatically converted for DuckDB)
3. Reference tables without schema prefix (automatically qualified if needed)

### Date Handling Strategy

**Critical**: The codebase has specific date handling to work with both database backends:

- Raw database dates come as Date, POSIXct, or character depending on backend
- **safe_parse_date()** in `data_transforms.R` handles all conversions robustly
- Transform functions parse dates VECTORIZED FIRST (before rowwise operations)
- Final timeline format uses character dates in "YYYY-MM-DD" format (required by timevis)

When modifying transforms, always:
1. Parse dates vectorized before any rowwise operations
2. Use `safe_parse_date()` for all date conversions
3. Format final dates as character strings for timevis

### Event Transform Pattern

Each PCORnet table has a dedicated transform function following this pattern:

```r
transform_[table_type] <- function(data) {
  # 1. Handle empty data
  # 2. Parse dates VECTORIZED first
  # 3. Filter out records with missing dates
  # 4. Use rowwise() only for tooltip generation
  # 5. Return standard timevis format with these columns:
  #    - id, content, start, end, group, type, className
  #    - title (HTML tooltip), source_table, source_key, event_type
}
```

### Event Aggregation

Aggregation combines multiple events into single timeline markers:

- **Individual**: No aggregation, every event shown separately
- **Daily**: Events of same type on same date collapsed with count
- **Weekly**: Events grouped by ISO week

Only point events are aggregated. Range events (encounters with discharge dates) and death markers are never aggregated.

### Filtering Architecture

Filters are applied in `apply_all_filters()` sequentially:

1. Event type selection (checkboxes)
2. Date range
3. Diagnosis code pattern (SQL LIKE syntax)
4. Procedure code pattern (SQL LIKE syntax)
5. Lab name (partial text match)
6. Medication name (partial text match)

Each filter function:
- Returns the full dataset if filter is empty/null
- For type-specific filters (dx, px, lab, med): keeps all non-matching event types unchanged
- Only filters the relevant event type

### Reactive Value Structure

The server maintains state in `rv` reactive values:

```r
rv <- reactiveValues(
  patient_data = NULL,      # List of raw data frames from database
  timeline_events = NULL,   # Transformed events (before filtering)
  selected_event = NULL,    # Currently selected event details
  db_connections = NULL,    # Active database connections
  date_range = NULL         # Min/max dates for the patient
)
```

## PCORnet CDM Tables Queried

The application queries these PCORnet Common Data Model tables:
- DEMOGRAPHIC
- ENCOUNTER
- DIAGNOSIS
- PROCEDURES
- LAB_RESULT_CM
- PRESCRIBING
- DISPENSING
- VITAL
- CONDITION
- DEATH
- DEATH_CAUSE

Additionally, from MasterPatientIndex database:
- Mpi (source system mappings)
- SourceRecords_Ext (CDM PATID to UID mapping)

## Event Type Color Scheme

Colors are defined in `www/custom.css` and should remain consistent:

- Encounters: #3498db (Blue)
- Diagnoses: #e74c3c (Coral)
- Procedures: #9b59b6 (Purple)
- Labs: #27ae60 (Green)
- Prescribing: #e67e22 (Orange)
- Dispensing: #f39c12 (Amber)
- Vitals: #1abc9c (Teal)
- Conditions: #e91e63 (Pink)
- Death: #2c3e50 (Dark Gray)

## Special Features

### Related Events for Encounters

When an encounter is selected, users can click "Show Related Events" to:
1. Update date filters to the encounter's admit/discharge window (+/- 1 day)
2. Zoom the timeline to that date range
3. Show all events that occurred during that encounter

Implementation uses the timevis `setWindow()` function.

### Death Marker Handling

Death events are displayed as special markers:
- Span across all groups (group = NA)
- Always shown regardless of event type filters
- Events after death date remain visible for data quality review

### Abnormal Lab Results

Labs with ABN_IND values (AB, AH, AL, CH, CL, CR) get special styling:
- className includes "event-lab-abnormal"
- Indicator appended to formatted result in tooltip

## Adding New Event Types

To add a new PCORnet table type:

1. **db_queries.R**: Add `query_[tablename]()` function
2. **db_queries.R**: Add table to `load_patient_data()` list
3. **data_transforms.R**: Create `transform_[tablename]()` following the established pattern
4. **data_transforms.R**: Add to `transform_all_to_timevis()` bind_rows
5. **filter_helpers.R**: Add to `get_event_type_counts()`
6. **app.R**: Add checkbox to UI in `output$event_type_checkboxes`
7. **app.R**: Add to `get_selected_event_types()` reactive
8. **www/custom.css**: Define color class
9. **app.R**: Add event detail rendering in `output$event_details`

## Testing with DuckDB

For local development/testing, create a DuckDB database with PCORnet schema:

```r
library(duckdb)
library(DBI)

con <- dbConnect(duckdb(), "data/cdw.duckdb")

# Create tables matching PCORnet CDM schema
# No need for "dbo." schema prefix in DuckDB
# Insert test data

dbDisconnect(con)
```

Then set `config.yml` to use `db_type: "duckdb"` and point to your database file.

## Common Pitfalls

1. **Don't use DBI::dbGetQuery() directly**: Use `execute_query()` to handle database differences
2. **Don't parse dates in rowwise context**: Always vectorize date parsing before rowwise operations
3. **Don't return Date objects to timevis**: Convert to character format "YYYY-MM-DD"
4. **Don't forget to filter out NA dates**: Events without dates cause timeline rendering issues
5. **Don't assume MPI database is available**: Wrap `query_source_systems()` in tryCatch
