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

# Package-level environment for storing background process
.ptv_env <- new.env(parent = emptyenv())

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
#' @param background Logical. If TRUE (the default), runs the app in a
#'   background R process, allowing you to continue working in your R session.
#'   The app URL will be printed and opened in your browser. Use
#'   \code{\link{stopViewer}} to stop the background app. If FALSE, runs in
#'   the current session (blocking).
#' @param port The TCP port for the Shiny app. Default is 3838. Only used when
#'   background = TRUE.
#' @param launch.browser Logical. Should the app be opened in a browser?
#'   Default is TRUE.
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}.
#'
#' @return If background = TRUE, returns invisibly a list with the process
#'   handle and URL. If background = FALSE, does not return (blocks until
#'   app closes).
#'
#' @examples
#' \dontrun{
#' # Example 1: From a Quarto document with ODBC connection (non-blocking)
#' library(DBI)
#' library(odbc)
#'
#' cdw <- dbConnect(odbc(), "MY_CDW_DSN")
#' DBI::dbExecute(cdw, "USE CDW")
#'
#' viewTimeline(cdw_conn = cdw, mpi_conn = cdw, db_type = "mssql")
#' # App runs in background, continue working...
#'
#' # When done:
#' stopViewer()
#'
#' # Example 2: Blocking mode (traditional Shiny behavior)
#' viewTimeline(cdw_conn = cdw, db_type = "mssql", background = FALSE)
#'
#' # Example 3: DuckDB with separate files
#' library(duckdb)
#'
#' cdw <- dbConnect(duckdb(), "path/to/cdw.duckdb")
#' mpi <- dbConnect(duckdb(), "path/to/mpi.duckdb")
#'
#' viewTimeline(cdw_conn = cdw, mpi_conn = mpi, db_type = "duckdb")
#' }
#'
#' @seealso \code{\link{stopViewer}} to stop a background viewer
#'
#' @export
viewTimeline <- function(cdw_conn, mpi_conn = NULL, db_type = c("mssql", "duckdb"),
                         background = TRUE, port = 3838, launch.browser = TRUE, ...) {
  db_type <- match.arg(db_type)

  # Validate cdw_conn is a DBI connection
  if (!inherits(cdw_conn, "DBIConnection")) {
    stop("cdw_conn must be a DBI connection object", call. = FALSE)
  }

  # Validate mpi_conn if provided
  if (!is.null(mpi_conn) && !inherits(mpi_conn, "DBIConnection")) {
    stop("mpi_conn must be a DBI connection object or NULL", call. = FALSE)
  }

  # Find the app directory

  app_dir <- system.file("example", package = "PatientTimelineViewer")
  if (app_dir == "") {
    stop("Could not find example app directory. Try reinstalling the package.",
         call. = FALSE)
  }

  if (background) {
    # Check for callr package
    if (!requireNamespace("callr", quietly = TRUE)) {
      stop("The 'callr' package is required for background mode. ",
           "Install with: install.packages('callr')", call. = FALSE)
    }

    # Stop any existing background viewer
    if (!is.null(.ptv_env$process) && .ptv_env$process$is_alive()) {
      message("Stopping existing background viewer...")
      .ptv_env$process$kill()
      Sys.sleep(0.5)
    }

    # Extract connection info for recreation in subprocess
    # For ODBC connections, we need to get DSN info
    cdw_info <- get_connection_info(cdw_conn)
    mpi_info <- if (!is.null(mpi_conn)) get_connection_info(mpi_conn) else NULL

    url <- paste0("http://127.0.0.1:", port, "/")

    # Launch in background process
    .ptv_env$process <- callr::r_bg(
      function(app_dir, cdw_info, mpi_info, db_type, port) {
        # Recreate connections in the subprocess
        cdw_conn <- recreate_connection(cdw_info)
        mpi_conn <- if (!is.null(mpi_info)) recreate_connection(mpi_info) else NULL

        # Set package state
        PatientTimelineViewer:::.pkg_state$db_type <- db_type

        # Create connections list
        conns <- list(
          cdw = cdw_conn,
          mpi = mpi_conn,
          db_type = db_type
        )

        # Store connections in shiny options
        shiny::shinyOptions(ptv_connections = conns)

        # Run the app
        shiny::runApp(app_dir, port = port, launch.browser = FALSE)
      },
      args = list(
        app_dir = app_dir,
        cdw_info = cdw_info,
        mpi_info = mpi_info,
        db_type = db_type,
        port = port
      ),
      package = TRUE
    )

    .ptv_env$url <- url
    .ptv_env$port <- port

    # Wait a moment for the app to start
    Sys.sleep(2)

    if (.ptv_env$process$is_alive()) {
      message("Timeline Viewer running at: ", url)
      message("Use stopViewer() to stop the app.")

      if (launch.browser) {
        utils::browseURL(url)
      }

      invisible(list(process = .ptv_env$process, url = url))
    } else {
      # Process died, get error
      result <- .ptv_env$process$get_result()
      stop("Failed to start Timeline Viewer: ", conditionMessage(result),
           call. = FALSE)
    }

  } else {
    # Blocking mode - original behavior
    .pkg_state$db_type <- db_type

    conns <- list(
      cdw = cdw_conn,
      mpi = mpi_conn,
      db_type = db_type
    )

    shiny::shinyOptions(ptv_connections = conns)
    shiny::runApp(app_dir, port = port, launch.browser = launch.browser, ...)
  }
}

#' Stop Background Timeline Viewer
#'
#' Stops a Timeline Viewer app that was started with
#' \code{viewTimeline(background = TRUE)}.
#'
#' @return Invisible TRUE if a process was stopped, FALSE if no process was running.
#'
#' @examples
#' \dontrun{
#' # Start the viewer
#' viewTimeline(cdw_conn = cdw, db_type = "mssql")
#'
#' # Do some work...
#'
#' # Stop the viewer
#' stopViewer()
#' }
#'
#' @seealso \code{\link{viewTimeline}}
#'
#' @export
stopViewer <- function() {
  if (!is.null(.ptv_env$process) && .ptv_env$process$is_alive()) {
    .ptv_env$process$kill()
    message("Timeline Viewer stopped.")
    .ptv_env$process <- NULL
    .ptv_env$url <- NULL
    invisible(TRUE)
  } else {
    message("No background Timeline Viewer is running.")
    invisible(FALSE)
  }
}

#' Check if Timeline Viewer is Running
#'
#' Check if a background Timeline Viewer is currently running.
#'
#' @return Logical TRUE if running, FALSE otherwise.
#'
#' @examples
#' \dontrun{
#' if (isViewerRunning()) {
#'   message("Viewer is running at: ", getViewerURL())
#' }
#' }
#'
#' @export
isViewerRunning <- function() {
  !is.null(.ptv_env$process) && .ptv_env$process$is_alive()
}

#' Get Timeline Viewer URL
#'
#' Get the URL of the currently running background Timeline Viewer.
#'
#' @return Character URL if running, NULL otherwise.
#'
#' @export
getViewerURL <- function() {
  if (isViewerRunning()) {
    .ptv_env$url
  } else {
    NULL
  }
}

# Helper function to extract connection info for recreation in subprocess
get_connection_info <- function(conn) {
  if (inherits(conn, "Microsoft SQL Server")) {
    # ODBC connection
    info <- DBI::dbGetInfo(conn)
    list(
      type = "odbc",
      dsn = info$servername,
      database = info$dbname
    )
  } else if (inherits(conn, "duckdb_connection")) {
    # DuckDB connection
    info <- DBI::dbGetInfo(conn)
    list(
      type = "duckdb",
      dbdir = info$dbdir
    )
  } else {
    # Generic - try to get info
    info <- tryCatch(DBI::dbGetInfo(conn), error = function(e) list())
    list(
      type = "unknown",
      info = info
    )
  }
}

# Helper function to recreate connection from info
recreate_connection <- function(info) {
  if (info$type == "odbc") {
    conn <- DBI::dbConnect(odbc::odbc(), info$dsn)
    if (!is.null(info$database) && info$database != "") {
      DBI::dbExecute(conn, paste("USE", info$database))
    }
    conn
  } else if (info$type == "duckdb") {
    DBI::dbConnect(duckdb::duckdb(), dbdir = info$dbdir, read_only = FALSE)
  } else {
    stop("Cannot recreate connection of type: ", info$type, call. = FALSE)
  }
}
