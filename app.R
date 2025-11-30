# app.R - Patient Timeline Viewer
# Main Shiny application for viewing patient clinical data timeline

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

# UI Definition
ui <- fluidPage(
  useShinyjs(),
  
  # Include custom CSS
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
    tags$style(HTML("
      .shiny-notification {
        position: fixed;
        top: 60px;
        right: 20px;
      }
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
    
    # Display options panel
    div(
      class = "filter-panel",
      h4("Display Options"),
      
      # Aggregation radio buttons
      fluidRow(
        column(12,
          radioButtons(
            "aggregation",
            label = "Aggregation:",
            choices = c(
              "Individual" = "individual",
              "Daily" = "daily",
              "Weekly" = "weekly"
            ),
            selected = "daily",
            inline = TRUE
          )
        )
      ),
      
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
      )
    ),
    
    # Timeline container
    div(
      class = "timeline-container",
      fluidRow(
        column(9,
          h4("Timeline", style = "margin: 0 0 5px 0;"),
          p(class = "timeline-hint", "Scroll to zoom • Click and drag to pan")
        ),
        column(3,
          div(
            style = "text-align: right;",
            actionButton("zoom_fit", "Fit All", icon = icon("expand"),
                         class = "btn-sm btn-outline-secondary")
          )
        )
      ),
      div(
        style = "height: 600px; overflow-y: auto;",
        timevisOutput("timeline", height = "600px")
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

# Server Definition
server <- function(input, output, session) {
  
  # Reactive values to store patient data
  rv <- reactiveValues(
    patient_data = NULL,
    timeline_events = NULL,
    selected_event = NULL,
    db_connections = NULL,
    date_range = NULL
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
        checkboxInput(
          inputId = paste0("show_", type),
          label = paste0(event_types[[type]], " (", count, ")"),
          value = TRUE,
          width = "auto"
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
      med_name = input$med_name
    )
    
    # Apply filters
    events <- apply_all_filters(rv$timeline_events, rv$patient_data, filters)
    
    # Apply aggregation
    events <- aggregate_events(events, input$aggregation)
    
    events
  })
  
  # Render timeline
  output$timeline <- renderTimevis({
    req(filtered_events())

    events <- filtered_events()

    if (nrow(events) == 0) {
      return(timevis(data.frame(), groups = get_timeline_groups()))
    }

    # Configure timeline options
    config <- list(
      stack = TRUE,
      stackSubgroups = TRUE,
      showCurrentTime = FALSE,
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

    timevis(
      data = events,
      groups = get_timeline_groups(),
      options = config,
      showZoom = TRUE
    )
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
    selected <- events %>% filter(id == selected_id)
    
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
      total_events
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
        filter(ENCOUNTERID == event$source_key) %>%
        slice(1)
    } else if (event$event_type == "diagnosis") {
      record <- rv$patient_data$diagnoses %>%
        filter(DIAGNOSISID == event$source_key) %>%
        slice(1)
    } else if (event$event_type == "procedure") {
      record <- rv$patient_data$procedures %>%
        filter(PROCEDURESID == event$source_key) %>%
        slice(1)
    } else if (event$event_type == "lab") {
      record <- rv$patient_data$labs %>%
        filter(LAB_RESULT_CM_ID == event$source_key) %>%
        slice(1)
    } else if (event$event_type == "prescribing") {
      record <- rv$patient_data$prescribing %>%
        filter(PRESCRIBINGID == event$source_key) %>%
        slice(1)
    } else if (event$event_type == "dispensing") {
      record <- rv$patient_data$dispensing %>%
        filter(DISPENSINGID == event$source_key) %>%
        slice(1)
    } else if (event$event_type == "vital") {
      record <- rv$patient_data$vitals %>%
        filter(VITALID == event$source_key) %>%
        slice(1)
    } else if (event$event_type == "condition") {
      record <- rv$patient_data$conditions %>%
        filter(CONDITIONID == event$source_key) %>%
        slice(1)
    } else if (event$event_type == "death") {
      record <- rv$patient_data$death
    }
    
    if (is.null(record) || nrow(record) == 0) {
      return(p("No details available for this event."))
    }
    
    # Build key-value display
    detail_rows <- lapply(names(record), function(col) {
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
      div(Filter(Negate(is.null), detail_rows))
    )
  })
  
  # Clear filters button
  observeEvent(input$clear_filters, {
    updateTextInput(session, "dx_pattern", value = "")
    updateTextInput(session, "px_pattern", value = "")
    updateTextInput(session, "lab_name", value = "")
    updateTextInput(session, "med_name", value = "")
    updateSelectInput(session, "enc_type_filter", selected = "ALL")
    
    if (!is.null(rv$date_range)) {
      updateDateInput(session, "date_start", value = rv$date_range$min)
      updateDateInput(session, "date_end", value = rv$date_range$max)
    }
  })
  
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
    fit_timeline()
  })

  # Show related events for encounter
  observeEvent(input$show_related, {
    req(rv$selected_event)
    req(rv$selected_event$event_type == "encounter")

    # Get encounter dates
    enc_id <- rv$selected_event$source_key
    enc <- rv$patient_data$encounters %>%
      filter(ENCOUNTERID == enc_id) %>%
      slice(1)

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

# Run the application
shinyApp(ui = ui, server = server)
