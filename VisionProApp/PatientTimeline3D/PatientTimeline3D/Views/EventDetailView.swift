import SwiftUI

/// Detailed view of a selected timeline event
struct EventDetailView: View {
    let event: TimelineEvent
    @EnvironmentObject var appModel: AppModel
    @State private var showRelatedEvents = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection

                Divider()

                // Event details
                detailsSection

                // Related events (for encounters)
                if event.eventType == .encounter {
                    relatedEventsSection
                }

                Spacer()
            }
            .padding()
        }
        .background(.regularMaterial)
        .cornerRadius(16)
        .frame(maxWidth: 400)
        .padding()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Event type icon with color
            ZStack {
                Circle()
                    .fill(TimelineColors.color(for: event.eventType).opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: event.eventType.icon)
                    .font(.title2)
                    .foregroundColor(TimelineColors.color(for: event.eventType))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.content)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(event.eventType.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(event.dateDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Close button
            Button(action: {
                appModel.selectedEvent = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            ForEach(Array(event.details.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                DetailRow(label: key, value: value, isAbnormal: key == "Abnormal Flag" && !value.isEmpty)
            }

            // Source information
            Group {
                Divider()

                DetailRow(label: "Source Table", value: event.sourceTable, isAbnormal: false)
                DetailRow(label: "Source Key", value: event.sourceKey, isAbnormal: false)
                DetailRow(label: "Event ID", value: event.id, isAbnormal: false)
            }
        }
    }

    // MARK: - Related Events Section

    private var relatedEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Button(action: {
                showRelatedEvents.toggle()
                if showRelatedEvents {
                    filterToEncounterWindow()
                }
            }) {
                HStack {
                    Image(systemName: showRelatedEvents ? "eye.fill" : "eye")
                    Text(showRelatedEvents ? "Showing Related Events" : "Show Related Events")
                }
            }
            .buttonStyle(.bordered)
            .tint(TimelineColors.color(for: event.eventType))

            if showRelatedEvents {
                Text("Showing events from \(formatDate(event.startDate)) to \(formatDate(event.endDate ?? event.startDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Count of related events
                let relatedCount = countRelatedEvents()
                Text("\(relatedCount) events during this encounter")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helper Methods

    private func filterToEncounterWindow() {
        // Set date filters to encounter window with 1 day buffer
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -1, to: event.startDate) ?? event.startDate
        let endDate = calendar.date(byAdding: .day, value: 1, to: event.endDate ?? event.startDate) ?? event.startDate

        appModel.startDateFilter = startDate
        appModel.endDateFilter = endDate
        appModel.applyFilters()
    }

    private func countRelatedEvents() -> Int {
        guard let start = appModel.startDateFilter,
              let end = appModel.endDateFilter else {
            return 0
        }

        return appModel.timelineEvents.filter { event in
            event.startDate >= start && event.startDate <= end
        }.count
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    let isAbnormal: Bool

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.body)
                .foregroundColor(isAbnormal ? TimelineColors.abnormalIndicator : .primary)

            if isAbnormal {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(TimelineColors.abnormalIndicator)
                    .font(.caption)
            }

            Spacer()
        }
    }
}

// MARK: - Event Card View

/// Compact card view for events in a list
struct EventCardView: View {
    let event: TimelineEvent
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Color indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(TimelineColors.color(for: event.eventType))
                    .frame(width: 4)

                // Event info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: event.eventType.icon)
                            .font(.caption)
                            .foregroundColor(TimelineColors.color(for: event.eventType))

                        Text(event.content)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        if event.isAbnormal {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(TimelineColors.abnormalIndicator)
                        }
                    }

                    Text(event.dateDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Duration badge for range events
                if let duration = event.durationDays, duration > 0 {
                    Text("\(duration)d")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? TimelineColors.color(for: event.eventType).opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Aggregated Event Detail View

/// Detail view for aggregated events showing multiple items
struct AggregatedEventDetailView: View {
    let aggregatedEvent: AggregatedEvent
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(TimelineColors.color(for: aggregatedEvent.eventType).opacity(0.2))
                        .frame(width: 50, height: 50)

                    Text("\(aggregatedEvent.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(TimelineColors.color(for: aggregatedEvent.eventType))
                }

                VStack(alignment: .leading) {
                    Text(aggregatedEvent.content)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(aggregatedEvent.date.formatted(style: .medium))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // List of contained events
            Text("Events")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(aggregatedEvent.events) { event in
                        EventCardView(
                            event: event,
                            isSelected: appModel.selectedEvent?.id == event.id
                        ) {
                            appModel.selectedEvent = event
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}

// MARK: - Preview

#Preview {
    EventDetailView(event: MockDataGenerator.sampleEvents.first!)
        .environmentObject(AppModel())
}
