// timeline-overview.js
// SVG minimap overview below the main timeline with draggable/resizable viewport

(function() {
  'use strict';

  var overviewInitialized = false;
  var svgNS = 'http://www.w3.org/2000/svg';

  // State
  var fullMin = null;     // Date - earliest event
  var fullMax = null;     // Date - latest event
  var svgWidth = 0;
  var svgHeight = 60;     // Content area height (excluding time axis)
  var axisHeight = 18;    // Height for the time axis labels
  var totalHeight = 78;   // svgHeight + axisHeight
  var minViewportWidth = 8; // Minimum draggable viewport width in px

  // Drag state (viewport)
  var isDragging = false;
  var isResizingLeft = false;
  var isResizingRight = false;
  var dragStartX = 0;
  var dragStartVpX = 0;
  var dragStartVpW = 0;

  // Filter range state
  var filterStartDate = null;   // Date or null (full range)
  var filterEndDate = null;     // Date or null (full range)
  var filterRangeIsActive = false;
  var isFilterDraggingLeft = false;
  var isFilterDraggingRight = false;
  var filterDragStartX = 0;
  var filterDragStartLeft = 0;
  var filterDragStartRight = 0;
  var filterUpdateFromR = false; // Guard flag: R→JS update in progress

  // DOM references
  var overviewSvg = null;
  var eventsGroup = null;
  var viewportRect = null;
  var leftHandle = null;
  var rightHandle = null;
  var dimLeft = null;
  var dimRight = null;
  var axisGroup = null;

  // Filter range DOM references
  var filterDimLeft = null;
  var filterDimRight = null;
  var filterBand = null;
  var filterLeftHandle = null;
  var filterRightHandle = null;

  // Color map matching CSS custom properties
  var colorMap = {
    'event-encounter': '#3498db',
    'event-diagnosis': '#e74c3c',
    'event-procedure': '#9b59b6',
    'event-lab': '#27ae60',
    'event-lab-abnormal': '#e74c3c',
    'event-prescribing': '#e67e22',
    'event-dispensing': '#f39c12',
    'event-vital': '#1abc9c',
    'event-condition': '#e91e63',
    'event-death': '#2c3e50'
  };

  // Group ordering for Y-position
  var groupOrder = [
    'encounters', 'diagnoses', 'procedures', 'labs',
    'prescribing', 'dispensing', 'vitals', 'conditions'
  ];

  // ---- Coordinate mapping ----

  function dateToX(date, minD, maxD, width) {
    var totalMs = maxD.getTime() - minD.getTime();
    if (totalMs <= 0) return width / 2;
    var offsetMs = date.getTime() - minD.getTime();
    return (offsetMs / totalMs) * width;
  }

  function xToDate(x, minD, maxD, width) {
    var totalMs = maxD.getTime() - minD.getTime();
    return new Date(minD.getTime() + (x / width) * totalMs);
  }

  // ---- SVG helpers ----

  function createSvgElement(tag, attrs) {
    var el = document.createElementNS(svgNS, tag);
    for (var k in attrs) {
      if (attrs.hasOwnProperty(k)) {
        el.setAttribute(k, attrs[k]);
      }
    }
    return el;
  }

  // ---- Time axis rendering ----

  function renderTimeAxis() {
    if (!axisGroup || !fullMin || !fullMax) return;
    axisGroup.innerHTML = '';

    var rangeMs = fullMax.getTime() - fullMin.getTime();
    if (rangeMs <= 0) return;

    // Determine appropriate tick interval
    var rangeDays = rangeMs / (1000 * 60 * 60 * 24);
    var tickIntervalMs;
    var formatFn;

    if (rangeDays <= 60) {
      // Under 2 months: tick every week
      tickIntervalMs = 7 * 24 * 60 * 60 * 1000;
      formatFn = function(d) {
        return (d.getMonth() + 1) + '/' + d.getDate();
      };
    } else if (rangeDays <= 365) {
      // Under 1 year: tick every month
      tickIntervalMs = 30 * 24 * 60 * 60 * 1000;
      formatFn = function(d) {
        var months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
        return months[d.getMonth()] + ' ' + d.getFullYear().toString().slice(2);
      };
    } else if (rangeDays <= 3650) {
      // Under 10 years: tick every 6 months
      tickIntervalMs = 182 * 24 * 60 * 60 * 1000;
      formatFn = function(d) {
        var months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
        return months[d.getMonth()] + ' ' + d.getFullYear();
      };
    } else {
      // Over 10 years: tick every 2 years
      tickIntervalMs = 730 * 24 * 60 * 60 * 1000;
      formatFn = function(d) {
        return d.getFullYear().toString();
      };
    }

    // Generate ticks
    var maxTicks = 20;
    var tickCount = Math.min(maxTicks, Math.floor(rangeMs / tickIntervalMs));
    if (tickCount < 2) tickCount = 2;
    var actualInterval = rangeMs / tickCount;

    for (var i = 1; i < tickCount; i++) {
      var tickDate = new Date(fullMin.getTime() + i * actualInterval);
      var x = dateToX(tickDate, fullMin, fullMax, svgWidth);

      // Tick line
      axisGroup.appendChild(createSvgElement('line', {
        x1: x, x2: x,
        y1: svgHeight, y2: svgHeight + 4,
        stroke: '#95a5a6',
        'stroke-width': 1
      }));

      // Tick label
      var label = createSvgElement('text', {
        x: x, y: svgHeight + 14,
        'text-anchor': 'middle',
        'font-size': '9px',
        fill: '#7f8c8d',
        'font-family': 'inherit'
      });
      label.textContent = formatFn(tickDate);
      axisGroup.appendChild(label);
    }

    // Axis line
    axisGroup.appendChild(createSvgElement('line', {
      x1: 0, x2: svgWidth,
      y1: svgHeight, y2: svgHeight,
      stroke: '#dee2e6',
      'stroke-width': 1
    }));
  }

  // ---- Build the overview DOM ----

  function buildOverviewDOM() {
    var container = document.getElementById('timeline-overview-container');
    if (!container) return false;

    // Clear previous content
    container.innerHTML = '';

    overviewSvg = createSvgElement('svg', {
      id: 'overview-svg',
      width: '100%',
      height: totalHeight
    });
    container.appendChild(overviewSvg);

    // Background
    overviewSvg.appendChild(createSvgElement('rect', {
      x: 0, y: 0, width: '100%', height: svgHeight,
      fill: '#fdfdfe'
    }));

    // Events layer
    eventsGroup = createSvgElement('g', { class: 'overview-events' });
    overviewSvg.appendChild(eventsGroup);

    // Time axis layer
    axisGroup = createSvgElement('g', { class: 'overview-axis' });
    overviewSvg.appendChild(axisGroup);

    // Filter range dim overlays (areas outside filter range)
    filterDimLeft = createSvgElement('rect', {
      class: 'filter-dim', x: 0, y: 0, width: 0, height: svgHeight,
      fill: 'rgba(0,0,0,0.08)', 'pointer-events': 'none',
      opacity: 0
    });
    overviewSvg.appendChild(filterDimLeft);

    filterDimRight = createSvgElement('rect', {
      class: 'filter-dim', x: 0, y: 0, width: 0, height: svgHeight,
      fill: 'rgba(0,0,0,0.08)', 'pointer-events': 'none',
      opacity: 0
    });
    overviewSvg.appendChild(filterDimRight);

    // Filter range band
    filterBand = createSvgElement('rect', {
      class: 'filter-band',
      x: 0, y: 0, width: 0, height: svgHeight,
      fill: 'rgba(230, 126, 34, 0.12)',
      stroke: '#e67e22',
      'stroke-width': 1,
      'stroke-dasharray': '4,3',
      'pointer-events': 'none',
      opacity: 0,
      rx: 1, ry: 1
    });
    overviewSvg.appendChild(filterBand);

    // Viewport dim overlays (areas outside the viewport)
    dimLeft = createSvgElement('rect', {
      class: 'overview-dim', x: 0, y: 0, width: 0, height: svgHeight,
      fill: 'rgba(0,0,0,0.15)', 'pointer-events': 'none'
    });
    overviewSvg.appendChild(dimLeft);

    dimRight = createSvgElement('rect', {
      class: 'overview-dim', x: 0, y: 0, width: 0, height: svgHeight,
      fill: 'rgba(0,0,0,0.15)', 'pointer-events': 'none'
    });
    overviewSvg.appendChild(dimRight);

    // Viewport rectangle
    viewportRect = createSvgElement('rect', {
      class: 'overview-viewport',
      x: 0, y: 0, width: 100, height: svgHeight,
      fill: 'rgba(52, 152, 219, 0.08)',
      stroke: '#3498db',
      'stroke-width': 1.5,
      cursor: 'move',
      rx: 2, ry: 2
    });
    overviewSvg.appendChild(viewportRect);

    // Left viewport resize handle
    leftHandle = createSvgElement('rect', {
      class: 'overview-handle overview-handle-left',
      x: 0, y: 0, width: 6, height: svgHeight,
      fill: '#3498db',
      opacity: 0.6,
      cursor: 'ew-resize',
      rx: 2, ry: 2
    });
    overviewSvg.appendChild(leftHandle);

    // Right viewport resize handle
    rightHandle = createSvgElement('rect', {
      class: 'overview-handle overview-handle-right',
      x: 0, y: 0, width: 6, height: svgHeight,
      fill: '#3498db',
      opacity: 0.6,
      cursor: 'ew-resize',
      rx: 2, ry: 2
    });
    overviewSvg.appendChild(rightHandle);

    // Filter left handle (top portion only, so viewport handles remain grabbable below)
    filterLeftHandle = createSvgElement('rect', {
      class: 'filter-handle filter-handle-left',
      x: 0, y: 0, width: 8, height: 18,
      fill: '#e67e22',
      opacity: 0.7,
      cursor: 'ew-resize',
      rx: 2, ry: 2
    });
    overviewSvg.appendChild(filterLeftHandle);

    // Filter right handle (top portion only)
    filterRightHandle = createSvgElement('rect', {
      class: 'filter-handle filter-handle-right',
      x: 0, y: 0, width: 8, height: 18,
      fill: '#e67e22',
      opacity: 0.7,
      cursor: 'ew-resize',
      rx: 2, ry: 2
    });
    overviewSvg.appendChild(filterRightHandle);

    return true;
  }

  // ---- Render events as dots and lines ----

  function renderEvents() {
    if (!eventsGroup || !fullMin || !fullMax) return;
    eventsGroup.innerHTML = '';

    var widget = HTMLWidgets.find('#timeline');
    if (!widget || !widget.timeline) return;

    var items = widget.timeline.itemsData.get();
    if (!items || items.length === 0) return;

    var rowHeight = svgHeight / Math.max(groupOrder.length, 1);

    items.forEach(function(item) {
      if (!item.start) return;

      // Determine color from className
      var color = '#999';
      if (item.className) {
        var classes = item.className.split(/\s+/);
        for (var i = 0; i < classes.length; i++) {
          if (colorMap[classes[i]]) {
            color = colorMap[classes[i]];
            break;
          }
        }
      }

      // Determine Y position from group
      var groupIdx = groupOrder.indexOf(item.group);
      if (groupIdx === -1) groupIdx = groupOrder.length - 1;
      var y = (groupIdx + 0.5) * rowHeight;

      var startDate = new Date(item.start);
      var startX = dateToX(startDate, fullMin, fullMax, svgWidth);

      if (item.end && item.type === 'range') {
        // Range event: draw a horizontal line
        var endDate = new Date(item.end);
        var endX = dateToX(endDate, fullMin, fullMax, svgWidth);
        var lineWidth = Math.max(2, endX - startX); // At least 2px visible

        eventsGroup.appendChild(createSvgElement('line', {
          x1: startX, x2: startX + lineWidth,
          y1: y, y2: y,
          stroke: color,
          'stroke-width': 2,
          opacity: 0.7,
          'stroke-linecap': 'round'
        }));
      } else {
        // Point event: draw a dot
        eventsGroup.appendChild(createSvgElement('circle', {
          cx: startX, cy: y, r: 1.8,
          fill: color,
          opacity: 0.75
        }));
      }
    });
  }

  // ---- Viewport position/size helpers ----

  function getViewportX() {
    return parseFloat(viewportRect.getAttribute('x')) || 0;
  }

  function getViewportW() {
    return parseFloat(viewportRect.getAttribute('width')) || 50;
  }

  function updateViewportVisuals(x, w) {
    // Clamp
    x = Math.max(0, x);
    w = Math.max(minViewportWidth, w);
    if (x + w > svgWidth) {
      x = svgWidth - w;
      if (x < 0) { x = 0; w = svgWidth; }
    }

    viewportRect.setAttribute('x', x);
    viewportRect.setAttribute('width', w);

    leftHandle.setAttribute('x', x - 2);
    rightHandle.setAttribute('x', x + w - 4);

    // Update dim overlays
    dimLeft.setAttribute('x', 0);
    dimLeft.setAttribute('width', Math.max(0, x));

    dimRight.setAttribute('x', x + w);
    dimRight.setAttribute('width', Math.max(0, svgWidth - x - w));
  }

  // ---- Filter range position/size helpers ----

  function getFilterRangeX() {
    var left = parseFloat(filterLeftHandle.getAttribute('x')) + 4; // center of 8px handle
    var right = parseFloat(filterRightHandle.getAttribute('x')) + 4;
    return { left: left, right: right };
  }

  function updateFilterRangeVisuals(leftX, rightX) {
    // Clamp to SVG bounds
    leftX = Math.max(0, leftX);
    rightX = Math.min(svgWidth, rightX);
    if (rightX - leftX < 2) rightX = leftX + 2;

    // Check if filter covers full range (within 2px tolerance)
    var isFullRange = (leftX <= 2 && rightX >= svgWidth - 2);
    filterRangeIsActive = !isFullRange;

    // Update filter band
    filterBand.setAttribute('x', leftX);
    filterBand.setAttribute('width', rightX - leftX);
    filterBand.setAttribute('opacity', isFullRange ? 0 : 1);

    // Update filter dim overlays
    filterDimLeft.setAttribute('x', 0);
    filterDimLeft.setAttribute('width', Math.max(0, leftX));
    filterDimLeft.setAttribute('opacity', isFullRange ? 0 : 1);

    filterDimRight.setAttribute('x', rightX);
    filterDimRight.setAttribute('width', Math.max(0, svgWidth - rightX));
    filterDimRight.setAttribute('opacity', isFullRange ? 0 : 1);

    // Position filter handles (clamp so they stay within SVG bounds)
    filterLeftHandle.setAttribute('x', Math.max(0, leftX - 4));
    filterRightHandle.setAttribute('x', Math.min(svgWidth - 8, rightX - 4));

    // Always show handles (at edges when full range)
    filterLeftHandle.setAttribute('opacity', isFullRange ? 0.4 : 0.7);
    filterRightHandle.setAttribute('opacity', isFullRange ? 0.4 : 0.7);
  }

  function syncFilterRangeToState() {
    if (!fullMin || !fullMax) return;

    if (!filterStartDate || !filterEndDate) {
      // Full range
      updateFilterRangeVisuals(0, svgWidth);
    } else {
      var leftX = dateToX(filterStartDate, fullMin, fullMax, svgWidth);
      var rightX = dateToX(filterEndDate, fullMin, fullMax, svgWidth);
      updateFilterRangeVisuals(leftX, rightX);
    }
  }

  function sendFilterRangeToShiny(leftX, rightX) {
    if (filterUpdateFromR) return; // Guard: don't echo back R-initiated changes
    if (!fullMin || !fullMax) return;
    if (typeof Shiny === 'undefined' || !Shiny.setInputValue) return;

    var startDate = xToDate(leftX, fullMin, fullMax, svgWidth);
    var endDate = xToDate(rightX, fullMin, fullMax, svgWidth);

    // Check if this is effectively the full range
    var isFullRange = (leftX <= 2 && rightX >= svgWidth - 2);

    // Format dates as YYYY-MM-DD
    var formatDate = function(d) {
      var y = d.getFullYear();
      var m = ('0' + (d.getMonth() + 1)).slice(-2);
      var day = ('0' + d.getDate()).slice(-2);
      return y + '-' + m + '-' + day;
    };

    Shiny.setInputValue('filter_range_from_minimap', {
      start: formatDate(startDate),
      end: formatDate(endDate),
      isFullRange: isFullRange
    }, { priority: 'event' });
  }

  function syncViewportToMainTimeline() {
    var widget = HTMLWidgets.find('#timeline');
    if (!widget || !widget.timeline || !fullMin || !fullMax) return;

    var win = widget.timeline.getWindow();
    var x1 = dateToX(win.start, fullMin, fullMax, svgWidth);
    var x2 = dateToX(win.end, fullMin, fullMax, svgWidth);
    updateViewportVisuals(x1, x2 - x1);
  }

  function syncMainTimelineToViewport(x, w) {
    var widget = HTMLWidgets.find('#timeline');
    if (!widget || !widget.timeline || !fullMin || !fullMax) return;

    var newStart = xToDate(x, fullMin, fullMax, svgWidth);
    var newEnd = xToDate(x + w, fullMin, fullMax, svgWidth);
    widget.timeline.setWindow(newStart, newEnd, { animation: false });
  }

  // ---- Drag / resize interaction ----

  function attachInteraction() {
    // Viewport drag
    viewportRect.addEventListener('mousedown', function(e) {
      isDragging = true;
      dragStartX = e.clientX;
      dragStartVpX = getViewportX();
      dragStartVpW = getViewportW();
      document.body.style.cursor = 'move';
      document.body.style.userSelect = 'none';
      e.preventDefault();
      e.stopPropagation();
    });

    // Left handle resize
    leftHandle.addEventListener('mousedown', function(e) {
      isResizingLeft = true;
      dragStartX = e.clientX;
      dragStartVpX = getViewportX();
      dragStartVpW = getViewportW();
      document.body.style.cursor = 'ew-resize';
      document.body.style.userSelect = 'none';
      e.preventDefault();
      e.stopPropagation();
    });

    // Right viewport handle resize
    rightHandle.addEventListener('mousedown', function(e) {
      isResizingRight = true;
      dragStartX = e.clientX;
      dragStartVpX = getViewportX();
      dragStartVpW = getViewportW();
      document.body.style.cursor = 'ew-resize';
      document.body.style.userSelect = 'none';
      e.preventDefault();
      e.stopPropagation();
    });

    // Filter left handle drag
    filterLeftHandle.addEventListener('mousedown', function(e) {
      isFilterDraggingLeft = true;
      filterDragStartX = e.clientX;
      var pos = getFilterRangeX();
      filterDragStartLeft = pos.left;
      filterDragStartRight = pos.right;
      document.body.style.cursor = 'ew-resize';
      document.body.style.userSelect = 'none';
      e.preventDefault();
      e.stopPropagation();
    });

    // Filter right handle drag
    filterRightHandle.addEventListener('mousedown', function(e) {
      isFilterDraggingRight = true;
      filterDragStartX = e.clientX;
      var pos = getFilterRangeX();
      filterDragStartLeft = pos.left;
      filterDragStartRight = pos.right;
      document.body.style.cursor = 'ew-resize';
      document.body.style.userSelect = 'none';
      e.preventDefault();
      e.stopPropagation();
    });

    // Mousemove (document-level for smooth dragging outside SVG)
    document.addEventListener('mousemove', function(e) {
      var anyViewportDrag = isDragging || isResizingLeft || isResizingRight;
      var anyFilterDrag = isFilterDraggingLeft || isFilterDraggingRight;

      if (!anyViewportDrag && !anyFilterDrag) return;

      var dx = e.clientX - (anyFilterDrag ? filterDragStartX : dragStartX);

      if (isDragging) {
        var newX = Math.max(0, Math.min(dragStartVpX + dx, svgWidth - dragStartVpW));
        updateViewportVisuals(newX, dragStartVpW);
        syncMainTimelineToViewport(newX, dragStartVpW);
      } else if (isResizingLeft) {
        var newX = dragStartVpX + dx;
        var newW = dragStartVpW - dx;
        if (newW >= minViewportWidth && newX >= 0) {
          updateViewportVisuals(newX, newW);
          syncMainTimelineToViewport(newX, newW);
        }
      } else if (isResizingRight) {
        var newW = dragStartVpW + dx;
        if (newW >= minViewportWidth && dragStartVpX + newW <= svgWidth) {
          updateViewportVisuals(dragStartVpX, newW);
          syncMainTimelineToViewport(dragStartVpX, newW);
        }
      } else if (isFilterDraggingLeft) {
        var newLeft = Math.max(0, Math.min(filterDragStartLeft + dx, filterDragStartRight - 2));
        updateFilterRangeVisuals(newLeft, filterDragStartRight);
      } else if (isFilterDraggingRight) {
        var newRight = Math.max(filterDragStartLeft + 2, Math.min(filterDragStartRight + dx, svgWidth));
        updateFilterRangeVisuals(filterDragStartLeft, newRight);
      }
    });

    // Mouseup
    document.addEventListener('mouseup', function() {
      if (isDragging || isResizingLeft || isResizingRight) {
        isDragging = false;
        isResizingLeft = false;
        isResizingRight = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
      }
      if (isFilterDraggingLeft || isFilterDraggingRight) {
        var pos = getFilterRangeX();
        sendFilterRangeToShiny(pos.left, pos.right);
        isFilterDraggingLeft = false;
        isFilterDraggingRight = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
      }
    });

    // Click on background to jump viewport there
    overviewSvg.addEventListener('mousedown', function(e) {
      // Only handle clicks on the background (not viewport/handles)
      if (e.target === overviewSvg || e.target === overviewSvg.firstChild) {
        var rect = overviewSvg.getBoundingClientRect();
        var clickX = e.clientX - rect.left;
        var vpW = getViewportW();
        var newX = Math.max(0, Math.min(clickX - vpW / 2, svgWidth - vpW));
        updateViewportVisuals(newX, vpW);
        syncMainTimelineToViewport(newX, vpW);
      }
    });
  }

  // ---- Compute full date range from timeline items ----

  function computeDateRange() {
    var widget = HTMLWidgets.find('#timeline');
    if (!widget || !widget.timeline) return false;

    var items = widget.timeline.itemsData.get();
    if (!items || items.length === 0) return false;

    var minMs = Infinity;
    var maxMs = -Infinity;

    items.forEach(function(item) {
      if (item.start) {
        var d = new Date(item.start).getTime();
        if (d < minMs) minMs = d;
        if (d > maxMs) maxMs = d;
      }
      if (item.end) {
        var d = new Date(item.end).getTime();
        if (d > maxMs) maxMs = d;
      }
    });

    if (!isFinite(minMs) || !isFinite(maxMs)) return false;

    // Add 2% padding on each side
    var range = maxMs - minMs;
    var pad = Math.max(range * 0.02, 86400000); // at least 1 day
    fullMin = new Date(minMs - pad);
    fullMax = new Date(maxMs + pad);
    return true;
  }

  // ---- Measure SVG width ----

  function measureWidth() {
    if (!overviewSvg) return;
    var rect = overviewSvg.getBoundingClientRect();
    svgWidth = rect.width || overviewSvg.clientWidth || 800;
  }

  // ---- Main init ----

  function initOverview() {
    var container = document.getElementById('timeline-overview-container');
    if (!container) return;

    var widget = HTMLWidgets.find('#timeline');
    if (!widget || !widget.timeline) {
      // Retry - timeline not ready yet
      setTimeout(initOverview, 200);
      return;
    }

    // Build DOM
    if (!buildOverviewDOM()) return;

    // Measure width
    measureWidth();

    // Compute date range from items
    if (!computeDateRange()) return;

    // Render events
    renderEvents();

    // Render time axis
    renderTimeAxis();

    // Attach drag/resize interaction
    attachInteraction();

    // Sync viewport to current main timeline window
    syncViewportToMainTimeline();

    // Listen for main timeline range changes to keep viewport in sync
    widget.timeline.on('rangechange', function(props) {
      if (props.byUser || !isDragging) {
        syncViewportToMainTimeline();
      }
    });

    // Also sync after range change is done (rangechanged fires once at end)
    widget.timeline.on('rangechanged', function() {
      if (!isDragging && !isResizingLeft && !isResizingRight) {
        syncViewportToMainTimeline();
      }
    });

    // Initialize filter range to full extent
    filterStartDate = null;
    filterEndDate = null;
    filterRangeIsActive = false;
    updateFilterRangeVisuals(0, svgWidth);

    // Handle window resize
    var resizeTimeout;
    window.addEventListener('resize', function() {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(function() {
        measureWidth();
        renderEvents();
        renderTimeAxis();
        syncViewportToMainTimeline();
        syncFilterRangeToState();
      }, 150);
    });

    overviewInitialized = true;
  }

  // ---- Listen for timeline renders ----

  $(document).on('shiny:value', function(event) {
    if (event.name === 'timeline') {
      overviewInitialized = false;
      // Allow time for the timeline to fully render
      setTimeout(initOverview, 400);
    }
  });

  // Also try on document ready
  $(document).ready(function() {
    setTimeout(initOverview, 800);
  });

  // ---- Shiny custom message handlers ----

  // R → JS: Update filter range visuals from date inputs
  $(document).ready(function() {
    if (typeof Shiny !== 'undefined') {
      Shiny.addCustomMessageHandler('updateFilterRange', function(msg) {
        if (!overviewInitialized || !fullMin || !fullMax) return;

        filterUpdateFromR = true;

        if (msg.isFullRange) {
          filterStartDate = null;
          filterEndDate = null;
          updateFilterRangeVisuals(0, svgWidth);
        } else {
          filterStartDate = new Date(msg.start);
          filterEndDate = new Date(msg.end);
          var leftX = dateToX(filterStartDate, fullMin, fullMax, svgWidth);
          var rightX = dateToX(filterEndDate, fullMin, fullMax, svgWidth);
          updateFilterRangeVisuals(leftX, rightX);
        }

        // Reset guard after short delay
        setTimeout(function() {
          filterUpdateFromR = false;
        }, 50);
      });

      // R → JS: Filter to current viewport
      Shiny.addCustomMessageHandler('filterToView', function(msg) {
        if (!overviewInitialized || !fullMin || !fullMax) return;

        var vpX = getViewportX();
        var vpW = getViewportW();
        updateFilterRangeVisuals(vpX, vpX + vpW);

        // Send the filter range to R
        sendFilterRangeToShiny(vpX, vpX + vpW);
      });
    }
  });

})();
