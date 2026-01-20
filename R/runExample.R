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
