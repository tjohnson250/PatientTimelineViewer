# inst/example/app.R - Patient Timeline Viewer Example
# Used by runExample() and viewTimeline() package functions
# Uses the single source of truth from R/app_ui_server.R

library(PatientTimelineViewer)
library(shiny)

# Run the application using the package's single source of truth
shinyApp(ui = timeline_ui(), server = timeline_server)
