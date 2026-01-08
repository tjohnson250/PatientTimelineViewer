import SwiftUI
import RealityKit

/// Patient Timeline 3D - A visionOS app for viewing patient medical history in immersive 3D space
@main
struct PatientTimeline3DApp: App {
    @State private var immersionStyle: ImmersionStyle = .mixed
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        // Main window with patient selection and controls
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)

        // Immersive 3D timeline space
        ImmersiveSpace(id: "ImmersiveTimeline") {
            ImmersiveView()
                .environmentObject(appModel)
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .progressive, .full)
    }
}

/// Main application state model
@MainActor
class AppModel: ObservableObject {
    @Published var currentPatient: Patient?
    @Published var timelineEvents: [TimelineEvent] = []
    @Published var filteredEvents: [TimelineEvent] = []
    @Published var selectedEvent: TimelineEvent?
    @Published var isImmersiveSpaceOpen = false
    @Published var isLoading = false

    // Filter state
    @Published var selectedEventTypes: Set<EventType> = Set(EventType.allCases)
    @Published var startDateFilter: Date?
    @Published var endDateFilter: Date?
    @Published var searchText: String = ""

    // 3D layout settings
    @Published var timelineRadius: Float = 2.0  // Distance from user
    @Published var timelineHeight: Float = 0.0  // Vertical offset
    @Published var eventSpacing: Float = 0.1    // Space between events

    private let dataService = PatientDataService()

    /// Load patient data by ID
    func loadPatient(patientId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let patient = try await dataService.fetchPatient(patientId: patientId)
            currentPatient = patient
            timelineEvents = try await dataService.fetchTimelineEvents(patientId: patientId)
            applyFilters()
        } catch {
            print("Error loading patient: \(error)")
        }
    }

    /// Apply all active filters to timeline events
    func applyFilters() {
        var events = timelineEvents

        // Filter by event type
        events = events.filter { selectedEventTypes.contains($0.eventType) }

        // Filter by date range
        if let start = startDateFilter {
            events = events.filter { $0.startDate >= start }
        }
        if let end = endDateFilter {
            events = events.filter { $0.startDate <= end }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            events = events.filter { event in
                event.content.lowercased().contains(searchLower) ||
                event.details.values.joined().lowercased().contains(searchLower)
            }
        }

        filteredEvents = events.sorted { $0.startDate < $1.startDate }
    }

    /// Toggle event type filter
    func toggleEventType(_ type: EventType) {
        if selectedEventTypes.contains(type) {
            selectedEventTypes.remove(type)
        } else {
            selectedEventTypes.insert(type)
        }
        applyFilters()
    }

    /// Select all event types
    func selectAllEventTypes() {
        selectedEventTypes = Set(EventType.allCases)
        applyFilters()
    }

    /// Clear all event type selections
    func clearEventTypes() {
        selectedEventTypes.removeAll()
        applyFilters()
    }

    /// Reset all filters
    func resetFilters() {
        selectedEventTypes = Set(EventType.allCases)
        startDateFilter = nil
        endDateFilter = nil
        searchText = ""
        applyFilters()
    }

    /// Get event counts by type
    func eventCountByType(_ type: EventType) -> Int {
        timelineEvents.filter { $0.eventType == type }.count
    }

    /// Get date range for loaded patient
    var dateRange: ClosedRange<Date>? {
        guard let minDate = timelineEvents.map({ $0.startDate }).min(),
              let maxDate = timelineEvents.map({ $0.endDate ?? $0.startDate }).max() else {
            return nil
        }
        return minDate...maxDate
    }
}
