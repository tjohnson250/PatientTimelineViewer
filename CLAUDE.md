# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains two applications for visualizing temporal patient data from a PCORnet CDM data warehouse:

1. **R/Shiny Web App** (root directory) — Interactive 2D timeline using the timevis library. Supports MS SQL Server (production) and DuckDB (development/testing) backends.
2. **Vision Pro App** (`VisionProApp/`) — Companion visionOS app that renders patient timelines as an immersive 3D cylindrical visualization using RealityKit. Currently uses mock data; designed for future API integration.

Both apps share the same event type color scheme and PCORnet CDM data model.

## Running the Applications

### R/Shiny App

```r
# Install dependencies
install.packages(c("shiny", "shinyjs", "timevis", "dplyr", "lubridate",
                   "DBI", "config", "htmltools", "stringr"))
install.packages("duckdb")   # For DuckDB backend
install.packages("odbc")     # For MS SQL Server backend
install.packages("httr2")    # For AI semantic filtering (optional)

# Run with default config profile (DuckDB)
shiny::runApp()

# Run with specific profile
Sys.setenv(R_CONFIG_ACTIVE = "production")
shiny::runApp()
```

Sample DuckDB databases are included in `data/` for local development.

### Vision Pro App

```bash
open VisionProApp/PatientTimeline3D/PatientTimeline3D.xcodeproj
# Select visionOS Simulator or Vision Pro device → ⌘R
```

Requires Xcode 15.0+ with visionOS 1.0+ SDK.

## Configuration System

`config.yml` uses the `config` R package with profile-based configuration:

- `db_type`: `"mssql"` or `"duckdb"`
- Profiles: `default` (DuckDB), `local`, `production` (MSSQL)
- Activate profile: `Sys.setenv(R_CONFIG_ACTIVE = "production")`

The app establishes database connections on startup via `get_db_connections()` in `R/db_queries.R` and maintains them throughout the session.

### Semantic Filter API Key

The optional AI-powered filter requires `ANTHROPIC_API_KEY` set in `~/.Renviron` or environment. Uses `claude-sonnet-4-20250514` by default (configurable in `R/semantic_filter.R`).

## R/Shiny Architecture

### Data Flow

```
Database (MS SQL Server or DuckDB)
    ↓
R/db_queries.R: load_patient_data() → list of raw data frames
    ↓
R/data_transforms.R: transform_all_to_timevis() → timevis event format
    ↓
R/filter_helpers.R: apply_all_filters() → filtered events
    ↓
R/aggregation.R: aggregate_events() → daily/weekly aggregated events
    ↓
app.R: timevis renders the timeline
    ↓
www/cluster-colors.js: dynamic cluster coloring
www/timeline-markers.js: birth/death marker rendering
```

### R Modules

| File | Purpose |
|------|---------|
| `app.R` | Main Shiny UI + server (~1,086 lines) |
| `R/db_queries.R` | Database abstraction layer with per-table query functions |
| `R/data_transforms.R` | Converts raw DB results to timevis format; contains `safe_parse_date()` |
| `R/aggregation.R` | Event aggregation (individual/daily/weekly) |
| `R/filter_helpers.R` | Sequential filter composition in `apply_all_filters()` |
| `R/semantic_filter.R` | AI-powered natural language → SQL generation via Claude API |
| `R/pcornet_schema.txt` | PCORnet CDM schema context fed to Claude for SQL generation |

### Client-Side Files (www/)

| File | Purpose |
|------|---------|
| `www/custom.css` | All styling including CSS variables for 9 event type colors |
| `www/cluster-colors.js` | Dynamic coloring of timevis clusters based on aggregated event composition |
| `www/timeline-markers.js` | Renders birth and death date reference lines on the timeline |

### Database Abstraction

`R/db_queries.R` provides database-agnostic queries:

- **`execute_query()`**: Handles parameter binding differences (ODBC uses `?`, DuckDB uses `$1, $2`)
- **`qualify_table()`**: Adds `dbo.` schema prefix for MS SQL Server, no prefix for DuckDB

When adding new queries:
1. Use `execute_query()` instead of `DBI::dbGetQuery()` directly
2. Use `?` placeholders for parameters (auto-converted for DuckDB)
3. Reference tables without schema prefix (auto-qualified)

### Date Handling Strategy

**Critical**: The codebase has specific date handling to work with both database backends:

- Raw dates arrive as Date, POSIXct, or character depending on backend
- **`safe_parse_date()`** in `data_transforms.R` handles all conversions
- Transform functions parse dates VECTORIZED FIRST (before rowwise operations)
- Final timeline format uses character dates in `"YYYY-MM-DD"` format (required by timevis)

When modifying transforms:
1. Parse dates vectorized before any rowwise operations
2. Use `safe_parse_date()` for all date conversions
3. Format final dates as character strings for timevis

### Event Transform Pattern

Each PCORnet table has a `transform_[table_type]()` function that:
1. Handles empty data
2. Parses dates VECTORIZED first
3. Filters out records with missing dates
4. Uses `rowwise()` only for tooltip generation
5. Returns standard timevis columns: `id`, `content`, `start`, `end`, `group`, `type`, `className`, `title` (HTML tooltip), `source_table`, `source_key`, `event_type`

### Event Aggregation

- **Individual**: No aggregation
- **Daily**: Events of same type on same date collapsed with count
- **Weekly**: Events grouped by ISO week

Only point events are aggregated. Range events (encounters with discharge dates) and death/birth markers are never aggregated.

### Filtering Architecture

Filters are composed sequentially in `apply_all_filters()`:

1. Semantic filter results (AI-generated SQL, applied first)
2. Event type selection (checkboxes)
3. Date range
4. Encounter type
5. Diagnosis code pattern (SQL LIKE syntax)
6. Procedure code pattern (SQL LIKE syntax)
7. Lab name (partial text match)
8. Medication name (partial text match, searches both PRESCRIBING and DISPENSING)

Each filter function returns the full dataset if filter is empty/null. Type-specific filters keep non-matching event types unchanged.

### Semantic Filter (R/semantic_filter.R)

The AI filter converts natural language queries (e.g., "Show statins", "Show encounters with A1c > 9") into SQL:
- `generate_filter_sql()` calls Claude API with PCORnet schema context from `R/pcornet_schema.txt`
- `validate_semantic_sql()` enforces SELECT-only queries scoped to current PATID
- Medication queries without a specific table target generate UNION ALL across PRESCRIBING and DISPENSING
- `filter_by_semantic_results()` in `R/filter_helpers.R` integrates results with standard filtering

### Reactive Value Structure

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

From the CDW database: DEMOGRAPHIC, ENCOUNTER, DIAGNOSIS, PROCEDURES, LAB_RESULT_CM, PRESCRIBING, DISPENSING, VITAL, CONDITION, DEATH, DEATH_CAUSE

From the MasterPatientIndex database: Mpi (source system mappings), EnterpriseRecords_Ext (CDM PATID to UID mapping)

## Event Type Color Scheme

Colors are defined in `www/custom.css` and must remain consistent across both apps:

| Event Type | Hex | Color |
|------------|---------|-------|
| Encounters | #3498db | Blue |
| Diagnoses | #e74c3c | Coral |
| Procedures | #9b59b6 | Purple |
| Labs | #27ae60 | Green |
| Prescribing | #e67e22 | Orange |
| Dispensing | #f39c12 | Amber |
| Vitals | #1abc9c | Teal |
| Conditions | #e91e63 | Pink |
| Death | #2c3e50 | Dark Gray |

The Vision Pro app mirrors these in `VisionProApp/PatientTimeline3D/Models/ColorScheme.swift`.

## Vision Pro App Architecture

The visionOS app in `VisionProApp/PatientTimeline3D/` uses SwiftUI + RealityKit:

- **ContentView.swift** — 2D window UI for controls and filters
- **ImmersiveView.swift** — 3D immersive timeline rendering
- **Models/** — `TimelineModels.swift` (data structures), `ColorScheme.swift` (color mappings), `MockData.swift` (sample data)
- **Views/** — `FilterPanelView.swift`, `EventDetailView.swift`, `Timeline3DView.swift`
- **Services/PatientDataService.swift** — Data provider (mock; extend for API integration)
- **Entities/TimelineEntity.swift** — RealityKit 3D entity management

### 3D Layout Algorithm

Events use cylindrical coordinates:
- **Angle (θ)**: Date maps to 0-2π (front = oldest, clockwise progression)
- **Radius (r)**: Base radius (1.5-4.0m adjustable) + per-event-type offset
- **Height (y)**: Stacked by event type group with jitter to prevent overlaps

## Special Behaviors

- **Related Events**: Clicking an encounter and selecting "Show Related Events" zooms to admit/discharge window ± 1 day using timevis `setWindow()`
- **Death markers**: Span all groups (group = NA), always visible regardless of filters, events after death remain visible for data quality review
- **Abnormal labs**: ABN_IND values (AB, AH, AL, CH, CL, CR) get className `event-lab-abnormal`

## Adding New Event Types

1. `R/db_queries.R`: Add `query_[tablename]()` function
2. `R/db_queries.R`: Add table to `load_patient_data()` list
3. `R/data_transforms.R`: Create `transform_[tablename]()` following the established pattern
4. `R/data_transforms.R`: Add to `transform_all_to_timevis()` bind_rows
5. `R/filter_helpers.R`: Add to `get_event_type_counts()`
6. `app.R`: Add checkbox to UI in `output$event_type_checkboxes`
7. `app.R`: Add to `get_selected_event_types()` reactive
8. `www/custom.css`: Define color class
9. `app.R`: Add event detail rendering in `output$event_details`
10. `VisionProApp/.../ColorScheme.swift`: Add color mapping if updating Vision Pro app

## Common Pitfalls

1. **Don't use `DBI::dbGetQuery()` directly** — Use `execute_query()` to handle database differences
2. **Don't parse dates in rowwise context** — Always vectorize date parsing before rowwise operations
3. **Don't return Date objects to timevis** — Convert to character format `"YYYY-MM-DD"`
4. **Don't forget to filter out NA dates** — Events without dates cause timeline rendering issues
5. **Don't assume MPI database is available** — Wrap `query_source_systems()` in tryCatch
6. **Don't change event type colors in only one place** — CSS (`www/custom.css`) and Swift (`ColorScheme.swift`) must stay in sync
