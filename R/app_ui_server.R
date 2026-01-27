# app_ui_server.R - Patient Timeline Viewer UI and Server
# This is the single source of truth for the Shiny app UI and server logic.
# Used by both app.R (development) and runExample()/viewTimeline() (package).

#' Create the Patient Timeline Viewer UI
#'
#' Returns the UI definition for the Patient Timeline Viewer Shiny application.
#' This is the single source of truth for the app UI.
#'
#' @return A Shiny UI object (fluidPage)
#' @export
timeline_ui <- function() {
  fluidPage(
    shinyjs::useShinyjs(),

    # Include custom CSS and JavaScript
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
      tags$script(src = "cluster-colors.js"),
      tags$script(src = "timeline-markers.js"),
      tags$style(HTML("
        .shiny-notification {
          position: fixed;
          top: 60px;
          right: 20px;
        }
        .help-icon {
          margin-left: 5px;
          color: #7f8c8d;
          cursor: help;
          font-size: 14px;
        }
        .help-icon:hover {
          color: #5a6268;
        }
      ")),
      tags$script(HTML("
        // Preserve timeline window when re-rendering
        var savedTimelineWindow = null;

        // Save window before timeline updates
        $(document).on('shiny:inputchanged', function(event) {
          // Save window when clustering or aggregation changes
          if (event.name === 'enable_clustering' || event.name === 'aggregation') {
            var widget = HTMLWidgets.find('#timeline');
            if (widget && widget.timeline) {
              var window = widget.timeline.getWindow();
              savedTimelineWindow = {
                start: window.start.getTime(),
                end: window.end.getTime()
              };
              console.log('Saved timeline window for', event.name, ':', savedTimelineWindow);
            }
          }
        });

        // Restore window after timeline renders
        $(document).on('shiny:value', function(event) {
          if (event.name === 'timeline' && savedTimelineWindow) {
            setTimeout(function() {
              var widget = HTMLWidgets.find('#timeline');
              if (widget && widget.timeline) {
                widget.timeline.setWindow(
                  new Date(savedTimelineWindow.start),
                  new Date(savedTimelineWindow.end),
                  {animation: false}
                );
                console.log('Restored timeline window');
                savedTimelineWindow = null;
              }
            }, 100);
          }
        });

        // Initialize Bootstrap tooltips
        $(document).ready(function() {
          $('[data-toggle=\"tooltip\"]').tooltip();
        });

        // Re-initialize tooltips when UI updates
        $(document).on('shiny:value', function(event) {
          setTimeout(function() {
            $('[data-toggle=\"tooltip\"]').tooltip();
          }, 100);
        });
      "))
    ),

    # App title
    titlePanel(
      div(class = "app-title", "Patient Timeline Viewer"),
      windowTitle = "Patient Timeline Viewer"
    ),

    # Patient ID input section
    div(
      class = "patient-input-panel",
      fluidRow(
        column(8,
          textInput(
            "patid",
            label = NULL,
            placeholder = "Enter Patient ID (PATID)",
            width = "100%"
          )
        ),
        column(4,
          actionButton(
            "load_patient",
            "Load Patient",
            class = "btn-load",
            width = "100%",
            icon = icon("user")
          )
        )
      )
    ),

    # Demographics panel (conditional)
    uiOutput("demographics_panel"),

    # Main content (conditional on patient loaded)
    conditionalPanel(
      condition = "output.patient_loaded",

      # Semantic filter panel
      div(
        class = "filter-panel",
        style = "background-color: #f8f9fa; border-left: 4px solid #3498db;",
        h4(
          icon("magic"), " AI-Powered Filter",
          tags$i(
            class = "fa fa-question-circle help-icon",
            `data-toggle` = "tooltip",
            `data-placement` = "top",
            title = "Ask questions in plain English like 'Show encounters with A1c > 9' or 'Show inpatient encounters from 2023'"
          )
        ),

        fluidRow(
          column(9,
            textInput(
              "semantic_query",
              label = NULL,
              placeholder = "e.g., Show encounters with A1c > 9, Show only inpatient encounters, Show diagnoses containing diabetes...",
              width = "100%"
            )
          ),
          column(3,
            div(
              style = "display: flex; gap: 5px;",
              actionButton(
                "apply_semantic_filter",
                "Apply",
                class = "btn-primary",
                icon = icon("search"),
                style = "flex: 1;"
              ),
              actionButton(
                "clear_semantic_filter",
                "Clear",
                class = "btn-secondary",
                icon = icon("times"),
                style = "flex: 1;"
              )
            )
          )
        ),

        # Status/error message area
        uiOutput("semantic_filter_status"),

        # Collapsible SQL display panel
        conditionalPanel(
          condition = "output.show_generated_sql",
          tags$details(
            class = "generated-sql-panel",
            style = "margin-top: 10px;",
            tags$summary(
              style = "cursor: pointer; font-weight: 600; color: #7f8c8d; padding: 5px;",
              icon("code"), " View Generated SQL"
            ),
            div(
              style = "padding: 10px; background-color: #2c3e50; color: #ecf0f1; border-radius: 4px; font-family: monospace; font-size: 12px; overflow-x: auto; margin-top: 5px;",
              uiOutput("generated_sql")
            )
          )
        )
      ),

      # Display options panel
      div(
        class = "filter-panel",
        h4("Display Options"),

        # Event type checkboxes
        fluidRow(
          column(12,
            div(
              style = "margin-bottom: 10px;",
              strong("Event Types:")
            ),
            uiOutput("event_type_checkboxes")
          )
        ),

        # Date range
        fluidRow(
          column(6,
            dateInput(
              "date_start",
              "Start Date:",
              value = NULL
            )
          ),
          column(6,
            dateInput(
              "date_end",
              "End Date:",
              value = NULL
            )
          )
        ),

        # Advanced filters (collapsible)
        tags$details(
          class = "advanced-filters",
          tags$summary(
            style = "cursor: pointer; font-weight: 600; color: #7f8c8d;",
            icon("filter"), " Advanced Filters"
          ),
          div(
            style = "padding-top: 15px;",
            fluidRow(
              column(4,
                textInput(
                  "dx_pattern",
                  "Diagnosis Code (SQL LIKE):",
                  placeholder = "e.g., E11%"
                )
              ),
              column(4,
                textInput(
                  "px_pattern",
                  "Procedure Code (SQL LIKE):",
                  placeholder = "e.g., 99%"
                )
              ),
              column(4,
                textInput(
                  "lab_name",
                  "Lab Name (partial match):",
                  placeholder = "e.g., glucose"
                )
              )
            ),
            fluidRow(
              column(4,
                textInput(
                  "med_name",
                  "Medication Name (partial match):",
                  placeholder = "e.g., metformin"
                )
              ),
              column(4,
                selectInput(
                  "enc_type_filter",
                  "Encounter Type:",
                  choices = c("All" = "ALL"),
                  multiple = TRUE
                )
              ),
              column(4,
                actionButton(
                  "clear_filters",
                  "Clear Filters",
                  class = "btn-secondary",
                  icon = icon("times"),
                  style = "margin-top: 25px;"
                )
              )
            )
          )
        ),

        # Aggregation and clustering controls
        fluidRow(
          style = "margin-top: 15px; padding-top: 15px; border-top: 1px solid #dee2e6;",
          column(8,
            radioButtons(
              "aggregation",
              label = tags$span(
                "Aggregation:",
                tags$i(
                  class = "fa fa-question-circle help-icon",
                  `data-toggle` = "tooltip",
                  `data-placement` = "top",
                  title = "Aggregates events before creating the timeline. Individual shows every event separately, Daily combines events of the same type on the same date, Weekly groups by ISO week."
                )
              ),
              choices = c(
                "Individual" = "individual",
                "Daily" = "daily",
                "Weekly" = "weekly"
              ),
              selected = "daily",
              inline = TRUE
            )
          ),
          column(4,
            checkboxInput(
              "enable_clustering",
              label = tags$span(
                "Enable auto-clustering",
                tags$i(
                  class = "fa fa-question-circle help-icon",
                  `data-toggle` = "tooltip",
                  `data-placement` = "top",
                  title = "Dynamically aggregates events as you zoom in and out of the timeline for better performance with large datasets."
                )
              ),
              value = TRUE
            )
          )
        )
      ),

      # Source system filter section
      div(
        class = "filter-panel",
        div(
          class = "source-filter-section",
          div(
            style = "margin-bottom: 10px;",
            strong("Source Systems:"),
            tags$i(
              class = "fa fa-question-circle help-icon",
              `data-toggle` = "tooltip",
              `data-placement` = "top",
              title = "Filter events by their originating source system (EMR). Colored left borders on timeline events indicate source."
            )
          ),
          uiOutput("source_system_checkboxes"),
          uiOutput("source_legend")
        )
      ),

      # Timeline container
      div(
        class = "timeline-container",
        fluidRow(
          column(9,
            h4("Timeline", style = "margin: 0 0 5px 0;"),
            p(class = "timeline-hint", "Scroll to zoom \u2022 Click and drag to pan \u2022 Double-click an event to zoom in")
          ),
          column(3,
            div(
              class = "timeline-controls",
              actionButton("zoom_fit", "Fit All", icon = icon("expand"),
                           class = "btn-sm btn-outline-secondary"),
              actionButton("zoom_in", "", icon = icon("plus"),
                           class = "btn-sm btn-outline-secondary",
                           title = "Zoom in"),
              actionButton("zoom_out", "", icon = icon("minus"),
                           class = "btn-sm btn-outline-secondary",
                           title = "Zoom out")
            )
          )
        ),
        div(
          style = "height: 600px; overflow-y: auto;",
          timevis::timevisOutput("timeline", height = "600px")
        )
      ),

      # Event details panel
      div(
        class = "detail-panel",
        h4("Event Details"),
        uiOutput("event_details"),
        conditionalPanel(
          condition = "output.show_related_button",
          div(
            style = "margin-top: 15px;",
            actionButton(
              "show_related",
              "Show Related Events",
              class = "btn-related",
              icon = icon("link")
            ),
            actionButton(
              "reset_view",
              "Reset View",
              class = "btn-reset",
              icon = icon("undo")
            )
          )
        )
      )
    ),

    # Initial message when no patient loaded
    conditionalPanel(
      condition = "!output.patient_loaded",
      div(
        class = "no-data-message",
        div(class = "icon", icon("user-circle")),
        p("Enter a Patient ID above and click 'Load Patient' to view their timeline.")
      )
    )
  )
}

#' Create the Patient Timeline Viewer Server
#'
#' Returns the server function for the Patient Timeline Viewer Shiny application.
#' This is the single source of truth for the app server logic.
#'
#' @param input Shiny input object
#' @param output Shiny output object
#' @param session Shiny session object
#' @return NULL (called for side effects)
#' @export
timeline_server <- function(input, output, session) {

  # Reactive values to store patient data
  rv <- reactiveValues(
    patient_data = NULL,
    timeline_events = NULL,
    selected_event = NULL,
    db_connections = NULL,
    date_range = NULL,
    semantic_filter_active = FALSE,
    semantic_filter_sql = NULL,
    semantic_filter_table = NULL,
    semantic_filter_results = NULL
  )

  # Output to control conditional panels
  output$patient_loaded <- reactive({
    !is.null(rv$patient_data) && nrow(rv$patient_data$demographic) > 0
  })
  outputOptions(output, "patient_loaded", suspendWhenHidden = FALSE)

  # Show related button only for encounters
  output$show_related_button <- reactive({
    !is.null(rv$selected_event) &&
    rv$selected_event$event_type == "encounter"
  })
  outputOptions(output, "show_related_button", suspendWhenHidden = FALSE)

  # Initialize database connections
  observe({
    tryCatch({
      rv$db_connections <- get_db_connections()
    }, error = function(e) {
      showNotification(
        paste("Database connection error:", e$message),
        type = "error",
        duration = NULL
      )
    })
  })

  # Clean up connections on session end
  onSessionEnded(function() {
    if (!is.null(isolate(rv$db_connections))) {
      close_db_connections(isolate(rv$db_connections))
    }
  })

  # Load patient data when button clicked
  observeEvent(input$load_patient, {
    req(input$patid)
    req(rv$db_connections)

    patid <- trimws(input$patid)
    if (patid == "") {
      showNotification("Please enter a Patient ID", type = "warning")
      return()
    }

    # Show loading notification
    showNotification("Loading patient data...", id = "loading", duration = NULL)

    tryCatch({
      # Load all patient data
      rv$patient_data <- load_patient_data(rv$db_connections, patid)

      # Check if patient exists
      if (nrow(rv$patient_data$demographic) == 0) {
        removeNotification("loading")
        showNotification(
          paste("No patient found with ID:", patid),
          type = "warning"
        )
        rv$patient_data <- NULL
        return()
      }

      # Get date range
      rv$date_range <- get_date_range(rv$patient_data)

      # Update date inputs
      updateDateInput(session, "date_start", value = rv$date_range$min)
      updateDateInput(session, "date_end", value = rv$date_range$max)

      # Transform to timeline format
      rv$timeline_events <- transform_all_to_timevis(rv$patient_data)

      # Update encounter type filter
      enc_types <- get_encounter_types(rv$patient_data$encounters)
      updateSelectInput(
        session, "enc_type_filter",
        choices = c("All" = "ALL", setNames(enc_types, enc_types)),
        selected = "ALL"
      )

      # Clear selected event
      rv$selected_event <- NULL

      removeNotification("loading")
      showNotification(
        paste("Loaded", get_total_event_count(rv$patient_data), "events"),
        type = "message"
      )

    }, error = function(e) {
      removeNotification("loading")
      showNotification(
        paste("Error loading patient:", e$message),
        type = "error",
        duration = NULL
      )
    })
  })

  # Render event type checkboxes with counts
  output$event_type_checkboxes <- renderUI({
    req(rv$patient_data)

    counts <- get_event_type_counts(rv$patient_data)

    event_types <- c(
      "encounters" = "Encounters",
      "diagnoses" = "Diagnoses",
      "procedures" = "Procedures",
      "labs" = "Labs",
      "prescribing" = "Prescriptions",
      "dispensing" = "Dispensing",
      "vitals" = "Vitals",
      "conditions" = "Conditions"
    )

    checkboxes <- lapply(names(event_types), function(type) {
      count <- counts[[type]]
      tags$div(
        class = "event-type-checkbox",
        tags$span(class = paste("color-indicator", type)),
        tags$div(
          class = "checkbox-wrapper",
          checkboxInput(
            inputId = paste0("show_", type),
            label = paste0(event_types[[type]], " (", count, ")"),
            value = TRUE,
            width = "auto"
          )
        )
      )
    })

    div(style = "display: flex; flex-wrap: wrap;", checkboxes)
  })

  # Get selected event types
  get_selected_event_types <- reactive({
    types <- c()
    if (isTRUE(input$show_encounters)) types <- c(types, "encounters")
    if (isTRUE(input$show_diagnoses)) types <- c(types, "diagnoses")
    if (isTRUE(input$show_procedures)) types <- c(types, "procedures")
    if (isTRUE(input$show_labs)) types <- c(types, "labs")
    if (isTRUE(input$show_prescribing)) types <- c(types, "prescribing")
    if (isTRUE(input$show_dispensing)) types <- c(types, "dispensing")
    if (isTRUE(input$show_vitals)) types <- c(types, "vitals")
    if (isTRUE(input$show_conditions)) types <- c(types, "conditions")
    types
  })

  # Source system color palette (matches CSS)
  source_colors <- c(
    "#FF6B35", "#2EC4B6", "#9B59B6", "#3498DB",
    "#E74C3C", "#27AE60", "#F39C12", "#1ABC9C"
  )

  # Render source system checkboxes
  output$source_system_checkboxes <- renderUI({
    req(rv$patient_data)

    sources <- get_source_systems(rv$patient_data)

    if (nrow(sources) == 0) {
      return(tags$p(
        class = "text-muted",
        style = "font-size: 12px; font-style: italic;",
        "No source system information available"
      ))
    }

    checkboxes <- lapply(1:nrow(sources), function(i) {
      src <- sources[i, ]
      input_id <- paste0("show_source_", gsub("[^A-Za-z0-9]", "_", src$source_code))

      tags$div(
        class = "source-system-checkbox",
        checkboxInput(
          inputId = input_id,
          label = src$display_label,
          value = TRUE,
          width = "auto"
        )
      )
    })

    div(style = "display: flex; flex-wrap: wrap; gap: 10px;", checkboxes)
  })

  # Render source system legend
  output$source_legend <- renderUI({
    req(rv$patient_data)

    sources <- get_source_systems(rv$patient_data)

    if (nrow(sources) == 0) return(NULL)

    legend_items <- lapply(1:nrow(sources), function(i) {
      src <- sources[i, ]
      color <- source_colors[((i - 1) %% length(source_colors)) + 1]

      tags$span(
        class = "source-legend-item",
        tags$span(
          class = "source-legend-color",
          style = paste0("background-color: ", color, ";")
        ),
        if (!is.na(src$source_description)) {
          paste0(src$source_description, " (", src$source_code, ")")
        } else {
          src$source_code
        }
      )
    })

    div(
      class = "source-legend",
      tags$span(class = "source-legend-title", "Legend: "),
      div(class = "source-legend-items", legend_items)
    )
  })

  # Get selected source systems
  get_selected_source_systems <- reactive({
    req(rv$patient_data)

    sources <- get_source_systems(rv$patient_data)

    if (nrow(sources) == 0) return(NULL)

    selected <- c()
    for (i in 1:nrow(sources)) {
      input_id <- paste0("show_source_", gsub("[^A-Za-z0-9]", "_", sources$source_code[i]))
      if (isTRUE(input[[input_id]])) {
        selected <- c(selected, sources$source_code[i])
      }
    }

    # If all selected, return NULL (no filtering)
    if (length(selected) == nrow(sources)) {
      return(NULL)
    }

    selected
  })

  # Filtered and aggregated events
  filtered_events <- reactive({
    req(rv$timeline_events)

    # Collect filter values
    filters <- list(
      event_types = get_selected_event_types(),
      start_date = input$date_start,
      end_date = input$date_end,
      dx_pattern = input$dx_pattern,
      px_pattern = input$px_pattern,
      lab_name = input$lab_name,
      med_name = input$med_name,
      semantic_results = if (rv$semantic_filter_active) rv$semantic_filter_results else NULL,
      semantic_table = if (rv$semantic_filter_active) rv$semantic_filter_table else NULL,
      source_systems = get_selected_source_systems()
    )

    # Apply filters
    events <- apply_all_filters(rv$timeline_events, rv$patient_data, filters)

    # Apply aggregation
    events <- aggregate_events(events, input$aggregation)

    events
  })

  # Render timeline
  output$timeline <- timevis::renderTimevis({
    req(filtered_events())

    events <- filtered_events()

    if (nrow(events) == 0) {
      return(timevis::timevis(data.frame(), groups = get_timeline_groups()))
    }

    # Calculate the actual date range from the events
    event_dates <- as.Date(events$start)

    # Also include birth and death dates if available
    all_dates <- event_dates
    if (!is.null(rv$patient_data$demographic) &&
        nrow(rv$patient_data$demographic) > 0 &&
        !is.na(rv$patient_data$demographic$BIRTH_DATE[1])) {
      all_dates <- c(all_dates, as.Date(rv$patient_data$demographic$BIRTH_DATE[1]))
    }
    if (!is.null(rv$patient_data$death) &&
        nrow(rv$patient_data$death) > 0 &&
        !is.na(rv$patient_data$death$DEATH_DATE[1])) {
      all_dates <- c(all_dates, as.Date(rv$patient_data$death$DEATH_DATE[1]))
    }

    min_date <- min(all_dates, na.rm = TRUE)
    max_date <- max(all_dates, na.rm = TRUE)

    # Add some padding (5% on each side)
    date_range <- as.numeric(max_date - min_date)
    padding <- max(1, date_range * 0.05)  # At least 1 day padding
    window_start <- min_date - padding
    window_end <- max_date + padding

    # Configure timeline options
    config <- list(
      stack = TRUE,
      stackSubgroups = TRUE,
      showCurrentTime = FALSE,
      start = window_start,
      end = window_end,
      zoomMin = 86400000,  # 1 day in milliseconds
      zoomMax = 3153600000000,  # 100 years in milliseconds
      tooltip = list(
        followMouse = TRUE,
        overflowMethod = "flip"
      ),
      margin = list(
        item = list(horizontal = 5, vertical = 5)
      ),
      autoResize = TRUE,
      maxHeight = "600px",
      verticalScroll = TRUE,
      zoomable = TRUE
    )

    # Add clustering if enabled
    if (isTRUE(input$enable_clustering)) {
      config$cluster <- list(
        maxItems = 1,
        showStipes = TRUE,
        titleTemplate = "{count} items"
      )
    }

    timevis::timevis(
      data = events,
      groups = get_timeline_groups(),
      options = config,
      showZoom = FALSE
    )
  })

  # Add birth and death markers after timeline renders
  observe({
    req(rv$patient_data)
    req(filtered_events())

    # Get birth date
    birth_date <- NULL
    if (!is.null(rv$patient_data$demographic) &&
        nrow(rv$patient_data$demographic) > 0 &&
        !is.na(rv$patient_data$demographic$BIRTH_DATE[1])) {
      birth_date <- as.character(rv$patient_data$demographic$BIRTH_DATE[1])
    }

    # Get death date
    death_date <- NULL
    if (!is.null(rv$patient_data$death) &&
        nrow(rv$patient_data$death) > 0 &&
        !is.na(rv$patient_data$death$DEATH_DATE[1])) {
      death_date <- as.character(rv$patient_data$death$DEATH_DATE[1])
    }

    # Send to JavaScript
    session$sendCustomMessage('addTimelineMarkers', list(
      birthDate = birth_date,
      deathDate = death_date
    ))
  })

  # Handle timeline event selection
  observeEvent(input$timeline_selected, {
    selected_id <- input$timeline_selected

    if (is.null(selected_id) || length(selected_id) == 0) {
      rv$selected_event <- NULL
      return()
    }

    # Find the selected event
    events <- filtered_events()
    selected <- events %>% dplyr::filter(id == selected_id)

    if (nrow(selected) == 0) {
      rv$selected_event <- NULL
      return()
    }

    rv$selected_event <- as.list(selected[1, ])
  })

  # Render demographics panel
  output$demographics_panel <- renderUI({
    req(rv$patient_data)

    total_events <- get_total_event_count(rv$patient_data)
    html <- format_demographic_html(
      rv$patient_data$demographic,
      rv$patient_data$source_systems,
      total_events,
      rv$patient_data$death
    )

    HTML(html)
  })

  # Render event details
  output$event_details <- renderUI({
    if (is.null(rv$selected_event)) {
      return(p(class = "text-muted", "Click an event on the timeline to view details."))
    }

    event <- rv$selected_event

    # Get the full record from raw data
    record <- NULL

    if (event$event_type == "encounter") {
      record <- rv$patient_data$encounters %>%
        dplyr::filter(ENCOUNTERID == event$source_key) %>%
        dplyr::slice(1)
    } else if (event$event_type == "diagnosis") {
      record <- rv$patient_data$diagnoses %>%
        dplyr::filter(DIAGNOSISID == event$source_key) %>%
        dplyr::slice(1)
    } else if (event$event_type == "procedure") {
      record <- rv$patient_data$procedures %>%
        dplyr::filter(PROCEDURESID == event$source_key) %>%
        dplyr::slice(1)
    } else if (event$event_type == "lab") {
      record <- rv$patient_data$labs %>%
        dplyr::filter(LAB_RESULT_CM_ID == event$source_key) %>%
        dplyr::slice(1)
    } else if (event$event_type == "prescribing") {
      record <- rv$patient_data$prescribing %>%
        dplyr::filter(PRESCRIBINGID == event$source_key) %>%
        dplyr::slice(1)
    } else if (event$event_type == "dispensing") {
      record <- rv$patient_data$dispensing %>%
        dplyr::filter(DISPENSINGID == event$source_key) %>%
        dplyr::slice(1)
    } else if (event$event_type == "vital") {
      record <- rv$patient_data$vitals %>%
        dplyr::filter(VITALID == event$source_key) %>%
        dplyr::slice(1)
    } else if (event$event_type == "condition") {
      record <- rv$patient_data$conditions %>%
        dplyr::filter(CONDITIONID == event$source_key) %>%
        dplyr::slice(1)
    } else if (event$event_type == "death") {
      record <- rv$patient_data$death
    }

    if (is.null(record) || nrow(record) == 0) {
      return(p("No details available for this event."))
    }

    # Build source system display if available
    source_system_row <- NULL
    if (!is.null(record) && "CDW_Source" %in% names(record) &&
        !is.na(record$CDW_Source[1]) && record$CDW_Source[1] != "") {

      source_code <- record$CDW_Source[1]
      source_desc <- NA

      # Look up description from source_descriptions
      if (!is.null(rv$patient_data$source_descriptions) &&
          nrow(rv$patient_data$source_descriptions) > 0) {
        desc_row <- rv$patient_data$source_descriptions %>%
          dplyr::filter(SRC == source_code)
        if (nrow(desc_row) > 0) {
          source_desc <- desc_row$SourceDescription[1]
        }
      }

      source_display <- if (!is.na(source_desc)) {
        paste0(source_desc, " (", source_code, ")")
      } else {
        as.character(source_code)
      }

      source_system_row <- div(
        class = "detail-row source-system-row",
        span(class = "detail-key", "Source System"),
        span(class = "detail-value", source_display)
      )
    }

    # Build key-value display (exclude CDW_Source since we show it specially)
    detail_rows <- lapply(names(record), function(col) {
      if (col == "CDW_Source") return(NULL)  # Skip - shown separately
      value <- record[[col]][1]
      if (!is.null(value) && !is.na(value) && as.character(value) != "") {
        div(
          class = "detail-row",
          span(class = "detail-key", col),
          span(class = "detail-value", as.character(value))
        )
      }
    })

    div(
      h5(paste("Source Table:", event$source_table)),
      source_system_row,  # Show source system prominently at top
      div(Filter(Negate(is.null), detail_rows))
    )
  })

  # Clear advanced filters button
  observeEvent(input$clear_filters, {
    # Clear only the advanced filter fields
    updateTextInput(session, "dx_pattern", value = "")
    updateTextInput(session, "px_pattern", value = "")
    updateTextInput(session, "lab_name", value = "")
    updateTextInput(session, "med_name", value = "")
    updateSelectInput(session, "enc_type_filter", selected = "ALL")
  })

  # Semantic filter: Apply button
  observeEvent(input$apply_semantic_filter, {
    req(input$semantic_query)
    req(rv$db_connections)
    req(input$patid)

    patid <- trimws(input$patid)
    query <- trimws(input$semantic_query)

    if (query == "") {
      showNotification("Please enter a query", type = "warning")
      return()
    }

    # Disable button while processing
    shinyjs::disable("apply_semantic_filter")

    # Show loading status
    output$semantic_filter_status <- renderUI({
      div(
        style = "margin-top: 10px; padding: 8px; background-color: #d1ecf1; border-left: 3px solid #0c5460; color: #0c5460;",
        icon("spinner", class = "fa-spin"), " Generating SQL query..."
      )
    })

    tryCatch({
      # Get database type
      db_type <- rv$db_connections$db_type

      # Apply semantic filter
      result <- apply_semantic_filter(
        natural_query = query,
        patid = patid,
        db_conn = rv$db_connections$cdw,
        db_type = db_type
      )

      if (!is.null(result$error)) {
        # Show error
        output$semantic_filter_status <- renderUI({
          div(
            style = "margin-top: 10px; padding: 8px; background-color: #f8d7da; border-left: 3px solid #721c24; color: #721c24;",
            icon("exclamation-triangle"), " Error: ", result$error
          )
        })
        rv$semantic_filter_active <- FALSE
        rv$semantic_filter_sql <- NULL

      } else {
        # Show success
        rv$semantic_filter_active <- TRUE
        rv$semantic_filter_sql <- result$sql
        rv$semantic_filter_results <- result$filtered_data

        # Detect which table(s) were queried
        sql_upper <- toupper(result$sql)
        detected_table <- NULL

        # Check for UNION of prescribing and dispensing (medication queries)
        has_prescribing <- grepl("FROM.*PRESCRIBING", sql_upper)
        has_dispensing <- grepl("FROM.*DISPENSING", sql_upper)

        if (has_prescribing && has_dispensing && grepl("UNION", sql_upper)) {
          detected_table <- "medications"  # Special case for combined medication search
        } else if (grepl("FROM.*ENCOUNTER", sql_upper)) {
          detected_table <- "encounters"
        } else if (grepl("FROM.*DIAGNOSIS", sql_upper)) {
          detected_table <- "diagnoses"
        } else if (grepl("FROM.*PROCEDURES", sql_upper)) {
          detected_table <- "procedures"
        } else if (grepl("FROM.*LAB_RESULT_CM", sql_upper)) {
          detected_table <- "labs"
        } else if (has_prescribing) {
          detected_table <- "prescribing"
        } else if (has_dispensing) {
          detected_table <- "dispensing"
        } else if (grepl("FROM.*VITAL", sql_upper)) {
          detected_table <- "vitals"
        } else if (grepl("FROM.*CONDITION", sql_upper)) {
          detected_table <- "conditions"
        }

        rv$semantic_filter_table <- detected_table

        output$semantic_filter_status <- renderUI({
          div(
            style = "margin-top: 10px; padding: 8px; background-color: #d4edda; border-left: 3px solid #155724; color: #155724;",
            icon("check-circle"), " ", result$message,
            if (!is.null(detected_table)) {
              paste0(" from ", detected_table)
            }
          )
        })

        # Display generated SQL
        output$generated_sql <- renderUI({
          pre(style = "margin: 0; white-space: pre-wrap; word-wrap: break-word;", result$sql)
        })
      }

    }, error = function(e) {
      output$semantic_filter_status <- renderUI({
        div(
          style = "margin-top: 10px; padding: 8px; background-color: #f8d7da; border-left: 3px solid #721c24; color: #721c24;",
          icon("exclamation-triangle"), " Error: ", e$message
        )
      })
      rv$semantic_filter_active <- FALSE
      rv$semantic_filter_sql <- NULL
    })

    # Re-enable button
    shinyjs::enable("apply_semantic_filter")
  })

  # Semantic filter: Clear button
  observeEvent(input$clear_semantic_filter, {
    # Reset semantic filter state
    rv$semantic_filter_active <- FALSE
    rv$semantic_filter_sql <- NULL
    rv$semantic_filter_table <- NULL
    rv$semantic_filter_results <- NULL

    # Clear UI elements
    updateTextInput(session, "semantic_query", value = "")
    output$semantic_filter_status <- renderUI(NULL)
    output$generated_sql <- renderUI(NULL)

    showNotification("Semantic filter cleared", type = "message")
  })

  # Output to control SQL display panel visibility
  output$show_generated_sql <- reactive({
    !is.null(rv$semantic_filter_sql)
  })
  outputOptions(output, "show_generated_sql", suspendWhenHidden = FALSE)

  # Helper function to fit timeline window
  fit_timeline <- function() {
    shinyjs::runjs("
      (function() {
        var widget = HTMLWidgets.find('#timeline');
        if (widget && widget.timeline) {
          widget.timeline.fit({
            animation: {
              duration: 500,
              easingFunction: 'easeInOutQuad'
            }
          });
        }
      })();
    ")
  }

  # Helper function to set timeline window to specific dates
  set_timeline_window <- function(start_date, end_date) {
    start_ms <- as.numeric(as.POSIXct(start_date)) * 1000
    end_ms <- as.numeric(as.POSIXct(end_date)) * 1000

    js_code <- sprintf("
      (function() {
        var widget = HTMLWidgets.find('#timeline');
        if (widget && widget.timeline) {
          widget.timeline.setWindow(%f, %f, {animation: true});
        }
      })();
    ", start_ms, end_ms)

    shinyjs::runjs(js_code)
  }

  # Zoom controls
  observeEvent(input$zoom_fit, {
    # Calculate window from actual filtered events
    events <- filtered_events()
    if (!is.null(events) && nrow(events) > 0) {
      event_dates <- as.Date(events$start)

      # Also include birth and death dates if available
      all_dates <- event_dates
      if (!is.null(rv$patient_data$demographic) &&
          nrow(rv$patient_data$demographic) > 0 &&
          !is.na(rv$patient_data$demographic$BIRTH_DATE[1])) {
        all_dates <- c(all_dates, as.Date(rv$patient_data$demographic$BIRTH_DATE[1]))
      }
      if (!is.null(rv$patient_data$death) &&
          nrow(rv$patient_data$death) > 0 &&
          !is.na(rv$patient_data$death$DEATH_DATE[1])) {
        all_dates <- c(all_dates, as.Date(rv$patient_data$death$DEATH_DATE[1]))
      }

      min_date <- min(all_dates, na.rm = TRUE)
      max_date <- max(all_dates, na.rm = TRUE)

      # Add padding (5% on each side)
      date_range <- as.numeric(max_date - min_date)
      padding <- max(1, date_range * 0.05)

      set_timeline_window(min_date - padding, max_date + padding)
    }
  })

  observeEvent(input$zoom_in, {
    shinyjs::runjs("
      (function() {
        var widget = HTMLWidgets.find('#timeline');
        if (widget && widget.timeline) {
          widget.timeline.zoomIn(0.2);
        }
      })();
    ")
  })

  observeEvent(input$zoom_out, {
    shinyjs::runjs("
      (function() {
        var widget = HTMLWidgets.find('#timeline');
        if (widget && widget.timeline) {
          widget.timeline.zoomOut(0.2);
        }
      })();
    ")
  })

  # Show related events for encounter
  observeEvent(input$show_related, {
    req(rv$selected_event)
    req(rv$selected_event$event_type == "encounter")

    # Get encounter dates
    enc_id <- rv$selected_event$source_key
    enc <- rv$patient_data$encounters %>%
      dplyr::filter(ENCOUNTERID == enc_id) %>%
      dplyr::slice(1)

    if (nrow(enc) > 0) {
      start <- as.Date(enc$ADMIT_DATE) - 1
      end <- if (!is.na(enc$DISCHARGE_DATE)) {
        as.Date(enc$DISCHARGE_DATE) + 1
      } else {
        as.Date(enc$ADMIT_DATE) + 1
      }

      # Update date filters
      updateDateInput(session, "date_start", value = start)
      updateDateInput(session, "date_end", value = end)

      # Zoom timeline to this range
      set_timeline_window(start, end)
    }
  })

  # Reset view
  observeEvent(input$reset_view, {
    # Reset date filter inputs
    if (!is.null(rv$date_range)) {
      updateDateInput(session, "date_start", value = rv$date_range$min)
      updateDateInput(session, "date_end", value = rv$date_range$max)
    }

    # Fit timeline to show all events
    fit_timeline()
  })
}
