# globals.R
# Global variable declarations to avoid R CMD check notes from dplyr NSE

# Suppress R CMD check notes about global variables used in dplyr/tidyverse NSE
utils::globalVariables(c(
  # Database column names
  "ABN_IND", "ADMIT_DATE", "BP_POSITION", "CONDITION", "CONDITIONID",
  "DIAGNOSISID", "DIASTOLIC", "DISCHARGE_DATE", "DISPENSE_AMT",
  "DISPENSE_DATE", "DISPENSE_SUP", "DISPENSINGID", "DRG", "DX", "DX_DATE",
 "DX_TYPE", "ENCOUNTERID", "ENC_TYPE", "FACILITY_LOCATION", "HT",
  "LAB_LOINC", "LAB_RESULT_CM_ID", "MEASURE_DATE", "NDC", "NORM_RANGE_HIGH",
  "NORM_RANGE_LOW", "ONSET_DATE", "ORIGINAL_BMI", "PAYER_TYPE_PRIMARY",
  "PRESCRIBINGID", "PROCEDURESID", "PX", "PX_DATE", "PX_TYPE",
  "RAW_CONDITION", "RAW_DISCHARGE_STATUS", "RAW_DISP_MED_NAME", "RAW_DX",
  "RAW_LAB_NAME", "RAW_PX_NAME", "RAW_RX_FREQUENCY", "RAW_RX_MED_NAME",
  "RAW_RX_ROUTE", "REPORT_DATE", "RESOLVE_DATE", "RESULT_DATE",
  "RESULT_MODIFIER", "RESULT_NUM", "RESULT_QUAL", "RESULT_UNIT",
  "RXNORM_CUI", "RX_DAYS_SUPPLY", "RX_DOSE_ORDERED", "RX_DOSE_ORDERED_UNIT",
  "RX_END_DATE", "RX_ORDER_DATE", "RX_REFILLS", "RX_START_DATE", "SMOKING",
  "SPECIMEN_SOURCE", "SYSTOLIC", "TOBACCO", "VITALID", "WT",

  # Internal computed variables
  "all_of", "arrange", "bp_display", "className", "cond_display", "content",
  "contents", "count", "dose_display", "dx_display", "end", "end_char",
  "event_type", "formatted_result", "group", "id", "ids", "if_else",
  "is_aggregated", "lab_display", "med_display", "n", "norm_range",
  "original_ids", "parsed_date", "parsed_end", "parsed_start", "pdx_desc",
  "period", "period_key", "px_display", "source_key", "source_keys",
  "source_table", "start", "start_char", "start_date", "start_date_temp",
  "status_desc", "title", "titles", "type", "vital_content",

  # httr2 functions (from Suggests)
  "req_body_json", "req_headers", "req_perform", "request", "resp_body_json",

  # stringr functions
  "str_replace_all",

  # Other
  "."
))
