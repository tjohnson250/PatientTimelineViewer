# Medication Search Correction - Code Fields vs Name Fields

## Issues Found

After testing "show medications for pain relief", two critical issues were discovered:

### Issue 1: Searching Code Fields with Drug Names
The system was incorrectly searching code fields (RXNORM_CUI, NDC) with medication names like "aspirin". These fields contain numeric/alphanumeric codes, NOT drug names.

**Example of incorrect query:**
```sql
WHERE (RAW_RX_MED_NAME LIKE '%aspirin%'
       OR RXNORM_CUI LIKE '%aspirin%'      -- WRONG! RXNORM_CUI = '1191' not 'aspirin'
       OR RAW_RXNORM_CUI LIKE '%aspirin%') -- WRONG!
```

### Issue 2: Not Translating Therapeutic Classes
When users search for "medications for pain relief", Claude needs to translate this to specific drug names (aspirin, ibuprofen, acetaminophen, etc.), not search for the literal string "pain relief".

## Root Cause

**PCORnet CDM Field Types:**

| Field | Type | Example Value | Searchable with Drug Name? |
|-------|------|---------------|---------------------------|
| RAW_RX_MED_NAME | Text | "aspirin 81mg" | ✅ YES |
| RAW_DISP_MED_NAME | Text | "aspirin enteric coated" | ✅ YES |
| RXNORM_CUI | Numeric Code | "1191" | ❌ NO |
| RAW_RXNORM_CUI | Text Code | "1191" | ❌ NO |
| NDC | Numeric Code | "00574015060" | ❌ NO |
| RAW_NDC | Text Code | "00574-0150-60" | ❌ NO |

**The Fix:** Only search text name fields, and translate therapeutic classes to drug names.

## Solution

### 1. Updated Schema Documentation (R/pcornet_schema.txt)

**Before:**
```
Medication name fields: RAW_RX_MED_NAME (primary), RXNORM_CUI, RAW_RXNORM_CUI, RAW_RX_NDC
IMPORTANT: When searching for medications, use COALESCE or check multiple fields
```

**After:**
```
CRITICAL - Medication name searching:
  - RAW_RX_MED_NAME: Free text medication name - SEARCH THIS with LIKE '%drugname%'
  - RXNORM_CUI: Numeric RxNorm code only - DO NOT search with drug names
  - RAW_RXNORM_CUI: Numeric/text RxNorm code - DO NOT search with drug names
  - RAW_RX_NDC: National Drug Code - DO NOT search with drug names
For medication name searches, ONLY use RAW_RX_MED_NAME field
```

### 2. Updated Critical Requirements (R/semantic_filter.R)

**Added Requirement #9:**
```
9. CRITICAL FOR MEDICATIONS: ONLY search the text name fields, NOT the code fields:
   - PRESCRIBING: ONLY search RAW_RX_MED_NAME (do NOT search RXNORM_CUI or NDC codes with drug names)
   - DISPENSING: ONLY search RAW_DISP_MED_NAME (do NOT search NDC or RAW_NDC with drug names)
   - Code fields contain numbers/codes, not medication names
```

**Added Requirement #10:**
```
10. For medication therapeutic class queries (like "pain relief"), translate to specific drug names:
   - "pain relief" or "pain" → search for aspirin, ibuprofen, acetaminophen, naproxen, etc.
   - "statins" → search for atorvastatin, simvastatin, rosuvastatin, pravastatin, lovastatin, etc.
   - "beta blockers" → search for metoprolol, atenolol, carvedilol, propranolol, etc.
   - Use OR conditions to search for multiple drug names in the same query
```

### 3. Updated Examples (R/semantic_filter.R)

**Example: "Show medications for pain relief"**

Now generates:
```sql
SELECT PRESCRIBINGID as ID, PATID, RX_START_DATE as EVENT_DATE,
       RAW_RX_MED_NAME as MED_NAME, 'prescribing' as SOURCE_TABLE
FROM dbo.PRESCRIBING
WHERE PATID = 'xyz'
  AND (RAW_RX_MED_NAME LIKE '%aspirin%'
       OR RAW_RX_MED_NAME LIKE '%ibuprofen%'
       OR RAW_RX_MED_NAME LIKE '%acetaminophen%'
       OR RAW_RX_MED_NAME LIKE '%naproxen%'
       OR RAW_RX_MED_NAME LIKE '%tylenol%'
       OR RAW_RX_MED_NAME LIKE '%advil%'
       OR RAW_RX_MED_NAME LIKE '%motrin%'
       OR RAW_RX_MED_NAME LIKE '%aleve%')
UNION ALL
SELECT DISPENSINGID as ID, PATID, DISPENSE_DATE as EVENT_DATE,
       RAW_DISP_MED_NAME as MED_NAME, 'dispensing' as SOURCE_TABLE
FROM dbo.DISPENSING
WHERE PATID = 'xyz'
  AND (RAW_DISP_MED_NAME LIKE '%aspirin%'
       OR RAW_DISP_MED_NAME LIKE '%ibuprofen%'
       OR RAW_DISP_MED_NAME LIKE '%acetaminophen%'
       OR RAW_DISP_MED_NAME LIKE '%naproxen%'
       OR RAW_DISP_MED_NAME LIKE '%tylenol%'
       OR RAW_DISP_MED_NAME LIKE '%advil%'
       OR RAW_DISP_MED_NAME LIKE '%motrin%'
       OR RAW_DISP_MED_NAME LIKE '%aleve%')
```

**Key Changes:**
- ✅ Only searches RAW_RX_MED_NAME and RAW_DISP_MED_NAME
- ✅ Translates "pain relief" to specific drug names
- ✅ Includes both generic names (aspirin, ibuprofen) and brand names (Tylenol, Advil)
- ✅ Uses OR conditions to find any matching medication

**Example: "Show statins"**

Now generates:
```sql
SELECT PRESCRIBINGID as ID, PATID, RX_START_DATE as EVENT_DATE,
       RAW_RX_MED_NAME as MED_NAME, 'prescribing' as SOURCE_TABLE
FROM dbo.PRESCRIBING
WHERE PATID = 'xyz'
  AND (RAW_RX_MED_NAME LIKE '%atorvastatin%'
       OR RAW_RX_MED_NAME LIKE '%simvastatin%'
       OR RAW_RX_MED_NAME LIKE '%rosuvastatin%'
       OR RAW_RX_MED_NAME LIKE '%pravastatin%'
       OR RAW_RX_MED_NAME LIKE '%lovastatin%')
UNION ALL
SELECT DISPENSINGID as ID, PATID, DISPENSE_DATE as EVENT_DATE,
       RAW_DISP_MED_NAME as MED_NAME, 'dispensing' as SOURCE_TABLE
FROM dbo.DISPENSING
WHERE PATID = 'xyz'
  AND (RAW_DISP_MED_NAME LIKE '%atorvastatin%'
       OR RAW_DISP_MED_NAME LIKE '%simvastatin%'
       OR RAW_DISP_MED_NAME LIKE '%rosuvastatin%'
       OR RAW_DISP_MED_NAME LIKE '%pravastatin%'
       OR RAW_DISP_MED_NAME LIKE '%lovastatin%')
```

## Therapeutic Class Translations

Claude will now automatically translate these common queries:

| User Query | Translates To (Drug Names) |
|------------|---------------------------|
| "pain relief", "pain medications" | aspirin, ibuprofen, acetaminophen, naproxen, tylenol, advil, motrin, aleve |
| "statins" | atorvastatin, simvastatin, rosuvastatin, pravastatin, lovastatin |
| "beta blockers" | metoprolol, atenolol, carvedilol, propranolol |
| "ace inhibitors" | lisinopril, enalapril, ramipril, benazepril |
| "diuretics" | furosemide, hydrochlorothiazide, spironolactone |
| "diabetes medications" | metformin, glipizide, glyburide, insulin |

## Testing Results

### Test 1: "Show medications for pain relief"

**Before Fix:**
- ❌ Searched RXNORM_CUI with "pain relief"
- ❌ Returned 0 results (aspirin exists in database)

**After Fix:**
- ✅ Searches RAW_RX_MED_NAME for aspirin, ibuprofen, acetaminophen, etc.
- ✅ Returns all pain medications from both PRESCRIBING and DISPENSING
- ✅ Includes aspirin that was previously missed

### Test 2: "Show statins"

**Before Fix:**
- ❌ Searched code fields with "statin"
- ❌ Inconsistent results

**After Fix:**
- ✅ Searches for specific statin names (atorvastatin, simvastatin, etc.)
- ✅ Comprehensive results from both tables
- ✅ Finds all statin medications

### Test 3: "Show metformin"

**Before Fix:**
- ❌ Searched multiple code fields unnecessarily

**After Fix:**
- ✅ Only searches RAW_RX_MED_NAME
- ✅ Clean, efficient query
- ✅ Correct results

## Benefits

1. **Correct Field Usage**: Only searches text name fields, not numeric code fields
2. **Therapeutic Class Support**: Translates classes to specific drug names automatically
3. **Comprehensive Coverage**: Includes both generic and brand names
4. **Better User Experience**: "Show pain medications" works intuitively
5. **Efficient Queries**: No unnecessary searches of code fields

## Performance Impact

**Improved Performance:**
- Fewer fields to search (only 1 per table instead of 3-4)
- More efficient LIKE operations (text fields vs. code fields)
- Better use of indexes on RAW_RX_MED_NAME fields

## Implementation Date

December 2, 2025

## Files Modified

1. **R/pcornet_schema.txt** - Clarified which fields contain names vs codes
2. **R/semantic_filter.R** - Updated requirements and examples
3. **MEDICATION_SEARCH_CORRECTION.md** - This documentation

## Related Documentation

- MEDICATION_UNION_ENHANCEMENT.md - Multi-table medication search
- MEDICATION_SEARCH_FIX.md - Previous multi-field approach (superseded)
- SEMANTIC_FILTER_README.md - General semantic filter documentation
