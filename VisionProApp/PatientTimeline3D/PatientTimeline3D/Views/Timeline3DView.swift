import SwiftUI
import RealityKit

/// A volumetric window version of the timeline (for windowed 3D mode)
/// This provides a smaller 3D preview that can be used without full immersion
struct Timeline3DView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var rotation: Angle = .zero
    @State private var isDragging = false

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                // Create a scaled-down version of the timeline
                let root = Entity()
                root.name = "VolumetricTimeline"

                // Scale to fit in volumetric window
                root.scale = SIMD3<Float>(repeating: 0.3)

                await buildMiniTimeline(in: root)

                content.add(root)
            } update: { content in
                // Apply rotation from drag gesture
                if let root = content.entities.first {
                    root.transform.rotation = simd_quatf(
                        angle: Float(rotation.radians),
                        axis: SIMD3<Float>(0, 1, 0)
                    )
                }
            }
            .gesture(dragRotationGesture)
        }
    }

    // MARK: - Mini Timeline

    @MainActor
    private func buildMiniTimeline(in root: Entity) async {
        guard let dateRange = appModel.dateRange else { return }

        // Add simplified axis
        let axisRadius: Float = 0.5
        let segments = 36
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let x = axisRadius * cos(angle)
            let z = axisRadius * sin(angle)

            let segmentEntity = Entity()
            let mesh = MeshResource.generateSphere(radius: 0.01)
            var material = UnlitMaterial()
            material.color = .init(tint: .gray.withAlphaComponent(0.3))
            segmentEntity.components.set(ModelComponent(mesh: mesh, materials: [material]))
            segmentEntity.position = SIMD3<Float>(x, 0, z)

            root.addChild(segmentEntity)
        }

        // Add event markers (simplified)
        for event in appModel.filteredEvents {
            let angle = calculateAngle(for: event.startDate, in: dateRange)
            let typeOffset = Float(event.eventType.groupIndex) * 0.05
            let radius = axisRadius + typeOffset

            let x = radius * cos(angle)
            let z = radius * sin(angle)
            let y = Float(event.eventType.groupIndex) * 0.03 - 0.1

            let eventEntity = Entity()
            let mesh = MeshResource.generateSphere(radius: event.isAbnormal ? 0.015 : 0.01)
            let material = TimelineColors.simpleMaterial(for: event.eventType)
            eventEntity.components.set(ModelComponent(mesh: mesh, materials: [material]))
            eventEntity.position = SIMD3<Float>(x, y, z)

            root.addChild(eventEntity)
        }
    }

    private func calculateAngle(for date: Date, in dateRange: ClosedRange<Date>) -> Float {
        let totalSeconds = dateRange.upperBound.timeIntervalSince(dateRange.lowerBound)
        let elapsedSeconds = date.timeIntervalSince(dateRange.lowerBound)
        let progress = Float(elapsedSeconds / totalSeconds)
        return progress * 2 * .pi - .pi / 2
    }

    // MARK: - Rotation Gesture

    private var dragRotationGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                rotation = .degrees(Double(value.translation.width) * 0.5)
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}

// MARK: - Timeline Stats View

/// Shows statistics about the current timeline view
struct TimelineStatsView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dateRange = appModel.dateRange {
                HStack {
                    Text("Date Range:")
                        .foregroundColor(.secondary)
                    Text("\(dateRange.lowerBound.formatted(style: .short)) - \(dateRange.upperBound.formatted(style: .short))")
                }
            }

            HStack {
                Text("Visible Events:")
                    .foregroundColor(.secondary)
                Text("\(appModel.filteredEvents.count)")
            }

            // Event type breakdown
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(EventType.allCases) { type in
                    let count = appModel.filteredEvents.filter { $0.eventType == type }.count
                    if count > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(TimelineColors.color(for: type))
                                .frame(width: 8, height: 8)
                            Text("\(count)")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Timeline Controls

/// Controls for the 3D timeline view
struct TimelineControlsView: View {
    @EnvironmentObject var appModel: AppModel
    @Binding var aggregationLevel: AggregationLevel

    var body: some View {
        VStack(spacing: 16) {
            // Aggregation level picker
            VStack(alignment: .leading) {
                Text("Aggregation")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Aggregation", selection: $aggregationLevel) {
                    ForEach(AggregationLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Timeline radius slider
            VStack(alignment: .leading) {
                Text("Distance: \(String(format: "%.1f", appModel.timelineRadius))m")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $appModel.timelineRadius, in: 1.5...4.0, step: 0.5)
            }

            // Reset button
            Button(action: {
                appModel.resetFilters()
                appModel.timelineRadius = 2.0
                appModel.timelineHeight = 0.0
            }) {
                Label("Reset View", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    Timeline3DView()
        .environmentObject(AppModel())
}
