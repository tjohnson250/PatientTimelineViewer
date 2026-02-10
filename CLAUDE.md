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

1. **app.R**: Development entry point (sources modules, runs shinyApp)
2. **R/app_ui_server.R**: Single source of truth for UI (`timeline_ui()`) and server (`timeline_server`) logic
3. **R/db_queries.R**: Database abstraction layer (connections, queries, PATID autocomplete search)
4. **R/data_transforms.R**: Data transformation to timeline format (includes ICD code description integration)
5. **R/aggregation.R**: Event aggregation logic
6. **R/filter_helpers.R**: Filtering operations (event type, date range, encounter type, source system, semantic results)
7. **R/semantic_filter.R**: AI-powered semantic filtering via Claude API (optional, requires `httr2` and API key)
8. **R/icd_lookup.R**: ICD-10-CM and ICD-9-CM code description lookups (optional, requires `icd.data`)
9. **R/runExample.R**: Package interface functions (`runExample()`, `viewTimeline()`, `stopViewer()`, `get_sample_data_path()`)
10. **R/globals.R**: Global variable declarations for R CMD check compliance

JavaScript modules in `www/`:
- **cluster-colors.js**: Manages color assignment for clustered events
- **timeline-markers.js**: Timeline marker manipulation and rendering
- **timeline-resizer.js**: Draggable resize handle for timeline pane height
- **timeline-overview.js**: Minimap/overview panel with draggable viewport and filter range handles

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

1. Semantic filter results (AI-generated SQL, applied first if active)
2. Event type selection (checkboxes)
3. Source system selection (checkboxes, when patient has multiple sources)
4. Date range
5. Encounter type (IP, ED, AV, etc. - also filters linked diagnoses/procedures/labs/vitals)
6. Diagnosis code pattern (SQL LIKE syntax)
7. Procedure code pattern (SQL LIKE syntax)
8. Lab name (partial text match)
9. Medication name (partial text match)

Each filter function:
- Returns the full dataset if filter is empty/null
- For type-specific filters (dx, px, lab, med): keeps all non-matching event types unchanged
- Only filters the relevant event type

### Reactive Value Structure

The server maintains state in `rv` reactive values:

```r
rv <- reactiveValues(
  patient_data = NULL,          # List of raw data frames from database
  timeline_events = NULL,       # Transformed events (before filtering)
  selected_event = NULL,        # Currently selected event details
  db_connections = NULL,        # Active database connections
  date_range = NULL,            # Min/max dates for the patient
  semantic_filter_active = FALSE,  # Whether AI filter is currently applied
  semantic_filter_sql = NULL,      # Generated SQL query text
  semantic_filter_table = NULL,    # Which table(s) the semantic filter targets
  semantic_filter_results = NULL,  # Query results from semantic filter
  loading_in_progress = FALSE      # Whether patient data is currently loading
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
- Mpi (source system mappings: Src, Lid, Uid)
- MPI_Src (source system descriptions)

## Event Type Color Scheme

Colors use a muted 8-hue palette with hues spaced ~45° apart for maximum distinguishability. Each event type has a pastel background and a slightly darker border, defined in `www/custom.css`, `R/app_ui_server.R` (inline styles in `filtered_events()`), and `inst/example/www/custom.css`:

- Encounters: bg #d4dded / border #a9bbdb (Blue, 220°)
- Diagnoses: bg #f0d4d4 / border #dba9a9 (Red, 0°)
- Procedures: bg #ded4ed / border #bda9db (Purple, 280°)
- Labs: bg #d4eddb / border #a9dbb8 (Green, 140°)
- Prescribing: bg #edded4 / border #dbbda9 (Orange, 30°)
- Dispensing: bg #ede8d4 / border #dbd1a9 (Gold, 55°)
- Vitals: bg #d4ebed / border #a9d7db (Cyan, 190°)
- Conditions: bg #edd4e7 / border #dba9cf (Magenta, 325°)
- Death: bg #d5d8dc / border #85929e (Gray)

When modifying colors, update all three locations: CSS (indicators, event items, cluster items, data-group selectors), R inline styles, and the example CSS.

## Special Features

### PATID Autocomplete

Type-ahead search with 300ms debounce. After 2+ characters are typed, matching PATIDs are queried from the DEMOGRAPHIC table and shown in a dropdown with DOB/sex details. Clicking a result auto-loads the patient. Implementation uses custom JavaScript in `app_ui_server.R` and the `search_patids()` function in `db_queries.R`.

### ICD Code Description Lookup

When the `icd.data` package is installed, diagnosis events automatically display human-readable code descriptions alongside ICD-10-CM and ICD-9-CM codes. Lookups are cached in memory for performance. Implementation is in `R/icd_lookup.R` with integration in `data_transforms.R`.

### Timeline Overview Minimap

A miniature representation of the full timeline displayed below the main timeline. Features:
- **Draggable viewport rectangle**: Pan the main timeline by dragging the blue viewport area
- **Orange filter range handles**: Drag to set the date range filter; changes sync bidirectionally with the date inputs
- Implementation in `www/timeline-overview.js` with server-side support in `app_ui_server.R`

### Compact Display & Filters Panel

All display controls are consolidated into a single "Display & Filters" panel (previously three separate panels: AI Filter, Display Options, Color Scheme). The panel has three rows:

1. **Row 1**: AI filter text input + Apply/Clear buttons + Color By dropdown
2. **Row 2**: Event type checkboxes (3-column CSS grid with colored indicator squares) + Source system checkboxes (with colored indicator squares matching left-border colors)
3. **Row 3**: Aggregation radio buttons + Enable auto-clustering + Show event labels + collapsible Advanced Filters

The event type checkboxes double as the color legend — colored squares on each checkbox match the timeline event colors. A separate legend is only shown when Color By is set to "Source System".

### Event Label Toggle

A "Show event labels" checkbox controls whether text labels appear on timeline markers. When unchecked, a `hide-labels` CSS class is applied and point events shrink to 6px dots. Uses DataSet update to force vis.js to remeasure items after toggling.

### Color Scheme Selector

Toggle between "Event Type" (default) and "Source System" coloring via a dropdown in the Display & Filters panel. Source system colors use a palette of 8 distinct colors with CSS left-border indicators. Source system checkboxes display colored indicator squares matching these border colors. Source system information comes from the MPI database when available.

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

### Resizable Timeline Pane

A draggable resize handle at the bottom of the timeline pane allows users to adjust the timeline height. Implementation in `www/timeline-resizer.js`.

### Loading Progress Indicator

When loading patient data, a step-by-step progress indicator shows which data tables are being queried. The progress is cancellable.

## Adding New Event Types

To add a new PCORnet table type:

1. **R/db_queries.R**: Add `query_[tablename]()` function
2. **R/db_queries.R**: Add table to `load_patient_data()` list
3. **R/data_transforms.R**: Create `transform_[tablename]()` following the established pattern
4. **R/data_transforms.R**: Add to `transform_all_to_timevis()` bind_rows
5. **R/filter_helpers.R**: Add to `get_event_type_counts()`
6. **R/app_ui_server.R**: Add checkbox to UI in `output$event_type_checkboxes`
7. **R/app_ui_server.R**: Add to `get_selected_event_types()` reactive
8. **R/app_ui_server.R**: Add to `event_colors` list in `filtered_events()` reactive
9. **www/custom.css**: Define color classes (`.color-indicator`, `.vis-item.event-*`, `.vis-item.vis-cluster.event-*`, `.vis-item.vis-cluster[data-group="*"]`)
10. **inst/example/www/custom.css**: Mirror the same color classes
11. **R/app_ui_server.R**: Add event detail rendering in `output$event_details`

## Testing with DuckDB

The package includes bundled synthetic sample data in `inst/extdata/`. For local development/testing:

```r
# Use bundled sample data (recommended)
library(PatientTimelineViewer)
runExample()

# Or create your own DuckDB database with PCORnet schema
library(duckdb)
library(DBI)

con <- dbConnect(duckdb(), "inst/extdata/pcornet_cdw.duckdb")

# Create tables matching PCORnet CDM schema
# No need for "dbo." schema prefix in DuckDB
# Insert test data

dbDisconnect(con)
```

Then set `config.yml` to use `db_type: "duckdb"` and point `cdw_path`/`mpi_path` to your database files.

The default config already points to `./inst/extdata/pcornet_cdw.duckdb` and `./inst/extdata/mpi.duckdb`.

## Common Pitfalls

1. **Don't use DBI::dbGetQuery() directly**: Use `execute_query()` to handle database differences
2. **Don't parse dates in rowwise context**: Always vectorize date parsing before rowwise operations
3. **Don't return Date objects to timevis**: Convert to character format "YYYY-MM-DD"
4. **Don't forget to filter out NA dates**: Events without dates cause timeline rendering issues
5. **Don't assume MPI database is available**: Wrap `query_source_systems()` in tryCatch
