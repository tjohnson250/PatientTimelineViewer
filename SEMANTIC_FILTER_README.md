# Semantic SQL Filtering Feature

## Overview

The Patient Timeline Viewer now includes an AI-powered semantic filtering feature that allows users to filter patient data using natural language queries. The feature uses the Anthropic Claude API to convert plain English questions into SQL queries that are validated and executed against the PCORnet CDM database.

## Features

- **Natural Language Queries**: Ask questions in plain English instead of writing SQL
- **SQL Generation**: Automatically generates safe, parameterized SQL queries
- **Security Validation**: Validates all generated SQL to prevent dangerous operations
- **Transparency**: Shows the generated SQL for user review and trust
- **Seamless Integration**: Works alongside existing timeline filters

## Setup

### 1. Set API Key

Before using the semantic filter, you need to set your Anthropic API key as an environment variable:

**Option A: Using .Renviron file (recommended)**

Create or edit `~/.Renviron` and add:

```
ANTHROPIC_API_KEY=your-api-key-here
```

Then restart R/RStudio.

**Option B: Set in current session**

```r
Sys.setenv(ANTHROPIC_API_KEY = "your-api-key-here")
```

**Option C: Set in system environment**

On Mac/Linux:
```bash
export ANTHROPIC_API_KEY=your-api-key-here
```

On Windows:
```powershell
$env:ANTHROPIC_API_KEY="your-api-key-here"
```

### 2. Install Required Packages

The semantic filter requires the `httr2` package:

```r
install.packages("httr2")
```

## Usage

1. **Load a patient** using the Patient ID input
2. **Enter a natural language query** in the "AI-Powered Filter" text box
3. **Click "Apply"** to generate and execute the SQL
4. **View results** on the timeline (filtered events)
5. **Expand "View Generated SQL"** to see the actual SQL query that was generated
6. **Click "Clear"** to remove the semantic filter and return to unfiltered data

## Example Queries

Here are some example queries you can try:

### Labs
- "Show encounters with A1c > 9"
- "Show labs where result was abnormal"
- "Show glucose tests with results over 200"
- "Show lab results from 2023"

### Encounters
- "Show only inpatient encounters"
- "Show emergency department visits"
- "Show encounters from 2023"
- "Show encounters with length of stay greater than 7 days"

### Diagnoses
- "Show diagnoses containing diabetes"
- "Show diagnoses with ICD-10 codes starting with E11"
- "Show principal diagnoses only"
- "Show diagnoses from the last year"

### Medications (searches both prescribing AND dispensing)
- "Show statins" - searches both PRESCRIBING and DISPENSING tables
- "Show metformin" - searches both tables
- "Show insulin" - searches both tables
- "Show prescriptions for metformin" - searches PRESCRIBING table only (user specified "prescriptions")
- "Show dispensing records for statins" - searches DISPENSING table only (user specified "dispensing")

**Note**: When you mention a medication without specifying "prescriptions" or "dispensing", the semantic filter automatically searches BOTH tables using a UNION query to give you comprehensive medication results.

### Procedures
- "Show procedures with CPT codes starting with 99"
- "Show all surgical procedures"

## How It Works

### Architecture

```
User Query → Claude API → SQL Generation → Validation → Execution → Timeline Filter
```

1. **User enters natural language query** (e.g., "Show encounters with A1c > 9")

2. **Query sent to Claude API** with:
   - System prompt containing PCORnet CDM schema documentation
   - Database type (MS SQL Server or DuckDB)
   - Current patient ID
   - Instructions to generate safe SQL

3. **Claude generates SQL query** based on:
   - Schema understanding
   - Natural language interpretation
   - Database-specific syntax (schema prefixes, etc.)

4. **SQL is validated** for:
   - Only SELECT statements allowed
   - Must include current PATID filter
   - No dangerous operations (INSERT, UPDATE, DELETE, DROP, etc.)
   - Proper schema qualification

5. **SQL is executed** against the CDW database

6. **Results are filtered** and displayed on the timeline

### Security Features

The semantic filter includes multiple security layers:

- **Keyword Blocking**: Blocks INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER, CREATE, EXEC, GRANT, REVOKE, etc.
- **SELECT-Only**: Only SELECT queries are allowed
- **Patient Scoping**: All queries must filter by current PATID
- **No Injection**: Uses parameterized queries where possible
- **Transparent**: Shows generated SQL for user review

### Files Added

- **R/semantic_filter.R**: Core functions for SQL generation and validation
- **R/pcornet_schema.txt**: PCORnet CDM schema documentation for Claude
- **SEMANTIC_FILTER_README.md**: This documentation file

### Files Modified

- **app.R**: Added UI elements and server logic for semantic filtering
- **R/filter_helpers.R**: Added `filter_by_semantic_results()` function

## Troubleshooting

### "ANTHROPIC_API_KEY environment variable not set"

**Solution**: Set the API key as described in the Setup section above. Restart R/RStudio after setting it in .Renviron.

### "Claude API error: ..."

**Possible causes**:
- Invalid API key
- Network connectivity issues
- API rate limits exceeded
- API service outage

**Solution**: Check your API key, internet connection, and Anthropic API status.

### "Security violation: SQL contains prohibited keyword"

**Cause**: The generated SQL contained a dangerous operation.

**Solution**: Try rephrasing your query. This is a safety feature to prevent data modification.

### "SQL must filter by current PATID"

**Cause**: The generated SQL didn't include the patient filter.

**Solution**: This should rarely happen. Try rephrasing your query or report as a bug.

### Generated SQL returns no results

**Possible causes**:
- Patient doesn't have data matching the criteria
- Query interpretation was different than expected
- Table/column names were incorrectly identified

**Solution**:
1. View the generated SQL to understand what was queried
2. Rephrase your question more specifically
3. Use the advanced filters for precise code/name matching

## Integration with Existing Filters

The semantic filter works alongside the existing filter system:

- **Semantic filter is applied FIRST**: It narrows down records from a specific table
- **Event type checkboxes**: Further filter which event types to display
- **Date range**: Applied after semantic filter
- **Advanced filters**: Also stack on top of semantic filter

**Example workflow**:
1. Apply semantic filter: "Show encounters with A1c > 9" (gets lab records)
2. Use event type checkboxes to also show diagnoses
3. Use date range to focus on recent events
4. Use advanced diagnosis filter to show only diabetes diagnoses

This allows powerful, layered filtering combining AI-generated queries with manual refinement.

## API Usage and Costs

Each semantic filter query makes one API call to Claude:
- **Model**: claude-sonnet-4-20250514
- **Max tokens**: 1024 (typically uses 100-300 for SQL generation)
- **Pricing**: Check current Anthropic pricing at https://www.anthropic.com/pricing

**Cost estimates** (as of 2025, check current pricing):
- Input: ~1000 tokens (schema + prompt)
- Output: ~200 tokens (SQL query)
- Cost per query: Typically < $0.01 USD

Consider caching frequently used queries or limiting usage for cost control.

## Limitations

1. **Single table queries**: Each query targets one PCORnet table at a time (cannot join multiple tables)
2. **Basic aggregations**: Complex aggregations may not be supported
3. **Interpretation accuracy**: AI may misinterpret ambiguous queries
4. **Schema knowledge**: Limited to PCORnet CDM schema as documented in pcornet_schema.txt

## Future Enhancements

Potential improvements:
- Query history/favorites
- Multi-table joins
- Query refinement suggestions
- Cached common queries
- User feedback on query accuracy
- Support for aggregate functions (COUNT, AVG, etc.)

## Support

For issues or questions:
1. Check the generated SQL to understand what was executed
2. Try rephrasing your query
3. Use advanced filters as an alternative
4. Report persistent issues to your system administrator
