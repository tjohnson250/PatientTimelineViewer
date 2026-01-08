# Patient Timeline 3D - Apple Vision Pro App

An immersive visionOS application for visualizing patient medical history in 3D space. This app is a companion to the R Shiny Patient Timeline Viewer, re-imagined for Apple Vision Pro's spatial computing environment.

## Overview

Patient Timeline 3D displays patient medical events arranged around you in 3D space:

- **Cylindrical Timeline**: Events are arranged in a cylinder around the user
- **Time as Angle**: Earlier events start at the front, progressing clockwise around you
- **Event Types as Layers**: Different event types (encounters, diagnoses, labs, etc.) are displayed at different heights and radii
- **Interactive**: Tap events to see details, filter by type, date range, and search

## Features

### Immersive 3D Visualization
- Events float in space around you at comfortable viewing distances
- Color-coded by event type (matching the original app's color scheme)
- Abnormal results highlighted with special indicators
- Birth and death markers displayed as vertical reference lines

### Event Types Supported
- **Encounters** (Blue) - Hospital stays, ER visits, office visits
- **Diagnoses** (Coral) - ICD-10 coded diagnoses
- **Procedures** (Purple) - CPT coded procedures
- **Labs** (Green) - Laboratory results with abnormal flags
- **Prescriptions** (Orange) - Medication prescriptions
- **Dispensing** (Amber) - Pharmacy dispensing events
- **Vitals** (Teal) - Blood pressure, heart rate, weight
- **Conditions** (Pink) - Chronic conditions
- **Death** (Dark Gray) - Mortality information

### Filtering & Controls
- Toggle event types on/off
- Date range filtering
- Text search across all event content
- Quick range buttons (1Y, 3Y, 5Y, All)
- Adjustable timeline radius (distance from user)
- Adjustable vertical position

### Spatial Interaction
- **Tap** events to view detailed information
- **Gaze** at events for hover highlighting
- **Windows** float alongside the immersive view for controls

## Requirements

- macOS with Xcode 15.0+
- visionOS 1.0+ SDK
- Apple Vision Pro device or Simulator

## Building the App

1. Open `PatientTimeline3D.xcodeproj` in Xcode
2. Select the visionOS Simulator or your Vision Pro device
3. Build and run (⌘R)

## Project Structure

```
PatientTimeline3D/
├── PatientTimeline3DApp.swift    # Main app entry point
├── ContentView.swift              # 2D window UI
├── ImmersiveView.swift            # 3D immersive timeline
├── Models/
│   ├── TimelineModels.swift       # Data models (Patient, TimelineEvent)
│   ├── ColorScheme.swift          # Event type colors
│   └── MockData.swift             # Sample data generator
├── Views/
│   ├── Timeline3DView.swift       # Volumetric preview
│   ├── FilterPanelView.swift      # Filter controls
│   └── EventDetailView.swift      # Event details panel
├── Services/
│   └── PatientDataService.swift   # Data fetching (mock/API)
├── Entities/
│   └── TimelineEntity.swift       # RealityKit entities
└── Assets.xcassets/               # App icons and colors
```

## Data Architecture

### Current Implementation
The app uses **mock data** that generates realistic PCORnet CDM-style patient records. This is suitable for:
- Development and testing
- Demonstrations
- Offline use

### Production Integration
To connect to a real data source, modify `PatientDataService.swift`:

```swift
// Initialize with API endpoint
let service = PatientDataService(
    dataSource: .api(baseURL: URL(string: "https://your-api.com")!)
)
```

The API should provide endpoints:
- `GET /patients/{id}` - Patient demographics
- `GET /patients/{id}/timeline` - Timeline events

## 3D Layout Algorithm

Events are positioned using cylindrical coordinates:

1. **Angle (θ)**: Determined by event date
   - Date range maps to 0-2π radians
   - Starts at front (-π/2), progresses clockwise

2. **Radius (r)**: Base radius + event type offset
   - Each event type has a slight offset to prevent overlap
   - User can adjust base radius (1.5m - 4.0m)

3. **Height (y)**: Based on event type group
   - Event types are stacked vertically
   - Small jitter added to prevent exact overlaps

## Color Scheme

Colors match the original R Shiny application:

| Event Type | Hex Color | Description |
|------------|-----------|-------------|
| Encounter | #3498db | Blue |
| Diagnosis | #e74c3c | Coral |
| Procedure | #9b59b6 | Purple |
| Lab | #27ae60 | Green |
| Prescribing | #e67e22 | Orange |
| Dispensing | #f39c12 | Amber |
| Vital | #1abc9c | Teal |
| Condition | #e91e63 | Pink |
| Death | #2c3e50 | Dark Gray |

## Future Enhancements

- [ ] Hand gesture support for timeline navigation
- [ ] Voice commands for filtering
- [ ] Multi-patient comparison view
- [ ] Timeline animation (play through time)
- [ ] Export selected events
- [ ] SharePlay for collaborative review
- [ ] Integration with Apple Health records

## License

This project is part of the Patient Timeline Viewer suite.

## Related Projects

- [Patient Timeline Viewer](../) - Original R Shiny web application
