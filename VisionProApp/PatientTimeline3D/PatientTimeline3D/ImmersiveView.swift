import SwiftUI
import RealityKit
import Combine

/// The immersive 3D timeline experience
/// Events are arranged in a cylinder around the user, organized by date (angle) and type (radius/height)
struct ImmersiveView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var timelineRoot: Entity?
    @State private var eventEntities: [String: TimelineEventEntity] = [:]
    @State private var hoveredEventId: String?

    var body: some View {
        RealityView { content in
            // Create the root entity for the timeline
            let root = Entity()
            root.name = "TimelineRoot"
            content.add(root)
            timelineRoot = root

            // Build the initial timeline
            await buildTimeline(in: root)
        } update: { content in
            // Update when filtered events change
            Task {
                await updateTimeline()
            }
        }
        .gesture(tapGesture)
        .gesture(hoverGesture)
        .onChange(of: appModel.filteredEvents) { _, _ in
            Task {
                await updateTimeline()
            }
        }
        .onChange(of: appModel.timelineRadius) { _, _ in
            Task {
                await rebuildTimeline()
            }
        }
        .onChange(of: appModel.timelineHeight) { _, _ in
            Task {
                await updateTimelinePosition()
            }
        }
    }

    // MARK: - Timeline Construction

    @MainActor
    private func buildTimeline(in root: Entity) async {
        guard appModel.currentPatient != nil else { return }

        // Clear existing
        root.children.removeAll()
        eventEntities.removeAll()

        // Get date range
        guard let dateRange = appModel.dateRange else { return }

        // Create timeline axis
        let axis = TimelineAxisEntity(
            startDate: dateRange.lowerBound,
            endDate: dateRange.upperBound,
            radius: appModel.timelineRadius
        )
        axis.position.y = appModel.timelineHeight
        root.addChild(axis)

        // Add birth marker if available
        if let birthDate = appModel.currentPatient?.birthDate {
            let birthAngle = calculateAngle(for: birthDate, in: dateRange)
            let birthMarker = LifeMarkerEntity(
                type: .birth,
                angle: birthAngle,
                radius: appModel.timelineRadius
            )
            birthMarker.position.y += appModel.timelineHeight
            root.addChild(birthMarker)
        }

        // Add death marker if available
        if let deathDate = appModel.currentPatient?.deathDate {
            let deathAngle = calculateAngle(for: deathDate, in: dateRange)
            let deathMarker = LifeMarkerEntity(
                type: .death,
                angle: deathAngle,
                radius: appModel.timelineRadius
            )
            deathMarker.position.y += appModel.timelineHeight
            root.addChild(deathMarker)
        }

        // Add event entities
        await addEventEntities(to: root, dateRange: dateRange)
    }

    @MainActor
    private func addEventEntities(to root: Entity, dateRange: ClosedRange<Date>) async {
        for event in appModel.filteredEvents {
            let entity: TimelineEventEntity

            if event.isRangeEvent, let endDate = event.endDate {
                // Range events get horizontal arcs
                let startAngle = calculateAngle(for: event.startDate, in: dateRange)
                let endAngle = calculateAngle(for: endDate, in: dateRange)

                // Calculate radius and height based on event type
                let typeOffset = Float(event.eventType.groupIndex) * 0.15
                let radius = appModel.timelineRadius + typeOffset
                let heightPerGroup: Float = 0.08
                let height = Float(event.eventType.groupIndex) * heightPerGroup - 0.3 + appModel.timelineHeight

                entity = TimelineEventEntity(
                    event: event,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    radius: radius,
                    height: height
                )
            } else {
                // Point events get spheres
                let position = calculatePosition(for: event, in: dateRange)
                entity = TimelineEventEntity(event: event, position: position)
                entity.position.y += appModel.timelineHeight
            }

            eventEntities[event.id] = entity
            root.addChild(entity)
        }
    }

    @MainActor
    private func updateTimeline() async {
        guard let root = timelineRoot else { return }
        guard let dateRange = appModel.dateRange else { return }

        // Get current event IDs
        let currentEventIds = Set(appModel.filteredEvents.map { $0.id })
        let existingEventIds = Set(eventEntities.keys)

        // Remove entities for events no longer in filtered list
        for eventId in existingEventIds.subtracting(currentEventIds) {
            if let entity = eventEntities[eventId] {
                entity.removeFromParent()
                eventEntities.removeValue(forKey: eventId)
            }
        }

        // Add entities for new events
        for event in appModel.filteredEvents where !existingEventIds.contains(event.id) {
            let entity: TimelineEventEntity

            if event.isRangeEvent, let endDate = event.endDate {
                // Range events get horizontal arcs
                let startAngle = calculateAngle(for: event.startDate, in: dateRange)
                let endAngle = calculateAngle(for: endDate, in: dateRange)

                let typeOffset = Float(event.eventType.groupIndex) * 0.15
                let radius = appModel.timelineRadius + typeOffset
                let heightPerGroup: Float = 0.08
                let height = Float(event.eventType.groupIndex) * heightPerGroup - 0.3 + appModel.timelineHeight

                entity = TimelineEventEntity(
                    event: event,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    radius: radius,
                    height: height
                )
            } else {
                // Point events get spheres
                let position = calculatePosition(for: event, in: dateRange)
                entity = TimelineEventEntity(event: event, position: position)
                entity.position.y += appModel.timelineHeight
            }

            eventEntities[event.id] = entity
            root.addChild(entity)
        }

        // Update selection state
        for (eventId, entity) in eventEntities {
            entity.isSelected = appModel.selectedEvent?.id == eventId
        }
    }

    @MainActor
    private func rebuildTimeline() async {
        guard let root = timelineRoot else { return }
        await buildTimeline(in: root)
    }

    @MainActor
    private func updateTimelinePosition() async {
        guard let root = timelineRoot else { return }

        // Update Y position of all children
        for child in root.children {
            if child.name == "TimelineAxis" || child.name == "BirthMarker" || child.name == "DeathMarker" {
                child.position.y = appModel.timelineHeight
            } else if let eventEntity = child as? TimelineEventEntity,
                      let event = eventEntity.timelineEvent,
                      let dateRange = appModel.dateRange {
                let position = calculatePosition(for: event, in: dateRange)
                child.position = SIMD3<Float>(position.x, position.y + appModel.timelineHeight, position.z)
            }
        }
    }

    // MARK: - Position Calculations

    /// Calculate the angle for a date on the circular timeline
    private func calculateAngle(for date: Date, in dateRange: ClosedRange<Date>) -> Float {
        let totalSeconds = dateRange.upperBound.timeIntervalSince(dateRange.lowerBound)
        let elapsedSeconds = date.timeIntervalSince(dateRange.lowerBound)
        let progress = Float(elapsedSeconds / totalSeconds)

        // Map to full circle, starting from front (-Z direction, which is angle = 0)
        return progress * 2 * .pi - .pi / 2
    }

    /// Calculate 3D position for an event
    /// - Date determines the angle around the user
    /// - Event type determines the height layer
    /// - Range events get offset slightly outward
    private func calculatePosition(for event: TimelineEvent, in dateRange: ClosedRange<Date>) -> TimelinePosition {
        let angle = calculateAngle(for: event.startDate, in: dateRange)

        // Calculate radius based on event type (inner to outer rings)
        let typeOffset = Float(event.eventType.groupIndex) * 0.15
        let radius = appModel.timelineRadius + typeOffset

        // Calculate height based on event type (stacked layers)
        let heightPerGroup: Float = 0.08
        let baseHeight = Float(event.eventType.groupIndex) * heightPerGroup - 0.3

        // Add small random offset to prevent exact overlaps
        let jitterX = Float.random(in: -0.02...0.02)
        let jitterY = Float.random(in: -0.01...0.01)
        let jitterZ = Float.random(in: -0.02...0.02)

        var position = TimelinePosition.fromCylindrical(
            angle: angle,
            radius: radius,
            height: baseHeight
        )

        return TimelinePosition(
            x: position.x + jitterX,
            y: position.y + jitterY,
            z: position.z + jitterZ,
            angle: angle
        )
    }

    // MARK: - Gestures

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                handleTap(on: value.entity)
            }
    }

    private var hoverGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                // This is a workaround - in a real app you'd use hover effects
                handleHover(on: value.entity)
            }
    }

    @MainActor
    private func handleTap(on entity: Entity) {
        // Find the TimelineEventEntity in the hierarchy
        var current: Entity? = entity
        while let entity = current {
            if let eventEntity = entity as? TimelineEventEntity,
               let event = eventEntity.timelineEvent {
                // Toggle selection
                if appModel.selectedEvent?.id == event.id {
                    appModel.selectedEvent = nil
                } else {
                    appModel.selectedEvent = event
                }

                // Update all entities' selection state
                for (_, e) in eventEntities {
                    e.isSelected = appModel.selectedEvent?.id == e.timelineEvent?.id
                }
                return
            }
            current = entity.parent
        }
    }

    @MainActor
    private func handleHover(on entity: Entity) {
        var current: Entity? = entity
        while let entity = current {
            if let eventEntity = entity as? TimelineEventEntity {
                eventEntity.isHovered = true
                hoveredEventId = eventEntity.timelineEvent?.id

                // Reset other hovers
                for (id, e) in eventEntities where id != hoveredEventId {
                    e.isHovered = false
                }
                return
            }
            current = entity.parent
        }
    }
}

// MARK: - Preview

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environmentObject(AppModel())
}
