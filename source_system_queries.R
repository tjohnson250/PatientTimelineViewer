# Source System Investigation Queries
# Run these against your production database to compare source system values

library(DBI)
library(odbc)

# Replace with your actual connection
# cdw_conn <- dbConnect(odbc(), "YOUR_CDW_DSN")
# mpi_conn <- dbConnect(odbc(), "YOUR_MPI_DSN")

# Set a test PATID
patid <- "YOUR_PATID_HERE"

# =============================================================================
# QUERY 1: Demographics Panel Source Systems (MPI Database)
# =============================================================================
# This is what shows in the demographics panel at the top of the page
# Tables: dbo.Mpi joined with dbo.MPI_Src

demographics_sources_query <- "
SELECT
  m.Src,
  m.Lid,
  m.Uid,
  s.SRC as MPI_Src_Code,
  s.Description as SourceDescription
FROM dbo.Mpi m
LEFT JOIN dbo.MPI_Src s ON m.Src = s.SRC
WHERE m.Uid = (
  SELECT DISTINCT Uid
  FROM dbo.EnterpriseRecords_Ext
  WHERE CDM_PATID = ?
)
"

# Run with:
# demographics_sources <- dbGetQuery(mpi_conn, demographics_sources_query, params = list(patid))
# print(demographics_sources)


# =============================================================================
# QUERY 2: CDW Event Source Systems (CDW Database)
# =============================================================================
# This is what shows in the timeline filter section
# Aggregates CDW_Source from all clinical event tables

cdw_sources_query <- "
SELECT
  CDW_Source,
  COUNT(*) as event_count,
  'ENCOUNTER' as source_table
FROM dbo.ENCOUNTER
WHERE PATID = ?
GROUP BY CDW_Source

UNION ALL

SELECT
  CDW_Source,
  COUNT(*) as event_count,
  'DIAGNOSIS' as source_table
FROM dbo.DIAGNOSIS
WHERE PATID = ?
GROUP BY CDW_Source

UNION ALL

SELECT
  CDW_Source,
  COUNT(*) as event_count,
  'PROCEDURES' as source_table
FROM dbo.PROCEDURES
WHERE PATID = ?
GROUP BY CDW_Source

UNION ALL

SELECT
  CDW_Source,
  COUNT(*) as event_count,
  'LAB_RESULT_CM' as source_table
FROM dbo.LAB_RESULT_CM
WHERE PATID = ?
GROUP BY CDW_Source

UNION ALL

SELECT
  CDW_Source,
  COUNT(*) as event_count,
  'PRESCRIBING' as source_table
FROM dbo.PRESCRIBING
WHERE PATID = ?
GROUP BY CDW_Source

UNION ALL

SELECT
  CDW_Source,
  COUNT(*) as event_count,
  'DISPENSING' as source_table
FROM dbo.DISPENSING
WHERE PATID = ?
GROUP BY CDW_Source

UNION ALL

SELECT
  CDW_Source,
  COUNT(*) as event_count,
  'VITAL' as source_table
FROM dbo.VITAL
WHERE PATID = ?
GROUP BY CDW_Source

UNION ALL

SELECT
  CDW_Source,
  COUNT(*) as event_count,
  'CONDITION' as source_table
FROM dbo.CONDITION
WHERE PATID = ?
GROUP BY CDW_Source
"

# Run with (note: 8 parameters needed, one per table):
# cdw_sources <- dbGetQuery(cdw_conn, cdw_sources_query,
#                           params = list(patid, patid, patid, patid, patid, patid, patid, patid))
# print(cdw_sources)


# =============================================================================
# QUERY 3: MPI_Src Lookup Table (all entries)
# =============================================================================
# This shows what description mappings are available

mpi_src_lookup_query <- "
SELECT SRC, Description
FROM dbo.MPI_Src
ORDER BY SRC
"

# Run with:
# mpi_src_lookup <- dbGetQuery(mpi_conn, mpi_src_lookup_query)
# print(mpi_src_lookup)


# =============================================================================
# Summary comparison
# =============================================================================
# After running all three queries, compare:
# 1. demographics_sources$Src vs cdw_sources$CDW_Source
# 2. Which CDW_Source values have matches in mpi_src_lookup$SRC
