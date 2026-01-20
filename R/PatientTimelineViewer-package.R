#' PatientTimelineViewer: Interactive Patient Timeline Visualization
#'
#' A Shiny application for viewing a comprehensive temporal overview of a
#' single patient's data from a PCORnet CDM data warehouse. Supports both
#' MS SQL Server and DuckDB backends.
#'
#' @section Main Functions:
#' \itemize{
#'   \item \code{\link{runExample}}: Launch the interactive timeline viewer app
#'   \item \code{\link{get_db_connections}}: Connect to CDW and MPI databases
#'   \item \code{\link{load_patient_data}}: Load all data for a patient
#'   \item \code{\link{transform_all_to_timevis}}: Convert data to timeline format
#'   \item \code{\link{apply_all_filters}}: Filter timeline events
#'   \item \code{\link{aggregate_events}}: Aggregate events by time period
#' }
#'
#' @section Configuration:
#' The package uses the \code{config} package for database configuration.
#' See \code{vignette("configuration")} for details on setting up your
#' database connections.
#'
#' @section Optional AI Features:
#' The package includes optional AI-powered semantic filtering using the
#' Anthropic Claude API. Set the \code{ANTHROPIC_API_KEY} environment
#' variable to enable this feature.
#'
#' @importFrom shinyjs useShinyjs
#' @importFrom timevis timevis timevisOutput renderTimevis
#' @keywords internal
"_PACKAGE"
