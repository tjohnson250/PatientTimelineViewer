#' Run the Patient Timeline Viewer Example App
#'
#' Launch the interactive Shiny application for viewing patient timelines.
#' The app demonstrates all features of the PatientTimelineViewer package
#' including timeline visualization, filtering, aggregation, and optional
#' AI-powered semantic filtering.
#'
#' @param display.mode The mode in which to display the application. See
#'   \code{\link[shiny]{runApp}} for details.
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}.
#'
#' @return This function does not return a value; it launches a Shiny app.
#'
#' @examples
#' \dontrun{
#' # Launch the example app
#' runExample()
#' }
#'
#' @export
runExample <- function(display.mode = "normal", ...) {
  app_dir <- system.file("example", package = "PatientTimelineViewer")
  if (app_dir == "") {
    stop("Could not find example app directory. Try reinstalling the package.",
         call. = FALSE)
  }
  shiny::runApp(app_dir, display.mode = display.mode, ...)
}

#' Get Path to Sample Data
#'
#' Returns the path to the bundled sample DuckDB database files for testing.
#'
#' @param file Which sample data file to return the path for.
#'   Options: "cdw" (PCORnet CDM data) or "mpi" (Master Patient Index).
#'
#' @return Character string with the full path to the sample data file.
#'
#' @examples
#' \dontrun{
#' # Get path to sample CDW database
#' cdw_path <- get_sample_data_path("cdw")
#'
#' # Get path to sample MPI database
#' mpi_path <- get_sample_data_path("mpi")
#' }
#'
#' @export
get_sample_data_path <- function(file = c("cdw", "mpi")) {

  file <- match.arg(file)


  filename <- switch(file,
    cdw = "pcornet_cdw.duckdb",
    mpi = "mpi.duckdb"
  )

  path <- system.file("extdata", filename, package = "PatientTimelineViewer")
  if (path == "") {
    stop("Could not find sample data file: ", filename,
         ". Try reinstalling the package.", call. = FALSE)
  }
  path
}

#' Launch Timeline Viewer with Custom Database Connections
#'
#' Launch the Patient Timeline Viewer Shiny application using user-supplied
#' database connections instead of reading from config.yml. This is useful
#' when running from Quarto documents or when you want to connect to multiple
#' databases in the same session.
#'
#' @param cdw_conn A DBI connection object to the CDW (PCORnet CDM) database.
#'   This connection must have access to the PCORnet CDM tables (DEMOGRAPHIC,
#'   ENCOUNTER, DIAGNOSIS, etc.).
#' @param mpi_conn A DBI connection object to the MPI (Master Patient Index)
#'   database. Optional - can be NULL if MPI data is not available, or the
#'   same as cdw_conn if MPI tables are in the same database.
#' @param db_type The database type, either "mssql" or "duckdb". This affects
#'   query parameter syntax and schema qualification.
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}.
#'
#' @return This function does not return a value; it launches a Shiny app.
#'
#' @examples
#' \dontrun{
#' # Example 1: From a Quarto document with ODBC connection
#' library(DBI)
#' library(odbc)
#'
#' cdw <- dbConnect(odbc(), "MY_CDW_DSN")
#' DBI::dbExecute(cdw, "USE CDW")
#'
#' viewTimeline(cdw_conn = cdw, mpi_conn = cdw, db_type = "mssql")
#'
#' # Example 2: DuckDB with separate files
#' library(duckdb)
#'
#' cdw <- dbConnect(duckdb(), "path/to/cdw.duckdb")
#' mpi <- dbConnect(duckdb(), "path/to/mpi.duckdb")
#'
#' viewTimeline(cdw_conn = cdw, mpi_conn = mpi, db_type = "duckdb")
#'
#' # Example 3: Without MPI database
#' viewTimeline(cdw_conn = cdw, db_type = "mssql")
#' }
#'
#' @export
viewTimeline <- function(cdw_conn, mpi_conn = NULL, db_type = c("mssql", "duckdb"), ...) {
  # Validate db_type

  db_type <- match.arg(db_type)


  # Validate cdw_conn is a DBI connection
  if (!inherits(cdw_conn, "DBIConnection")) {
    stop("cdw_conn must be a DBI connection object", call. = FALSE)
  }

  # Validate mpi_conn if provided
  if (!is.null(mpi_conn) && !inherits(mpi_conn, "DBIConnection")) {
    stop("mpi_conn must be a DBI connection object or NULL", call. = FALSE)
  }

  # Set package state for db_type (needed by execute_query)
  .pkg_state$db_type <- db_type

  # Create connections list

  conns <- list(
    cdw = cdw_conn,
    mpi = mpi_conn,
    db_type = db_type
  )

  # Find the app directory
  app_dir <- system.file("example", package = "PatientTimelineViewer")
  if (app_dir == "") {
    stop("Could not find example app directory. Try reinstalling the package.",
         call. = FALSE)
  }

  # Store connections in shiny options so the app can retrieve them
  shiny::shinyOptions(ptv_connections = conns)

  # Launch the app
  shiny::runApp(app_dir, ...)
}
