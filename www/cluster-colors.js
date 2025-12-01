// cluster-colors.js
// Apply event type colors to clustered items

(function() {
  var setupDone = false;

  // Map group names to event type classes
  // Include both the group ID and the label text (content)
  var groupToEventClass = {
    'encounters': 'event-encounter',
    'diagnoses': 'event-diagnosis',
    'procedures': 'event-procedure',
    'labs': 'event-lab',
    'prescribing': 'event-prescribing',
    'prescriptions': 'event-prescribing',  // Label text for prescribing group
    'dispensing': 'event-dispensing',
    'vitals': 'event-vital',
    'conditions': 'event-condition'
  };

  // Function to apply cluster colors via DOM manipulation
  function applyClusterColorsDom() {
    // Find all cluster elements in the DOM
    var clusters = document.querySelectorAll('.vis-item.vis-cluster');
    console.log('DOM: Found', clusters.length, 'cluster elements');

    clusters.forEach(function(clusterElement) {
      // Remove any existing event-* classes first to avoid conflicts
      var existingClasses = clusterElement.className.split(' ');
      existingClasses.forEach(function(cls) {
        if (cls.startsWith('event-')) {
          clusterElement.classList.remove(cls);
        }
      });

      var groupName = null;

      // Method 1: Look for non-cluster items with same 'top' style value
      // Clusters and regular items in the same group have the same CSS top value
      var clusterTop = clusterElement.style.top;
      if (clusterTop) {
        var nonClusterItems = document.querySelectorAll('.vis-item:not(.vis-cluster)');
        for (var i = 0; i < nonClusterItems.length; i++) {
          var item = nonClusterItems[i];
          if (item.style.top === clusterTop) {
            // Found an item in the same row, get its event class
            var classes = item.className.split(' ');
            for (var j = 0; j < classes.length; j++) {
              if (classes[j].startsWith('event-')) {
                // Extract group name from event class
                var eventClass = classes[j];
                console.log('DOM: Found same-row item with class:', eventClass);

                // Reverse lookup: find group name from event class
                for (var grp in groupToEventClass) {
                  if (groupToEventClass[grp] === eventClass) {
                    groupName = grp;
                    console.log('DOM: Determined group:', groupName);
                    break;
                  }
                }
                break;
              }
            }
            if (groupName) break;
          }
        }
      }

      // Method 2: If still no group, try position-based detection with better logic
      if (!groupName) {
        var rect = clusterElement.getBoundingClientRect();
        var clusterCenterY = rect.top + (rect.height / 2);

        var labels = document.querySelectorAll('.vis-label');
        var closestLabel = null;
        var closestDistance = Infinity;

        labels.forEach(function(labelEl) {
          var labelRect = labelEl.getBoundingClientRect();
          var labelCenterY = labelRect.top + (labelRect.height / 2);
          var distance = Math.abs(labelCenterY - clusterCenterY);

          if (distance < closestDistance) {
            closestDistance = distance;
            closestLabel = labelEl;
          }
        });

        if (closestLabel) {
          var labelText = closestLabel.textContent.trim().toLowerCase();
          groupName = labelText;
          console.log('DOM: Found group via closest label:', groupName, 'distance:', closestDistance);
        }
      }

      // Apply the appropriate event class based on group
      if (groupName && groupToEventClass[groupName]) {
        console.log('DOM: Applying', groupToEventClass[groupName], 'to cluster');
        clusterElement.classList.add(groupToEventClass[groupName]);
        clusterElement.setAttribute('data-group', groupName);
      } else {
        console.log('DOM: Could not determine group for cluster (groupName:', groupName, ')');
      }
    });
  }

  // Function to apply cluster colors via data
  function applyClusterColors() {
    var widget = HTMLWidgets.find('#timeline');
    if (!widget || !widget.timeline) {
      // Fall back to DOM manipulation
      applyClusterColorsDom();
      return;
    }

    var timeline = widget.timeline;
    var items = timeline.itemsData.get();

    console.log('Applying cluster colors to', items.filter(function(i) { return i.isCluster; }).length, 'clusters');

    // Debug: Log some aggregated items
    var aggItems = items.filter(function(i) { return i.id && i.id.indexOf('AGG_') === 0; });
    if (aggItems.length > 0) {
      console.log('Found', aggItems.length, 'aggregated items. Sample:', aggItems.slice(0, 3).map(function(i) {
        return {id: i.id, group: i.group, className: i.className, content: i.content};
      }));
    }

    items.forEach(function(item) {
      if (item.isCluster) {
        // Get the group this cluster belongs to
        var group = item.group;
        console.log('Cluster', item.id, 'is in group:', group);

        // Determine className from group name
        var eventClass = null;
        if (group && groupToEventClass[group]) {
          eventClass = groupToEventClass[group];
          console.log('  -> Using mapping for group', group, ':', eventClass);
        } else {
          // Try to get from clustered items
          var clusterItems = item.items || (item.data && item.data.items) || [];
          console.log('  -> Cluster contains', clusterItems.length, 'items');
          if (clusterItems.length > 0) {
            var firstItemId = clusterItems[0];
            var firstItem = timeline.itemsData.get(firstItemId);
            if (firstItem) {
              eventClass = firstItem.className || '';
              group = firstItem.group || item.group;
              console.log('  -> Using first item className:', eventClass, 'group:', group);
            }
          }
        }

        // Update via itemsData if we found a className
        if (eventClass) {
          console.log('  -> Updating cluster', item.id, 'with className:', eventClass);
          timeline.itemsData.update({
            id: item.id,
            className: eventClass
          });
        } else {
          console.log('  -> WARNING: No className determined for cluster', item.id);
        }
      }
    });

    // Also apply DOM-based styling as backup, but wait longer to not override data updates
    setTimeout(applyClusterColorsDom, 200);
  }

  // Setup function
  function setup() {
    if (setupDone) return;

    setTimeout(function() {
      var widget = HTMLWidgets.find('#timeline');
      if (widget && widget.timeline) {
        setupDone = true;

        // Apply on various events
        widget.timeline.on('changed', applyClusterColors);
        widget.timeline.on('rangechanged', applyClusterColors);

        // Initial application
        applyClusterColors();
      }
    }, 300);
  }

  // Apply colors when timeline is rendered
  $(document).on('shiny:value', function(event) {
    if (event.name === 'timeline') {
      setupDone = false;
      setTimeout(setup, 100);
    }
  });

  // Also try on load
  $(document).ready(function() {
    setTimeout(setup, 500);
  });
})();
