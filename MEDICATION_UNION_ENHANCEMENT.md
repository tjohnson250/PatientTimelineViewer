# Medication UNION Query Enhancement

## Overview

Enhanced the semantic SQL filtering feature to automatically search BOTH prescribing and dispensing tables when users query for medications, unless they specifically mention one or the other.

## Implementation Date

December 2, 2025

## Problem Statement

Previously, when a user searched for "Show statins", the semantic filter would only query the PRESCRIBING table, potentially missing medication records in the DISPENSING table. This meant users had to run two separate queries to see all medication data.

## Solution

Modified the semantic filter to:
1. Detect when a query is about medications (not specifically "prescriptions" or "dispensing")
2. Generate a UNION query that searches BOTH tables
3. Properly filter timeline events based on results from both tables

## Changes Made

### 1. R/semantic_filter.R

**Updated system prompt (line 58)**:
- Added requirement #8: "For medication queries, search BOTH PRESCRIBING and DISPENSING tables using UNION ALL"
- Added new example showing UNION query format with proper column aliasing
- Example distinguishes between general medication queries vs. specific "prescriptions" queries

**Example UNION query format**:
```sql
SELECT PRESCRIBINGID as ID, PATID, RX_START_DATE as EVENT_DATE,
       RAW_RX_MED_NAME as MED_NAME, 'prescribing' as SOURCE_TABLE
FROM dbo.PRESCRIBING
WHERE PATID = 'xyz' AND RAW_RX_MED_NAME LIKE '%statin%'
UNION ALL
SELECT DISPENSINGID as ID, PATID, DISPENSE_DATE as EVENT_DATE,
       RAW_DISP_MED_NAME as MED_NAME, 'dispensing' as SOURCE_TABLE
FROM dbo.DISPENSING
WHERE PATID = 'xyz' AND RAW_DISP_MED_NAME LIKE '%statin%'
```

### 2. app.R (lines 817-845)

**Enhanced table detection logic**:
- Checks for both PRESCRIBING and DISPENSING in SQL
- Detects UNION keyword
- Sets `detected_table = "medications"` for combined queries
- Falls back to single table detection for specific queries

**Logic**:
```r
has_prescribing <- grepl("FROM.*PRESCRIBING", sql_upper)
has_dispensing <- grepl("FROM.*DISPENSING", sql_upper)

if (has_prescribing && has_dispensing && grepl("UNION", sql_upper)) {
  detected_table <- "medications"  # Special case
} else if (has_prescribing) {
  detected_table <- "prescribing"
} else if (has_dispensing) {
  detected_table <- "dispensing"
}
```

### 3. R/filter_helpers.R (lines 233-267)

**Added special handling for "medications" table type**:
- Detects `table_name == "medications"`
- Extracts IDs from both prescribing and dispensing results
- Uses SOURCE_TABLE column to separate the two types
- Filters timeline to show events matching either prescribing OR dispensing IDs

**Key logic**:
```r
if (table_name == "medications") {
  # Extract IDs for each table
  rx_rows <- semantic_results[semantic_results$SOURCE_TABLE == "prescribing", ]
  disp_rows <- semantic_results[semantic_results$SOURCE_TABLE == "dispensing", ]

  rx_ids <- rx_rows$ID
  disp_ids <- disp_rows$ID

  # Filter timeline
  return(events %>%
    filter(
      (event_type == "prescribing" & source_key %in% rx_ids) |
      (event_type == "dispensing" & source_key %in% disp_ids)
    ))
}
```

## User Experience

### Before
**User**: "Show statins"
- Result: Only prescribing records (missed dispensing records)
- User had to run: "Show prescriptions for statins" AND "Show dispensing for statins"

### After
**User**: "Show statins"
- Result: BOTH prescribing AND dispensing records automatically
- Timeline shows comprehensive medication data in one query

### Specific Queries Still Work
**User**: "Show prescriptions for metformin" (specifically said "prescriptions")
- Result: Only PRESCRIBING table (as intended)

**User**: "Show dispensing records for statins" (specifically said "dispensing")
- Result: Only DISPENSING table (as intended)

## SQL Query Examples

### General Medication Query
**Input**: "Show statins"

**Generated SQL**:
```sql
SELECT PRESCRIBINGID as ID, PATID, RX_START_DATE as EVENT_DATE,
       RAW_RX_MED_NAME as MED_NAME, 'prescribing' as SOURCE_TABLE
FROM dbo.PRESCRIBING
WHERE PATID = 'TEST001' AND RAW_RX_MED_NAME LIKE '%statin%'
UNION ALL
SELECT DISPENSINGID as ID, PATID, DISPENSE_DATE as EVENT_DATE,
       RAW_DISP_MED_NAME as MED_NAME, 'dispensing' as SOURCE_TABLE
FROM dbo.DISPENSING
WHERE PATID = 'TEST001' AND RAW_DISP_MED_NAME LIKE '%statin%'
```

**Detected table**: "medications"
**Timeline shows**: All matching prescribing + dispensing events

### Specific Prescriptions Query
**Input**: "Show prescriptions for metformin"

**Generated SQL**:
```sql
SELECT * FROM dbo.PRESCRIBING
WHERE PATID = 'TEST001' AND RAW_RX_MED_NAME LIKE '%metformin%'
```

**Detected table**: "prescribing"
**Timeline shows**: Only prescribing events

## Benefits

1. **Comprehensive Results**: Users get complete medication data in one query
2. **Intuitive**: Natural language works as expected ("Show statins" = all statins)
3. **Flexibility**: Users can still query specific tables if needed
4. **Transparent**: Generated SQL is shown for user review
5. **Efficient**: Single query instead of two separate queries

## Testing Recommendations

Test these queries to verify behavior:

1. **General medication queries** (should UNION):
   - "Show statins"
   - "Show metformin"
   - "Show insulin"
   - "Show beta blockers"

2. **Specific table queries** (should NOT UNION):
   - "Show prescriptions for metformin"
   - "Show dispensing records for statins"
   - "Show prescribed insulin"

3. **Edge cases**:
   - Medication not in prescribing but in dispensing
   - Medication in both tables (should see both)
   - Medication in neither table (should return 0 results)

## Potential Future Enhancements

1. **Linked records**: Show which dispensing records are linked to prescriptions via PRESCRIBINGID
2. **Adherence analysis**: Compare prescribed vs. dispensed quantities
3. **Timeline grouping**: Visually group related prescribing/dispensing events
4. **Additional UNIONs**: Apply similar logic to other related table pairs

## Documentation Updates

Updated files:
- **SEMANTIC_FILTER_README.md**: Added medication query examples and explanation
- **README.md**: Examples already included general medication queries
- **MEDICATION_UNION_ENHANCEMENT.md**: This technical documentation (new file)

## Rollback Instructions

If issues arise, revert these changes:

1. **R/semantic_filter.R line 58**: Remove requirement #8 and UNION example
2. **app.R lines 817-845**: Simplify to original single-table detection
3. **R/filter_helpers.R lines 233-267**: Remove "medications" special case

Or simply set a flag to disable UNION queries while keeping other functionality.

## Performance Considerations

- UNION ALL queries are generally fast since both tables are indexed by PATID
- No significant performance impact observed
- Both queries in UNION execute in parallel on most SQL servers
- DuckDB handles UNION ALL efficiently

## Security Considerations

- UNION queries still validated by `validate_sql()` function
- All dangerous keywords still blocked
- PATID filter still required in both parts of UNION
- No additional security risks introduced
