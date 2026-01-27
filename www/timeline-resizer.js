// Timeline resizer - allows users to drag to resize the timeline pane
(function() {
  'use strict';

  var MIN_HEIGHT = 300;           // Minimum timeline height in pixels
  var MAX_HEIGHT_PERCENT = 80;    // Maximum height as % of viewport
  var isResizing = false;
  var startY = 0;
  var startHeight = 0;
  var resizerInitialized = false;

  function initResizer() {
    // Prevent multiple initializations
    if (resizerInitialized) return;

    var resizeHandle = document.getElementById('timeline-resize-handle');
    var timelineWrapper = document.getElementById('timeline-wrapper');

    if (!resizeHandle || !timelineWrapper) {
      // Timeline not ready yet, retry
      setTimeout(initResizer, 100);
      return;
    }

    resizerInitialized = true;

    // Mouse down on handle: Start resize
    resizeHandle.addEventListener('mousedown', function(e) {
      isResizing = true;
      startY = e.clientY;
      startHeight = timelineWrapper.offsetHeight;
      document.body.style.cursor = 'ns-resize';
      document.body.style.userSelect = 'none';
      e.preventDefault();
    });

    // Mouse move: Perform resize
    document.addEventListener('mousemove', function(e) {
      if (!isResizing) return;

      var deltaY = e.clientY - startY;
      var newHeight = startHeight + deltaY;

      // Apply constraints
      var maxHeight = window.innerHeight * (MAX_HEIGHT_PERCENT / 100);
      newHeight = Math.max(MIN_HEIGHT, Math.min(newHeight, maxHeight));

      // Update wrapper height
      timelineWrapper.style.height = newHeight + 'px';

      // Find and update the timevis container inside
      var timevisContainer = timelineWrapper.querySelector('.vis-timeline');
      if (timevisContainer) {
        timevisContainer.style.maxHeight = newHeight + 'px';
      }

      // Trigger timeline redraw using requestAnimationFrame for performance
      requestAnimationFrame(function() {
        var widget = HTMLWidgets.find('#timeline');
        if (widget && widget.timeline) {
          widget.timeline.redraw();
        }
      });
    });

    // Mouse up: End resize
    document.addEventListener('mouseup', function(e) {
      if (isResizing) {
        isResizing = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';

        // Get final height and send to Shiny
        var finalHeight = timelineWrapper.offsetHeight;
        if (window.Shiny && Shiny.setInputValue) {
          Shiny.setInputValue('timeline_height', finalHeight, {priority: 'event'});
        }

        // Final redraw to ensure clean state
        var widget = HTMLWidgets.find('#timeline');
        if (widget && widget.timeline) {
          widget.timeline.redraw();
        }
      }
    });
  }

  // Initialize when timeline renders
  $(document).on('shiny:value', function(event) {
    if (event.name === 'timeline') {
      // Reset initialization flag when timeline re-renders
      resizerInitialized = false;
      setTimeout(initResizer, 100);
    }
  });

  // Also try on document ready
  $(document).ready(function() {
    setTimeout(initResizer, 500);
  });
})();
