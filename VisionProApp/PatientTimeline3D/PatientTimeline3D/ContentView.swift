import SwiftUI
import RealityKit

/// Main content view - the 2D window interface for controlling the timeline
struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State private var patientIdInput: String = "SAMPLE_001"
    @State private var showingFilters: Bool = false

    var body: some View {
        NavigationSplitView {
            // Sidebar with patient info and controls
            sidebarContent
        } detail: {
            // Main content area
            if appModel.currentPatient != nil {
                patientDetailView
            } else {
                welcomeView
            }
        }
        .navigationTitle("Patient Timeline 3D")
    }

    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        List {
            // Patient Search Section
            Section("Patient") {
                HStack {
                    TextField("Patient ID", text: $patientIdInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Load") {
                        Task {
                            await appModel.loadPatient(patientId: patientIdInput)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(patientIdInput.isEmpty || appModel.isLoading)
                }

                if appModel.isLoading {
                    ProgressView("Loading patient data...")
                }
            }

            // Patient Demographics (when loaded)
            if let patient = appModel.currentPatient {
                Section("Demographics") {
                    LabeledContent("Patient ID", value: patient.patientId)
                    LabeledContent("Age", value: patient.ageDescription)
                    LabeledContent("Sex", value: patient.sexDescription)

                    if let race = patient.race {
                        LabeledContent("Race", value: race)
                    }

                    if let ethnicity = patient.ethnicity {
                        LabeledContent("Ethnicity", value: ethnicity)
                    }

                    if !patient.sourceSystems.isEmpty {
                        LabeledContent("Sources", value: patient.sourceSystems.joined(separator: ", "))
                    }
                }

                // Event Counts Section
                Section("Events (\(appModel.timelineEvents.count))") {
                    ForEach(EventType.allCases) { eventType in
                        let count = appModel.eventCountByType(eventType)
                        if count > 0 {
                            HStack {
                                Image(systemName: eventType.icon)
                                    .foregroundColor(TimelineColors.color(for: eventType))
                                Text(eventType.displayName)
                                Spacer()
                                Text("\(count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Immersive Space Control
            Section("3D View") {
                Toggle("Immersive Timeline", isOn: Binding(
                    get: { appModel.isImmersiveSpaceOpen },
                    set: { newValue in
                        Task {
                            if newValue {
                                await openImmersiveSpace(id: "ImmersiveTimeline")
                                appModel.isImmersiveSpaceOpen = true
                            } else {
                                await dismissImmersiveSpace()
                                appModel.isImmersiveSpaceOpen = false
                            }
                        }
                    }
                ))
                .disabled(appModel.currentPatient == nil)

                if appModel.isImmersiveSpaceOpen {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeline Radius")
                            .font(.caption)
                        Slider(value: $appModel.timelineRadius, in: 1.0...4.0, step: 0.5)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vertical Position")
                            .font(.caption)
                        Slider(value: $appModel.timelineHeight, in: -0.5...0.5, step: 0.1)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 300)
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            Text("Patient Timeline 3D")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Enter a Patient ID to view their medical history\nin immersive 3D space around you.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(maxWidth: 300)
                .padding(.vertical)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "bed.double.fill", color: TimelineColors.encounter, text: "View encounters and hospital stays")
                FeatureRow(icon: "cross.case.fill", color: TimelineColors.diagnosis, text: "Track diagnoses over time")
                FeatureRow(icon: "flask.fill", color: TimelineColors.lab, text: "Monitor lab results and trends")
                FeatureRow(icon: "pill.fill", color: TimelineColors.prescribing, text: "Review medication history")
                FeatureRow(icon: "heart.fill", color: TimelineColors.vital, text: "See vital signs patterns")
            }
            .padding()
            .background(.regularMaterial)
            .cornerRadius(12)

            Text("Try loading patient ID: SAMPLE_001")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Patient Detail View

    private var patientDetailView: some View {
        VStack {
            // Filter bar
            HStack {
                Button(action: { showingFilters.toggle() }) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\(appModel.filteredEvents.count) of \(appModel.timelineEvents.count) events")
                    .foregroundColor(.secondary)

                if appModel.filteredEvents.count != appModel.timelineEvents.count {
                    Button("Reset") {
                        appModel.resetFilters()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding()

            // Filter panel (collapsible)
            if showingFilters {
                FilterPanelView()
                    .environmentObject(appModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Event list or selected event detail
            if let selectedEvent = appModel.selectedEvent {
                EventDetailView(event: selectedEvent)
                    .environmentObject(appModel)
            } else {
                // Show 2D event list as backup when not in immersive mode
                eventListView
            }
        }
        .animation(.easeInOut, value: showingFilters)
    }

    // MARK: - Event List View

    private var eventListView: some View {
        List {
            ForEach(appModel.filteredEvents) { event in
                EventRowView(event: event)
                    .onTapGesture {
                        appModel.selectedEvent = event
                    }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .foregroundColor(.primary)
        }
    }
}

struct EventRowView: View {
    let event: TimelineEvent

    var body: some View {
        HStack {
            Circle()
                .fill(TimelineColors.color(for: event.eventType))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading) {
                Text(event.content)
                    .font(.headline)
                Text(event.dateDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: event.eventType.icon)
                .foregroundColor(TimelineColors.color(for: event.eventType))

            if event.isAbnormal {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(TimelineColors.abnormalIndicator)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(AppModel())
}
