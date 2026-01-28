# aggregation.R
# Aggregation logic for timeline events (none/daily/weekly)

#' @importFrom dplyr `%>%` mutate filter select any_of case_when n group_by summarise arrange bind_rows
#' @importFrom lubridate isoyear isoweek
#' @importFrom htmltools htmlEscape
NULL

#' Aggregate events by a time period
#'
#' Combine multiple events of the same type into single markers based on
#' time period (daily or weekly). Range events (encounters with discharge dates),
#' death markers, and birth markers are never aggregated.
#'
#' @param events Data frame of timeline events from \code{\link{transform_all_to_timevis}}
#' @param level Aggregation level:
#'   \describe{
#'     \item{"individual"}{No aggregation, every event shown separately}
#'     \item{"daily"}{Events of same type on same day combined}
#'     \item{"weekly"}{Events grouped by ISO week}
#'   }
#'
#' @return Data frame of aggregated events in timevis format
#'
#' @examples
#' \dontrun{
#' events <- transform_all_to_timevis(data)
#' daily <- aggregate_events(events, "daily")
#' weekly <- aggregate_events(events, "weekly")
#' }
#'
#' @export
aggregate_events <- function(events, level = "daily") {
  if (nrow(events) == 0) return(events)
  if (level == "individual") return(events)
  
  # Convert start to Date for period calculation (it may be character)
  events <- events %>%
    mutate(
      start_date = as.Date(start),
      period = case_when(
        level == "daily" ~ as.character(start_date),
        level == "weekly" ~ paste0(isoyear(start_date), "-W", sprintf("%02d", isoweek(start_date))),
        TRUE ~ as.character(start_date)
      )
    )
  
  # Separate events that should be aggregated (box events) from those that shouldn't (ranges/death/birth)
  point_events <- events %>%
    filter(type == "box" & !event_type %in% c("death", "birth"))

  other_events <- events %>%
    filter(type != "box" | event_type %in% c("death", "birth")) %>%
    select(-any_of(c("period", "start_date")))
  
  if (nrow(point_events) == 0) {
    return(other_events)
  }
  
  # Aggregate point events by group and period
  # Remove the start_date and period columns that contain Date objects
  # These Date columns cause dplyr to corrupt character columns during summarise!
  point_events <- point_events %>%
    select(-start_date, -period) %>%
    mutate(
      # Recreate period as character to avoid Date issues
      period_key = start  # For daily aggregation, period is just the start date
    )

  # For weekly aggregation, we need to recalculate period
  if (level == "weekly") {
    point_events <- point_events %>%
      mutate(
        start_date_temp = as.Date(start),
        period_key = paste0(isoyear(start_date_temp), "-W", sprintf("%02d", isoweek(start_date_temp)))
      ) %>%
      select(-start_date_temp)
  }

  # Use base R aggregation to avoid dplyr's weird Date conversion bug
  # Create a grouping key
  point_events$group_key <- paste(point_events$group, point_events$event_type, point_events$period_key, sep = "|||")

  # Split by group_key
  split_events <- split(point_events, point_events$group_key)

  # Build aggregated data frame manually
  agg_list <- lapply(split_events, function(df) {
    # Extract base className (remove modifiers like event-lab-abnormal)
    # Use event_type to construct consistent className
    event_type <- df$event_type[1]
    base_class <- paste0("event-", gsub("_", "-", event_type))
    # Map event_type to className
    base_class <- switch(event_type,
      "encounter" = "event-encounter",
      "diagnosis" = "event-diagnosis",
      "procedure" = "event-procedure",
      "lab" = "event-lab",
      "prescribing" = "event-prescribing",
      "dispensing" = "event-dispensing",
      "vital" = "event-vital",
      "condition" = "event-condition",
      df$className[1]  # fallback to first className
    )

    # Handle source system for aggregated events
    unique_sources <- unique(df$cdw_source[!is.na(df$cdw_source) & df$cdw_source != ""])
    has_multiple_sources <- length(unique_sources) > 1

    # Determine aggregated source values
    if (length(unique_sources) == 0) {
      agg_cdw_source <- NA_character_
      agg_source_description <- NA_character_
      source_class_suffix <- ""
    } else if (length(unique_sources) == 1) {
      agg_cdw_source <- unique_sources[1]
      # Get description from first matching row
      desc_row <- df[!is.na(df$cdw_source) & df$cdw_source == unique_sources[1], ]
      agg_source_description <- if (nrow(desc_row) > 0 && "source_description" %in% names(desc_row)) {
        desc_row$source_description[1]
      } else {
        NA_character_
      }
      source_class_suffix <- paste0(" source-", gsub("[^A-Za-z0-9]", "", unique_sources[1]))
    } else {
      # Multiple sources - mark as mixed
      agg_cdw_source <- NA_character_
      agg_source_description <- NA_character_
      source_class_suffix <- " source-mixed"
    }

    data.frame(
      group = df$group[1],
      event_type = event_type,
      period_key = df$period_key[1],
      count = nrow(df),
      ids = I(list(df$id)),
      contents = I(list(df$content)),
      titles = I(list(df$title)),
      source_keys = I(list(df$source_key)),
      start = df$start[1],  # Take first start
      source_table = df$source_table[1],
      className = paste0(base_class, source_class_suffix),
      cdw_source = agg_cdw_source,
      source_description = agg_source_description,
      multiple_sources = has_multiple_sources,
      all_sources = I(list(unique_sources)),
      stringsAsFactors = FALSE
    )
  })

  aggregated <- do.call(rbind, agg_list)
  rownames(aggregated) <- NULL

  aggregated <- aggregated %>%
    mutate(
      id = paste0("AGG_", group, "_", period_key),
      content = sapply(1:nrow(aggregated), function(i) {
        if (count[i] == 1) {
          contents[[i]][1]
        } else {
          # Proper pluralization for marker label
          group_name <- tools::toTitleCase(gsub("_", " ", group[i]))
          # Handle words ending in -sis (diagnosis -> diagnoses)
          if (grepl("ses$", group_name)) {
            # Already plural (e.g., "diagnoses")
            plural_name <- group_name
          } else if (grepl("sis$", group_name)) {
            plural_name <- gsub("sis$", "ses", group_name)
          } else if (grepl("s$", group_name)) {
            # Already ends in s, assume plural
            plural_name <- group_name
          } else {
            plural_name <- paste0(group_name, "s")
          }
          paste0(count[i], " ", plural_name)
        }
      }),
      end = NA_character_,
      type = "box",
      title = sapply(1:n(), function(i) {
        if (count[i] == 1) {
          titles[[i]][1]
        } else {
          # Build aggregated tooltip
          # Proper pluralization: diagnosis -> diagnoses, others just add "s"
          type_name <- tools::toTitleCase(gsub("_", " ", event_type[i]))
          type_plural <- if (grepl("sis$", type_name)) {
            gsub("sis$", "ses", type_name)  # diagnosis -> diagnoses
          } else {
            paste0(type_name, "s")
          }
          header <- paste0("<b>", count[i], " ", type_plural,
                          " on ", start[i], "</b><br>")
          items <- unlist(contents[i])
          # Limit to first 10 items
          if (length(items) > 10) {
            item_list <- paste0("- ", items[1:10], collapse = "<br>")
            item_list <- paste0(item_list, "<br>... and ", length(items) - 10, " more")
          } else {
            item_list <- paste0("- ", items, collapse = "<br>")
          }
          # Add source system info for aggregated events
          source_info <- ""
          if (multiple_sources[i]) {
            sources_list <- unlist(all_sources[i])
            source_info <- paste0("<br><b>Sources:</b> ", paste(sources_list, collapse = ", "))
          } else if (!is.na(cdw_source[i])) {
            if (!is.na(source_description[i])) {
              source_info <- paste0("<br><b>Source System:</b> ", source_description[i],
                                   " (", cdw_source[i], ")")
            } else {
              source_info <- paste0("<br><b>Source System:</b> ", cdw_source[i])
            }
          }
          paste0(header, item_list, source_info)
        }
      }),
      # Store original IDs for click handling
      original_ids = sapply(ids, function(x) paste(x, collapse = ",")),
      source_key = sapply(source_keys, function(x) paste(x, collapse = ",")),
      is_aggregated = count > 1
    ) %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type, original_ids, is_aggregated,
           cdw_source, source_description)
  
  # Combine with non-aggregated events
  if (nrow(other_events) > 0) {
    other_events <- other_events %>%
      mutate(
        original_ids = id,
        is_aggregated = FALSE
      ) %>%
      select(-any_of("period"))
  }
  
  # Ensure other_events has the same columns as aggregated
  if (nrow(other_events) > 0 && nrow(aggregated) > 0) {
    # Add missing columns to other_events
    for (col in setdiff(names(aggregated), names(other_events))) {
      other_events[[col]] <- NA
    }
    other_events <- other_events %>% select(all_of(names(aggregated)))
  }

  bind_rows(
    aggregated,
    other_events
  ) %>%
    arrange(start)
}

#' Get period label for aggregation
#' @param level Aggregation level
#' @return Human-readable label
get_aggregation_label <- function(level) {
  switch(level,
    "individual" = "Individual Events",
    "daily" = "Daily Aggregation",
    "weekly" = "Weekly Aggregation",
    level
  )
}

#' Parse original IDs from aggregated event
#' @param original_ids Comma-separated string of original event IDs
#' @return Character vector of IDs
parse_original_ids <- function(original_ids) {
  if (is.null(original_ids) || is.na(original_ids) || original_ids == "") {
    return(character(0))
  }
  strsplit(original_ids, ",")[[1]]
}
