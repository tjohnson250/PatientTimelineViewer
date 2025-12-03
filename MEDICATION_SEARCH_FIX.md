# Medication Search Multi-Field Fix

## Issue

When searching for medications like "show medications for pain relief" (which would search for aspirin), the semantic filter was only checking a single field (`RAW_RX_MED_NAME` in PRESCRIBING and `RAW_DISP_MED_NAME` in DISPENSING). This resulted in:

- **0 results** even when medications existed in the database
- Medications stored in alternate fields (RXNORM_CUI, NDC, etc.) were not found
- Incomplete search results

## Root Cause

The PCORnet CDM has multiple fields where medication information can be stored:

**PRESCRIBING table**:
- `RAW_RX_MED_NAME` - Free text medication name (most common)
- `RXNORM_CUI` - Standardized RxNorm code
- `RAW_RXNORM_CUI` - Raw RxNorm code
- `RAW_RX_NDC` - National Drug Code (raw)

**DISPENSING table**:
- `RAW_DISP_MED_NAME` - Free text medication name (most common)
- `NDC` - National Drug Code (standardized)
- `RAW_NDC` - National Drug Code (raw)

Previous queries only searched the primary free-text field, missing records where medication names were in other columns.

## Solution

Updated the semantic filter to search **all relevant medication name fields** in both tables using OR conditions.

### Changes Made

#### 1. R/pcornet_schema.txt (lines 29-45)

Added detailed field documentation:

```
PRESCRIBING
  Medication name fields: RAW_RX_MED_NAME (primary), RXNORM_CUI, RAW_RXNORM_CUI, RAW_RX_NDC
  IMPORTANT: When searching for medications, use COALESCE or check multiple fields:
    - RAW_RX_MED_NAME (most common, contains free text name)
    - RXNORM_CUI (standardized RxNorm code)
    - RAW_RXNORM_CUI (raw RxNorm code)

DISPENSING
  Medication name fields: RAW_DISP_MED_NAME (primary), NDC, RAW_NDC
  IMPORTANT: When searching for medications, use COALESCE or check multiple fields:
    - RAW_DISP_MED_NAME (most common, contains free text name)
    - NDC (National Drug Code)
    - RAW_NDC (raw NDC code)
```

#### 2. R/semantic_filter.R (lines 59-62)

Added critical requirement #9:

```
9. CRITICAL FOR MEDICATIONS: Search ALL medication name fields in both tables using OR conditions:
   - PRESCRIBING: Check RAW_RX_MED_NAME, RXNORM_CUI, and RAW_RXNORM_CUI
   - DISPENSING: Check RAW_DISP_MED_NAME, NDC, and RAW_NDC
   - Use OR to search all fields for comprehensive results
```

#### 3. R/semantic_filter.R (lines 84-108)

Updated medication query example:

**Before**:
```sql
SELECT PRESCRIBINGID as ID, ...
FROM dbo.PRESCRIBING
WHERE PATID = 'xyz'
  AND RAW_RX_MED_NAME LIKE '%statin%'  -- Only one field!
UNION ALL
SELECT DISPENSINGID as ID, ...
FROM dbo.DISPENSING
WHERE PATID = 'xyz'
  AND RAW_DISP_MED_NAME LIKE '%statin%'  -- Only one field!
```

**After**:
```sql
SELECT PRESCRIBINGID as ID, PATID, RX_START_DATE as EVENT_DATE,
       COALESCE(RAW_RX_MED_NAME, RXNORM_CUI, RAW_RXNORM_CUI) as MED_NAME,
       'prescribing' as SOURCE_TABLE
FROM dbo.PRESCRIBING
WHERE PATID = 'xyz'
  AND (RAW_RX_MED_NAME LIKE '%statin%'      -- Check all fields!
       OR RXNORM_CUI LIKE '%statin%'
       OR RAW_RXNORM_CUI LIKE '%statin%')
UNION ALL
SELECT DISPENSINGID as ID, PATID, DISPENSE_DATE as EVENT_DATE,
       COALESCE(RAW_DISP_MED_NAME, NDC, RAW_NDC) as MED_NAME,
       'dispensing' as SOURCE_TABLE
FROM dbo.DISPENSING
WHERE PATID = 'xyz'
  AND (RAW_DISP_MED_NAME LIKE '%statin%'    -- Check all fields!
       OR NDC LIKE '%statin%'
       OR RAW_NDC LIKE '%statin%')
```

## Testing

Test these queries to verify the fix:

### Should Now Return Results

**Query**: "Show medications for pain relief"
- **Expected**: Finds aspirin in any field (RAW_RX_MED_NAME, RXNORM_CUI, etc.)
- **Before**: 0 results (only checked RAW_RX_MED_NAME)
- **After**: All aspirin records from both tables

**Query**: "Show statins"
- **Expected**: Finds atorvastatin, simvastatin, etc. in any medication field
- **Before**: Might miss records stored only in NDC or RXNORM_CUI fields
- **After**: Comprehensive results from all fields

**Query**: "Show metformin"
- **Expected**: All metformin records regardless of storage field
- **After**: Complete medication list

### Edge Cases to Test

1. **Medication only in RXNORM_CUI**: Should be found
2. **Medication only in NDC**: Should be found
3. **Medication in multiple fields**: Should appear once (no duplicates)
4. **Medication in neither table**: Should return 0 results (expected)
5. **Medication in prescribing but not dispensing**: Should show prescribing records
6. **Medication in dispensing but not prescribing**: Should show dispensing records

## SQL Query Examples

### Generated for "Show aspirin"

```sql
SELECT PRESCRIBINGID as ID, PATID, RX_START_DATE as EVENT_DATE,
       COALESCE(RAW_RX_MED_NAME, RXNORM_CUI, RAW_RXNORM_CUI) as MED_NAME,
       'prescribing' as SOURCE_TABLE
FROM dbo.PRESCRIBING
WHERE PATID = 'TEST001'
  AND (RAW_RX_MED_NAME LIKE '%aspirin%'
       OR RXNORM_CUI LIKE '%aspirin%'
       OR RAW_RXNORM_CUI LIKE '%aspirin%')
UNION ALL
SELECT DISPENSINGID as ID, PATID, DISPENSE_DATE as EVENT_DATE,
       COALESCE(RAW_DISP_MED_NAME, NDC, RAW_NDC) as MED_NAME,
       'dispensing' as SOURCE_TABLE
FROM dbo.DISPENSING
WHERE PATID = 'TEST001'
  AND (RAW_DISP_MED_NAME LIKE '%aspirin%'
       OR NDC LIKE '%aspirin%'
       OR RAW_NDC LIKE '%aspirin%')
```

### Generated for "Show prescriptions for warfarin"

```sql
SELECT * FROM dbo.PRESCRIBING
WHERE PATID = 'TEST001'
  AND (RAW_RX_MED_NAME LIKE '%warfarin%'
       OR RXNORM_CUI LIKE '%warfarin%'
       OR RAW_RXNORM_CUI LIKE '%warfarin%')
```

## Benefits

1. **Comprehensive Results**: Finds medications regardless of which field contains the name
2. **Better User Experience**: Users get expected results without understanding database schema
3. **Handles Real-World Data**: Many EHR systems store medication data differently
4. **Backward Compatible**: Still works with queries that only have RAW_*_MED_NAME populated
5. **Follows PCORnet Standards**: Properly utilizes all standardized medication fields

## Performance Considerations

- **Index Impact**: If RAW_RX_MED_NAME and RAW_DISP_MED_NAME are indexed, performance remains good
- **OR Conditions**: Multiple OR conditions may prevent index use in some databases
- **Recommendation**: Consider adding indexes on RXNORM_CUI and NDC if medication searches are frequent
- **Query Optimization**: Database optimizer will skip NULL checks automatically

## Alternative Approaches Considered

### 1. COALESCE Only (Not Chosen)
```sql
WHERE COALESCE(RAW_RX_MED_NAME, RXNORM_CUI, RAW_RXNORM_CUI) LIKE '%aspirin%'
```
**Pros**: Simpler query
**Cons**: Only checks first non-NULL field; misses cases where medication appears in multiple fields

### 2. Separate Queries with UNION (Not Chosen)
```sql
SELECT ... WHERE RAW_RX_MED_NAME LIKE '%aspirin%'
UNION
SELECT ... WHERE RXNORM_CUI LIKE '%aspirin%'
UNION
SELECT ... WHERE RAW_RXNORM_CUI LIKE '%aspirin%'
```
**Pros**: Explicit field checking
**Cons**: Much more complex; potential duplicates; worse performance

### 3. OR Conditions (Chosen)
```sql
WHERE (RAW_RX_MED_NAME LIKE '%aspirin%'
       OR RXNORM_CUI LIKE '%aspirin%'
       OR RAW_RXNORM_CUI LIKE '%aspirin%')
```
**Pros**: Comprehensive; clear intent; good performance with indexes
**Cons**: Slightly more complex WHERE clause

## Future Enhancements

1. **Smart Field Prioritization**: Search most commonly populated fields first
2. **Field-Specific Search**: Allow users to specify which field to search
3. **NDC Lookup**: Integrate NDC code lookup for exact matching
4. **RxNorm Integration**: Use RxNorm API for medication name standardization
5. **Fuzzy Matching**: Handle misspellings and variations

## Implementation Date

December 2, 2025

## Related Documentation

- MEDICATION_UNION_ENHANCEMENT.md - Multi-table medication search
- SEMANTIC_FILTER_README.md - General semantic filter documentation
- CLAUDE.md - Project architecture
