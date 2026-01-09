import RealityKit
import SwiftUI

/// Custom RealityKit entity for timeline events in 3D space
class TimelineEventEntity: Entity, HasModel, HasCollision {

    /// The timeline event this entity represents
    var timelineEvent: TimelineEvent?

    /// Start angle for range events (stored for arc rendering)
    var startAngle: Float = 0

    /// End angle for range events (stored for arc rendering)
    var endAngle: Float = 0

    /// Radius from center (stored for arc rendering)
    var arcRadius: Float = 2.0

    /// Whether this entity is currently selected
    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    /// Whether this entity is being hovered
    var isHovered: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    // MARK: - Initialization

    required init() {
        super.init()
    }

    /// Create a timeline event entity for point events
    @MainActor
    convenience init(event: TimelineEvent, position: TimelinePosition) {
        self.init()
        self.timelineEvent = event
        self.name = event.id
        self.startAngle = position.angle
        self.arcRadius = sqrt(position.x * position.x + position.z * position.z)

        // Set position at center for point events
        self.position = SIMD3<Float>(position.x, position.y, position.z)

        // Create the visual representation
        setupPointVisuals(for: event)

        // Add collision for interaction
        setupCollision(for: event)

        // Face the user (center of the space)
        self.look(at: .zero, from: self.position, relativeTo: nil)
    }

    /// Create a timeline event entity for range events (horizontal arc)
    @MainActor
    convenience init(event: TimelineEvent, startAngle: Float, endAngle: Float, radius: Float, height: Float) {
        self.init()
        self.timelineEvent = event
        self.name = event.id
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.arcRadius = radius

        // Position at the arc's midpoint
        let midAngle = (startAngle + endAngle) / 2
        let midX = radius * cos(midAngle)
        let midZ = radius * sin(midAngle)
        self.position = SIMD3<Float>(midX, height, midZ)

        // Create the arc visual representation
        setupArcVisuals(for: event, startAngle: startAngle, endAngle: endAngle, radius: radius)

        // Add collision for interaction
        setupArcCollision(for: event, startAngle: startAngle, endAngle: endAngle, radius: radius)
    }

    // MARK: - Visual Setup

    @MainActor
    private func setupPointVisuals(for event: TimelineEvent) {
        let eventType = event.eventType

        // Point events are spheres
        let radius: Float = event.isAbnormal ? 0.025 : 0.02
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = TimelineColors.simpleMaterial(for: eventType)
        self.model = ModelComponent(mesh: mesh, materials: [material])

        // Add text label
        addLabel(for: event)

        // Add abnormal indicator if needed
        addIcon(for: event)
    }

    @MainActor
    private func setupArcVisuals(for event: TimelineEvent, startAngle: Float, endAngle: Float, radius: Float) {
        let eventType = event.eventType
        let material = TimelineColors.simpleMaterial(for: eventType)

        // Calculate arc length to determine number of segments
        var angleDiff = endAngle - startAngle
        if angleDiff < 0 {
            angleDiff += 2 * .pi  // Handle wrap-around
        }

        // Use more segments for longer arcs (minimum 3, roughly 1 per 5 degrees)
        let segmentCount = max(3, Int(angleDiff / (5 * .pi / 180)))
        let angleStep = angleDiff / Float(segmentCount)

        // Create arc segments as small cylinders connecting points
        for i in 0..<segmentCount {
            let angle1 = startAngle + Float(i) * angleStep
            let angle2 = startAngle + Float(i + 1) * angleStep

            // Calculate positions relative to entity center
            let midAngle = (startAngle + endAngle) / 2
            let centerX = radius * cos(midAngle)
            let centerZ = radius * sin(midAngle)

            let x1 = radius * cos(angle1) - centerX
            let z1 = radius * sin(angle1) - centerZ
            let x2 = radius * cos(angle2) - centerX
            let z2 = radius * sin(angle2) - centerZ

            // Create a small cylinder segment
            let segmentLength = sqrt(pow(x2 - x1, 2) + pow(z2 - z1, 2))
            let segmentMesh = MeshResource.generateBox(
                size: SIMD3<Float>(0.015, 0.015, segmentLength),
                cornerRadius: 0.005
            )

            let segmentEntity = Entity()
            segmentEntity.components.set(ModelComponent(mesh: segmentMesh, materials: [material]))

            // Position at midpoint of segment
            let midX = (x1 + x2) / 2
            let midZ = (z1 + z2) / 2
            segmentEntity.position = SIMD3<Float>(midX, 0, midZ)

            // Rotate to align with arc direction
            let segmentAngle = atan2(z2 - z1, x2 - x1)
            segmentEntity.orientation = simd_quatf(angle: segmentAngle, axis: SIMD3<Float>(0, 1, 0))

            self.addChild(segmentEntity)
        }

        // Add spheres at start and end points for clean caps
        let capRadius: Float = 0.012
        let capMesh = MeshResource.generateSphere(radius: capRadius)

        // Start cap
        let startCap = Entity()
        startCap.components.set(ModelComponent(mesh: capMesh, materials: [material]))
        let startX = radius * cos(startAngle) - radius * cos((startAngle + endAngle) / 2)
        let startZ = radius * sin(startAngle) - radius * sin((startAngle + endAngle) / 2)
        startCap.position = SIMD3<Float>(startX, 0, startZ)
        self.addChild(startCap)

        // End cap
        let endCap = Entity()
        endCap.components.set(ModelComponent(mesh: capMesh, materials: [material]))
        let endX = radius * cos(endAngle) - radius * cos((startAngle + endAngle) / 2)
        let endZ = radius * sin(endAngle) - radius * sin((startAngle + endAngle) / 2)
        endCap.position = SIMD3<Float>(endX, 0, endZ)
        self.addChild(endCap)

        // Add label at the midpoint
        addLabel(for: event)
    }

    @MainActor
    private func addLabel(for event: TimelineEvent) {
        let labelEntity = Entity()
        labelEntity.name = "label"

        // Create text mesh
        let textMesh = MeshResource.generateText(
            event.content,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.015),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )

        let textMaterial = UnlitMaterial(color: .white)
        labelEntity.components.set(ModelComponent(mesh: textMesh, materials: [textMaterial]))

        // Position label above the event
        labelEntity.position = SIMD3<Float>(0, 0.05, 0)

        self.addChild(labelEntity)
    }

    @MainActor
    private func addIcon(for event: TimelineEvent) {
        // Icons are represented by small colored shapes that indicate the event type
        // The shape already conveys type through color, so we keep icons subtle
        guard event.isAbnormal else { return }

        // Add abnormal indicator (red ring)
        let ringMesh = MeshResource.generateBox(size: SIMD3<Float>(0.05, 0.002, 0.05), cornerRadius: 0.025)
        var ringMaterial = UnlitMaterial()
        ringMaterial.color = .init(tint: UIColor(TimelineColors.abnormalIndicator))

        let ringEntity = Entity()
        ringEntity.components.set(ModelComponent(mesh: ringMesh, materials: [ringMaterial]))
        ringEntity.position = SIMD3<Float>(0, -0.03, 0)

        self.addChild(ringEntity)
    }

    @MainActor
    private func setupCollision(for event: TimelineEvent) {
        // Add collision shape for point events
        let shape = ShapeResource.generateSphere(radius: 0.03)
        self.components.set(CollisionComponent(shapes: [shape]))
        self.components.set(InputTargetComponent())
    }

    @MainActor
    private func setupArcCollision(for event: TimelineEvent, startAngle: Float, endAngle: Float, radius: Float) {
        // Create a bounding box collision for the arc
        var angleDiff = endAngle - startAngle
        if angleDiff < 0 {
            angleDiff += 2 * .pi
        }

        // Approximate arc with a box at its midpoint
        let arcLength = radius * angleDiff
        let shape = ShapeResource.generateBox(size: SIMD3<Float>(arcLength * 0.5, 0.05, 0.05))

        self.components.set(CollisionComponent(shapes: [shape]))
        self.components.set(InputTargetComponent())
    }

    // MARK: - Appearance Updates

    @MainActor
    private func updateAppearance() {
        guard let event = timelineEvent else { return }

        var material: RealityKit.Material

        if isSelected {
            // Selected: brighter, glowing
            material = TimelineColors.glowMaterial(for: event.eventType)
        } else if isHovered {
            // Hovered: slightly brighter
            var simpleMaterial = TimelineColors.simpleMaterial(for: event.eventType)
            simpleMaterial.color.tint = simpleMaterial.color.tint.withAlphaComponent(1.0)
            material = simpleMaterial
        } else {
            // Normal state
            material = TimelineColors.simpleMaterial(for: event.eventType)
        }

        self.model?.materials = [material]

        // Scale on selection
        let scale: Float = isSelected ? 1.3 : (isHovered ? 1.1 : 1.0)
        self.scale = SIMD3<Float>(repeating: scale)
    }
}

// MARK: - Timeline Axis Entity

/// The central timeline axis that events are arranged around
class TimelineAxisEntity: Entity, HasModel {

    required init() {
        super.init()
    }

    /// Create the timeline axis with date markers
    @MainActor
    convenience init(startDate: Date, endDate: Date, radius: Float) {
        self.init()
        self.name = "TimelineAxis"

        // Create the main circular axis
        createCircularAxis(radius: radius)

        // Add date markers around the circle
        createDateMarkers(startDate: startDate, endDate: endDate, radius: radius)

        // Add legend
        createLegend(radius: radius)
    }

    @MainActor
    private func createCircularAxis(radius: Float) {
        // Create a thin torus as the timeline axis
        // Using a ring of small spheres since MeshResource doesn't have generateTorus
        let segments = 72
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let x = radius * cos(angle)
            let z = radius * sin(angle)

            let segmentEntity = Entity()
            let mesh = MeshResource.generateSphere(radius: 0.005)
            var material = UnlitMaterial()
            material.color = .init(tint: .gray.withAlphaComponent(0.5))
            segmentEntity.components.set(ModelComponent(mesh: mesh, materials: [material]))
            segmentEntity.position = SIMD3<Float>(x, 0, z)

            self.addChild(segmentEntity)
        }
    }

    @MainActor
    private func createDateMarkers(startDate: Date, endDate: Date, radius: Float) {
        let calendar = Calendar.current
        let totalDays = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 365

        // Create year markers
        var currentDate = startDate
        var markerIndex = 0

        while currentDate <= endDate {
            let year = calendar.component(.year, from: currentDate)
            let month = calendar.component(.month, from: currentDate)

            // Only show January markers (year boundaries)
            if month == 1 {
                let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: currentDate).day ?? 0
                let progress = Float(daysSinceStart) / Float(totalDays)
                let angle = progress * 2 * .pi - .pi / 2  // Start from top

                let x = (radius + 0.1) * cos(angle)
                let z = (radius + 0.1) * sin(angle)

                // Create year label
                let labelEntity = Entity()
                let textMesh = MeshResource.generateText(
                    String(year),
                    extrusionDepth: 0.001,
                    font: .systemFont(ofSize: 0.03, weight: .bold),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byClipping
                )

                var textMaterial = UnlitMaterial()
                textMaterial.color = .init(tint: .white)
                labelEntity.components.set(ModelComponent(mesh: textMesh, materials: [textMaterial]))
                labelEntity.position = SIMD3<Float>(x, 0.05, z)
                labelEntity.look(at: .zero, from: labelEntity.position, relativeTo: nil)

                self.addChild(labelEntity)

                // Create tick mark
                let tickEntity = Entity()
                let tickMesh = MeshResource.generateBox(size: SIMD3<Float>(0.005, 0.03, 0.005))
                var tickMaterial = UnlitMaterial()
                tickMaterial.color = .init(tint: .white.withAlphaComponent(0.7))
                tickEntity.components.set(ModelComponent(mesh: tickMesh, materials: [tickMaterial]))
                tickEntity.position = SIMD3<Float>(radius * cos(angle), 0, radius * sin(angle))

                self.addChild(tickEntity)

                markerIndex += 1
            }

            // Move to next month
            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? endDate
        }
    }

    @MainActor
    private func createLegend(radius: Float) {
        // Create a legend panel floating above the timeline
        let legendEntity = Entity()
        legendEntity.name = "Legend"
        legendEntity.position = SIMD3<Float>(0, 0.5, -radius - 0.3)

        var yOffset: Float = 0
        for eventType in EventType.allCases {
            let rowEntity = Entity()

            // Color indicator
            let colorMesh = MeshResource.generateSphere(radius: 0.015)
            let colorMaterial = TimelineColors.simpleMaterial(for: eventType)
            let colorEntity = Entity()
            colorEntity.components.set(ModelComponent(mesh: colorMesh, materials: [colorMaterial]))
            colorEntity.position = SIMD3<Float>(-0.15, 0, 0)
            rowEntity.addChild(colorEntity)

            // Label
            let textMesh = MeshResource.generateText(
                eventType.displayName,
                extrusionDepth: 0.001,
                font: .systemFont(ofSize: 0.02),
                containerFrame: .zero,
                alignment: .left,
                lineBreakMode: .byClipping
            )
            var textMaterial = UnlitMaterial()
            textMaterial.color = .init(tint: .white)
            let textEntity = Entity()
            textEntity.components.set(ModelComponent(mesh: textMesh, materials: [textMaterial]))
            textEntity.position = SIMD3<Float>(-0.1, 0, 0)
            rowEntity.addChild(textEntity)

            rowEntity.position = SIMD3<Float>(0, yOffset, 0)
            legendEntity.addChild(rowEntity)

            yOffset -= 0.04
        }

        self.addChild(legendEntity)
    }
}

// MARK: - Birth/Death Marker Entity

/// Special marker for birth and death dates
class LifeMarkerEntity: Entity, HasModel {

    enum MarkerType {
        case birth
        case death
    }

    required init() {
        super.init()
    }

    @MainActor
    convenience init(type: MarkerType, angle: Float, radius: Float) {
        self.init()

        let color: UIColor
        let height: Float = 0.3

        switch type {
        case .birth:
            self.name = "BirthMarker"
            color = UIColor(TimelineColors.vital)  // Green for birth
        case .death:
            self.name = "DeathMarker"
            color = UIColor(TimelineColors.death)  // Dark gray for death
        }

        // Create vertical line
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(0.01, height, 0.01))
        var material = UnlitMaterial()
        material.color = .init(tint: color)

        self.components.set(ModelComponent(mesh: mesh, materials: [material]))

        let x = radius * cos(angle)
        let z = radius * sin(angle)
        self.position = SIMD3<Float>(x, height / 2, z)
    }
}
