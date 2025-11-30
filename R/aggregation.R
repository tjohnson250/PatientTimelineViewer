# aggregation.R
# Aggregation logic for timeline events (none/daily/weekly)

library(dplyr)
library(lubridate)
library(htmltools)

#' Aggregate events by a time period
#' @param events Data frame of timeline events
#' @param level Aggregation level: "individual", "daily", or "weekly"
#' @return Data frame of aggregated events
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
  
  # Separate events that should be aggregated (points) from those that shouldn't (ranges/death)
  point_events <- events %>% 
    filter(type == "point" & event_type != "death")
  
  other_events <- events %>% 
    filter(type != "point" | event_type == "death") %>%
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
    data.frame(
      group = df$group[1],
      event_type = df$event_type[1],
      period_key = df$period_key[1],
      count = nrow(df),
      ids = I(list(df$id)),
      contents = I(list(df$content)),
      titles = I(list(df$title)),
      source_keys = I(list(df$source_key)),
      start = df$start[1],  # Take first start
      source_table = df$source_table[1],
      className = df$className[1],
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
          paste0(count[i], " ", gsub("s$", "", group[i]))
        }
      }),
      end = NA_character_,
      type = "point",
      title = sapply(1:n(), function(i) {
        if (count[i] == 1) {
          titles[[i]][1]
        } else {
          # Build aggregated tooltip
          header <- paste0("<b>", count[i], " ", tools::toTitleCase(gsub("_", " ", event_type[i])), 
                          "s on ", start[i], "</b><br>")
          items <- unlist(contents[i])
          # Limit to first 10 items
          if (length(items) > 10) {
            item_list <- paste0("• ", items[1:10], collapse = "<br>")
            item_list <- paste0(item_list, "<br>... and ", length(items) - 10, " more")
          } else {
            item_list <- paste0("• ", items, collapse = "<br>")
          }
          paste0(header, item_list)
        }
      }),
      # Store original IDs for click handling
      original_ids = sapply(ids, function(x) paste(x, collapse = ",")),
      source_key = sapply(source_keys, function(x) paste(x, collapse = ",")),
      is_aggregated = count > 1
    ) %>%
    select(id, content, start, end, group, type, className, title,
           source_table, source_key, event_type, original_ids, is_aggregated)
  
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
