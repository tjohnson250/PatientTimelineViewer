// timeline-markers.js
// Add birth and death date vertical markers to the timeline

(function() {
  // Function to add custom time markers
  window.addTimelineMarkers = function(birthDate, deathDate) {
    var widget = HTMLWidgets.find('#timeline');
    if (!widget || !widget.timeline) {
      console.log('Timeline widget not found, retrying...');
      setTimeout(function() {
        window.addTimelineMarkers(birthDate, deathDate);
      }, 100);
      return;
    }

    var timeline = widget.timeline;

    // Remove existing markers first
    try {
      timeline.removeCustomTime('birth-marker');
    } catch(e) {}
    try {
      timeline.removeCustomTime('death-marker');
    } catch(e) {}

    // Add birth date marker if provided
    if (birthDate) {
      try {
        var birthDateTime = new Date(birthDate);
        timeline.addCustomTime(birthDateTime, 'birth-marker');
        // Format the date for display (YYYY-MM-DD)
        var birthDateFormatted = birthDateTime.toISOString().split('T')[0];
        timeline.setCustomTimeMarker('Birth: ' + birthDateFormatted, 'birth-marker', true);
        console.log('Added birth marker at:', birthDate);
      } catch(e) {
        console.error('Error adding birth marker:', e);
      }
    }

    // Add death date marker if provided
    if (deathDate) {
      try {
        var deathDateTime = new Date(deathDate);
        timeline.addCustomTime(deathDateTime, 'death-marker');
        // Format the date for display (YYYY-MM-DD)
        var deathDateFormatted = deathDateTime.toISOString().split('T')[0];
        timeline.setCustomTimeMarker('Death: ' + deathDateFormatted, 'death-marker', true);
        console.log('Added death marker at:', deathDate);
      } catch(e) {
        console.error('Error adding death marker:', e);
      }
    }
  };

  // Listen for Shiny messages to add markers
  if (window.Shiny) {
    Shiny.addCustomMessageHandler('addTimelineMarkers', function(data) {
      console.log('Received marker data:', data);
      window.addTimelineMarkers(data.birthDate, data.deathDate);
    });
  }
})();
