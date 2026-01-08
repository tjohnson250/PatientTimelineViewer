import SwiftUI
import RealityKit

/// Color scheme matching the original Patient Timeline Viewer
/// These colors are used consistently across 2D UI and 3D visualization
enum TimelineColors {
    // Event type colors (matching www/custom.css)
    static let encounter = Color(hex: "#3498db")      // Blue
    static let diagnosis = Color(hex: "#e74c3c")      // Coral
    static let procedure = Color(hex: "#9b59b6")      // Purple
    static let lab = Color(hex: "#27ae60")            // Green
    static let prescribing = Color(hex: "#e67e22")    // Orange
    static let dispensing = Color(hex: "#f39c12")     // Amber
    static let vital = Color(hex: "#1abc9c")          // Teal
    static let condition = Color(hex: "#e91e63")      // Pink
    static let death = Color(hex: "#2c3e50")          // Dark Gray

    // UI colors
    static let background = Color(hex: "#1a1a2e")
    static let cardBackground = Color(hex: "#16213e")
    static let text = Color.white
    static let textSecondary = Color.gray
    static let accent = Color(hex: "#0f4c75")
    static let abnormalIndicator = Color(hex: "#e74c3c")

    /// Get color for event type
    static func color(for eventType: EventType) -> Color {
        switch eventType {
        case .encounter: return encounter
        case .diagnosis: return diagnosis
        case .procedure: return procedure
        case .lab: return lab
        case .prescribing: return prescribing
        case .dispensing: return dispensing
        case .vital: return vital
        case .condition: return condition
        case .death: return death
        }
    }

    /// Get lighter variant for backgrounds
    static func backgroundColor(for eventType: EventType) -> Color {
        color(for: eventType).opacity(0.3)
    }

    /// Get SIMD color for RealityKit materials
    static func simdColor(for eventType: EventType) -> SIMD3<Float> {
        let color = color(for: eventType)
        return color.toSIMD3()
    }

    /// Get UIColor for 3D materials
    static func uiColor(for eventType: EventType) -> UIColor {
        UIColor(color(for: eventType))
    }
}

// MARK: - Color Extensions

extension Color {
    /// Initialize from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert to SIMD3<Float> for RealityKit
    func toSIMD3() -> SIMD3<Float> {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD3<Float>(Float(red), Float(green), Float(blue))
    }

    /// Convert to SIMD4<Float> with alpha for RealityKit
    func toSIMD4() -> SIMD4<Float> {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    }
}

// MARK: - Material Helpers

extension TimelineColors {
    /// Create a simple material for event type
    @MainActor
    static func simpleMaterial(for eventType: EventType, isSelected: Bool = false) -> SimpleMaterial {
        var material = SimpleMaterial()
        let baseColor = color(for: eventType)

        if isSelected {
            material.color = .init(tint: UIColor(baseColor.opacity(1.0)))
        } else {
            material.color = .init(tint: UIColor(baseColor.opacity(0.8)))
        }

        material.roughness = .float(0.3)
        material.metallic = .float(0.1)

        return material
    }

    /// Create a glowing material for highlighted events
    @MainActor
    static func glowMaterial(for eventType: EventType) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(color(for: eventType)))
        return material
    }
}
