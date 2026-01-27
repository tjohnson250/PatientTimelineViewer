# app.R - Patient Timeline Viewer
# Development entry point for running the Shiny app directly
# Uses the single source of truth from R/app_ui_server.R

library(shiny)
library(shinyjs)
library(timevis)
library(dplyr)
library(lubridate)
library(DBI)
library(odbc)
library(config)
library(htmltools)

# Source helper modules
source("R/db_queries.R")
source("R/data_transforms.R")
source("R/aggregation.R")
source("R/filter_helpers.R")
source("R/semantic_filter.R")
source("R/app_ui_server.R")

# Check for Anthropic API key (warn if not present)
if (Sys.getenv("ANTHROPIC_API_KEY") == "") {
  warning(
    "ANTHROPIC_API_KEY environment variable not set.\n",
    "Semantic filtering feature will not work without it.\n",
    "Set the key in your .Renviron file or environment before using AI-powered filters."
  )
}

# Run the application using single source of truth
shinyApp(ui = timeline_ui(), server = timeline_server)
