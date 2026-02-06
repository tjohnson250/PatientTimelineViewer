# Cancellation Feature Implementation

## Overview
Implemented a cancellation mechanism for patient data loading operations. Users can now abort long-running data loads by clicking a "Cancel" button in the loading dialog.

## Changes Made

### 1. R/app_ui_server.R

#### Added Reactive Values
- `rv$cancel_load`: Boolean flag to track cancellation requests
- `rv$loading_in_progress`: Boolean flag to track if loading is currently in progress

#### Replaced Notification with Modal Dialog
Changed from a simple notification to a modal dialog that includes:
- Loading spinner with message
- Cancel button that users can click
- Modal cannot be dismissed by clicking outside (easyClose = FALSE)

#### Added Cancel Handler
New `observeEvent` for `input$cancel_load_btn` that:
- Sets `rv$cancel_load <- TRUE`
- Removes the loading modal
- Shows a notification that loading was cancelled

#### Modified Load Patient Observer
Updated the `observeEvent(input$load_patient, ...)` to:
- Reset cancellation flag at start of load
- Show modal dialog instead of notification
- Pass cancellation check function to `load_patient_data()`
- Check for cancellation after loading completes
- Check for cancellation before processing results
- Properly clean up modal and flags on completion or error

### 2. R/db_queries.R

#### Updated load_patient_data Function
Added `cancel_check` parameter:
- Optional callback function that returns TRUE if loading should be cancelled
- Default value is NULL (no cancellation checking for backwards compatibility)

#### Implemented Cancellation Checking
- Helper function `should_cancel()` checks the callback between each query
- Checks cancellation after each of the 13 queries:
  1. Demographics
  2. Source systems
  3. Source descriptions
  4. Encounters
  5. Diagnoses
  6. Procedures
  7. Labs
  8. Prescribing
  9. Dispensing
  10. Vitals
  11. Conditions
  12. Death
  13. Death cause

- If cancellation is requested, function returns NULL immediately
- Prevents unnecessary database queries after cancellation

#### Updated Documentation
- Added `@param cancel_check` documentation
- Updated `@return` to note NULL return on cancellation
- Added note about cancellation support in description

## How It Works

1. **User clicks "Load Patient"**
   - Cancellation flag is reset to FALSE
   - Modal dialog appears with Cancel button

2. **During Loading**
   - Between each database query, the cancellation flag is checked
   - If user clicks Cancel button, flag is set to TRUE
   - Next cancellation check causes `load_patient_data()` to return NULL

3. **After Loading (or Cancellation)**
   - Modal is removed
   - If cancelled: no data is processed, user sees cancellation message
   - If successful: data is processed normally

## Benefits

1. **Responsive**: Checks between queries, not just at the end
2. **Clean**: Prevents wasted processing of data after cancellation
3. **User-Friendly**: Clear UI with modal dialog and cancel button
4. **Backwards Compatible**: Optional parameter doesn't break existing usage
5. **Safe**: Proper cleanup of UI and state on cancellation or error

## Usage Examples

### In Shiny App (Automatic)
The cancellation is automatically available in the UI when users click "Load Patient". No changes needed to use it.

### Programmatic Usage
```r
# Without cancellation (backwards compatible)
data <- load_patient_data(conns, "PAT001")

# With cancellation callback
cancel_flag <- FALSE
data <- load_patient_data(
  conns,
  "PAT001",
  cancel_check = function() cancel_flag
)
# Set cancel_flag <- TRUE to cancel during loading
```

## Testing Recommendations

1. Test with small patient datasets (should complete quickly)
2. Test with large patient datasets (should be cancellable mid-load)
3. Test cancellation at different points during load
4. Verify no data corruption if cancelled
5. Verify proper cleanup of UI elements
6. Test error handling still works correctly

## Future Enhancements

Possible improvements for future versions:
- Progress indicator showing which table is currently loading
- Percentage complete indicator
- Ability to resume cancelled loads
- Timeout settings for automatic cancellation
- Loading statistics (rows loaded per table)
