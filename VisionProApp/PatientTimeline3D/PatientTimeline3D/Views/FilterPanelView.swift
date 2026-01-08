import SwiftUI

/// Filter controls for the patient timeline
struct FilterPanelView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showAdvancedFilters = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Event Type Filters
            eventTypeSection

            Divider()

            // Date Range Filter
            dateRangeSection

            // Advanced Filters (collapsible)
            DisclosureGroup("Advanced Filters", isExpanded: $showAdvancedFilters) {
                advancedFiltersSection
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Event Type Section

    private var eventTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Event Types")
                    .font(.headline)

                Spacer()

                Button("All") {
                    appModel.selectAllEventTypes()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("None") {
                    appModel.clearEventTypes()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(EventType.allCases) { eventType in
                    EventTypeToggle(
                        eventType: eventType,
                        isSelected: appModel.selectedEventTypes.contains(eventType),
                        count: appModel.eventCountByType(eventType)
                    ) {
                        appModel.toggleEventType(eventType)
                    }
                }
            }
        }
    }

    // MARK: - Date Range Section

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date Range")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("From")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { appModel.startDateFilter ?? appModel.dateRange?.lowerBound ?? Date() },
                            set: { appModel.startDateFilter = $0; appModel.applyFilters() }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("To")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { appModel.endDateFilter ?? appModel.dateRange?.upperBound ?? Date() },
                            set: { appModel.endDateFilter = $0; appModel.applyFilters() }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }

                Button(action: {
                    appModel.startDateFilter = nil
                    appModel.endDateFilter = nil
                    appModel.applyFilters()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity((appModel.startDateFilter != nil || appModel.endDateFilter != nil) ? 1 : 0)
            }
        }
    }

    // MARK: - Advanced Filters Section

    private var advancedFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search text filter
            VStack(alignment: .leading, spacing: 4) {
                Text("Search")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search events...", text: $appModel.searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: appModel.searchText) { _, _ in
                            appModel.applyFilters()
                        }

                    if !appModel.searchText.isEmpty {
                        Button(action: {
                            appModel.searchText = ""
                            appModel.applyFilters()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }

            // Quick date range buttons
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Range")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    QuickRangeButton(title: "1Y") {
                        setDateRange(years: -1)
                    }
                    QuickRangeButton(title: "3Y") {
                        setDateRange(years: -3)
                    }
                    QuickRangeButton(title: "5Y") {
                        setDateRange(years: -5)
                    }
                    QuickRangeButton(title: "All") {
                        appModel.startDateFilter = nil
                        appModel.endDateFilter = nil
                        appModel.applyFilters()
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helper Methods

    private func setDateRange(years: Int) {
        let today = Date()
        appModel.startDateFilter = Calendar.current.date(byAdding: .year, value: years, to: today)
        appModel.endDateFilter = today
        appModel.applyFilters()
    }
}

// MARK: - Supporting Views

struct EventTypeToggle: View {
    let eventType: EventType
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: eventType.icon)
                    .font(.caption)

                Text(eventType.displayName)
                    .font(.caption)
                    .lineLimit(1)

                if count > 0 {
                    Text("(\(count))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? TimelineColors.color(for: eventType).opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? TimelineColors.color(for: eventType) : .secondary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? TimelineColors.color(for: eventType) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct QuickRangeButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    FilterPanelView()
        .environmentObject(AppModel())
        .frame(width: 600)
        .padding()
}
