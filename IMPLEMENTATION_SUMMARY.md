# Semantic SQL Filtering - Implementation Summary

## Overview

Successfully implemented an AI-powered semantic SQL filtering feature for the Patient Timeline Viewer. Users can now filter patient data using natural language queries like "Show encounters with A1c > 9" instead of using manual filters.

## Implementation Date

December 2, 2025

## Files Created

### 1. R/pcornet_schema.txt
- **Purpose**: PCORnet CDM schema documentation for Claude API
- **Content**: Table structures, column descriptions, common values, and usage notes for all PCORnet tables
- **Usage**: Provided as context to Claude when generating SQL queries

### 2. R/semantic_filter.R
- **Purpose**: Core logic for semantic filtering
- **Functions**:
  - `load_schema_context()`: Reads schema documentation from file
  - `generate_filter_sql()`: Calls Claude API to convert natural language to SQL
  - `validate_sql()`: Security validation of generated SQL
  - `apply_semantic_filter()`: Complete workflow (generate → validate → execute)

### 3. SEMANTIC_FILTER_README.md
- **Purpose**: User documentation for the semantic filter feature
- **Content**: Setup instructions, usage examples, troubleshooting, architecture overview

### 4. IMPLEMENTATION_SUMMARY.md
- **Purpose**: Technical summary of implementation (this file)

## Files Modified

### 1. app.R

**Added imports/sources:**
- Source `R/semantic_filter.R`
- API key check at startup (warns if ANTHROPIC_API_KEY not set)

**UI Changes:**
- New "AI-Powered Filter" panel above existing filters
- Text input for natural language queries
- "Apply" and "Clear" buttons
- Status/error message display area
- Collapsible "View Generated SQL" panel with syntax highlighting

**Server Changes:**
- Added reactive values:
  - `semantic_filter_active`: Boolean flag
  - `semantic_filter_sql`: Generated SQL query
  - `semantic_filter_table`: Which table was queried
  - `semantic_filter_results`: Query results data frame

- Added event observers:
  - `observeEvent(input$apply_semantic_filter)`: Generates SQL, validates, executes, displays results
  - `observeEvent(input$clear_semantic_filter)`: Clears semantic filter state

- Modified `filtered_events` reactive:
  - Now passes semantic filter results to `apply_all_filters()`

**Location in app.R:**
- UI: Lines 134-197 (semantic filter panel)
- Server reactive values: Lines 411-414
- Server logic: Lines 752-880

### 2. R/filter_helpers.R

**Added function:**
- `filter_by_semantic_results()` (lines 223-265)
  - Maps semantic SQL results to timeline events
  - Filters events by matching source IDs
  - Preserves non-matching event types

**Modified function:**
- `apply_all_filters()` (lines 267-311)
  - Now accepts `semantic_results` and `semantic_table` parameters
  - Applies semantic filter first, before other filters

## Architecture

```
┌──────────────┐
│ User enters  │
│ NL query     │
└──────┬───────┘
       │
       v
┌──────────────────────────────────────────┐
│ app.R: observeEvent(apply_semantic)      │
│ - Collects query and patient ID          │
│ - Calls apply_semantic_filter()          │
└──────┬───────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────┐
│ semantic_filter.R: apply_semantic_filter │
│ 1. generate_filter_sql()                 │
│    - Builds system prompt with schema    │
│    - Calls Claude API                    │
│    - Returns SQL string                  │
│ 2. validate_sql()                        │
│    - Checks for dangerous keywords       │
│    - Ensures PATID filter present        │
│    - Validates SELECT-only               │
│ 3. DBI::dbGetQuery()                     │
│    - Executes validated SQL              │
│    - Returns result data frame           │
└──────┬───────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────┐
│ app.R: Store results in reactive values  │
│ - rv$semantic_filter_results             │
│ - rv$semantic_filter_table               │
│ - rv$semantic_filter_sql                 │
└──────┬───────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────┐
│ filtered_events() reactive triggered     │
│ - Collects all filter parameters         │
│ - Includes semantic results & table      │
└──────┬───────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────┐
│ filter_helpers.R: apply_all_filters      │
│ 1. filter_by_semantic_results()          │
│    - Maps table to event type            │
│    - Filters by matching IDs             │
│ 2. Other filters applied sequentially    │
└──────┬───────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────┐
│ Timeline updated with filtered events    │
└──────────────────────────────────────────┘
```

## Security Features

1. **Keyword Blocking**: Prevents INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER, CREATE, EXEC, GRANT, REVOKE
2. **SELECT-Only Validation**: Only SELECT queries allowed
3. **Patient Scoping**: All queries must include `WHERE PATID = '<current_patient>'`
4. **SQL Transparency**: Generated SQL displayed to user for review
5. **Error Handling**: Try-catch blocks prevent crashes from API or SQL errors

## Database Compatibility

The implementation supports both database backends:

- **MS SQL Server**: Uses `dbo.` schema prefix, ODBC `?` parameter placeholders
- **DuckDB**: No schema prefix, `$1` parameter placeholders

The `generate_filter_sql()` function automatically adjusts based on `db_type` parameter.

## Dependencies

### New R Packages
- `httr2`: For Anthropic API HTTP requests (must be installed)

### Existing Packages Used
- `DBI`: Database queries
- `dplyr`: Data manipulation
- `shiny`, `shinyjs`: UI and reactivity

### External Services
- Anthropic Claude API (requires ANTHROPIC_API_KEY)

## Configuration

### Environment Variables
- `ANTHROPIC_API_KEY`: Required for semantic filtering to work
  - Can be set in `~/.Renviron`
  - Or as system environment variable
  - Or in R session with `Sys.setenv()`

### API Settings
- **Model**: claude-sonnet-4-20250514
- **Max tokens**: 1024
- **API version**: 2023-06-01
- **Endpoint**: https://api.anthropic.com/v1/messages

## Testing Recommendations

### Test Queries

1. **Labs**:
   - "Show encounters with A1c > 9"
   - "Show labs where result was abnormal"
   - "Show glucose tests"

2. **Encounters**:
   - "Show only inpatient encounters"
   - "Show emergency department visits"
   - "Show encounters from 2023"

3. **Diagnoses**:
   - "Show diagnoses containing diabetes"
   - "Show diagnoses with ICD-10 codes starting with E11"

4. **Prescriptions**:
   - "Show prescriptions for metformin"
   - "Show insulin prescriptions"

5. **Procedures**:
   - "Show procedures with CPT codes starting with 99"

### Security Tests

1. Try injection attempts (should be blocked):
   - "Show encounters; DROP TABLE ENCOUNTER;"
   - "Show encounters' OR '1'='1"
   - "Show all encounters UNION SELECT * FROM DEMOGRAPHIC"

2. Try unauthorized operations (should be blocked):
   - "DELETE FROM ENCOUNTER WHERE PATID = 'xyz'"
   - "UPDATE DIAGNOSIS SET DX = 'test'"
   - "INSERT INTO ENCOUNTER VALUES (...)"

### Error Handling Tests

1. Invalid API key → Should show error message
2. Network timeout → Should show error message
3. Ambiguous query → May generate SQL that returns no results
4. Query for non-existent table → Should fail gracefully

## Known Limitations

1. **Single table queries only**: Cannot join multiple PCORnet tables in one query
2. **Basic filtering**: Complex aggregations (GROUP BY, COUNT, AVG) may not work reliably
3. **AI interpretation**: May misinterpret ambiguous natural language
4. **Schema knowledge**: Limited to what's documented in pcornet_schema.txt
5. **No query history**: Users must re-type queries (could be added as enhancement)

## Future Enhancements

Potential improvements for future iterations:

1. **Query History**: Save and recall previous queries
2. **Query Templates**: Pre-built common queries
3. **Multi-table Joins**: Support queries across related tables
4. **Aggregations**: Support COUNT, AVG, SUM, GROUP BY
5. **Query Refinement**: "Refine last query" feature
6. **Favorites**: Save favorite queries
7. **Query Sharing**: Export/import query definitions
8. **Caching**: Cache common queries to reduce API costs
9. **User Feedback**: Allow users to rate query accuracy
10. **Advanced Validation**: Check for SQL injection patterns

## Cost Estimates

Per query API cost (based on 2025 pricing, verify current rates):
- Input: ~1000 tokens (schema + prompt)
- Output: ~200 tokens (SQL query)
- **Estimated cost**: $0.003 - $0.01 USD per query

For a typical user session (10-20 queries): ~$0.10 USD

## Rollback Instructions

If the feature needs to be disabled:

1. Comment out the semantic filter UI panel in app.R (lines 134-197)
2. Remove `source("R/semantic_filter.R")` from app.R (line 19)
3. Remove semantic filter parameters from `filtered_events` reactive
4. Remove `filter_by_semantic_results()` call from `apply_all_filters()`

Or simply don't set the ANTHROPIC_API_KEY environment variable (feature will be non-functional but won't break the app).

## Migration Notes

No database schema changes required. Feature is purely application-level.

No data migration needed.

Backward compatible - app works with or without API key set.

## Version Information

- Implementation version: 1.0
- Claude Code: Used for implementation
- Shiny application: Patient Timeline Viewer
- Database: PCORnet CDM (MS SQL Server or DuckDB)

## Contact

For questions or issues with this implementation, refer to:
- SEMANTIC_FILTER_README.md (user documentation)
- Code comments in R/semantic_filter.R
- CLAUDE.md (project architecture documentation)
