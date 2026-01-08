import Foundation
import SwiftUI

// MARK: - Event Types

/// Types of medical events that can appear on the timeline
enum EventType: String, CaseIterable, Identifiable, Codable {
    case encounter = "encounter"
    case diagnosis = "diagnosis"
    case procedure = "procedure"
    case lab = "lab"
    case prescribing = "prescribing"
    case dispensing = "dispensing"
    case vital = "vital"
    case condition = "condition"
    case death = "death"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .encounter: return "Encounters"
        case .diagnosis: return "Diagnoses"
        case .procedure: return "Procedures"
        case .lab: return "Labs"
        case .prescribing: return "Prescriptions"
        case .dispensing: return "Dispensing"
        case .vital: return "Vitals"
        case .condition: return "Conditions"
        case .death: return "Death"
        }
    }

    var icon: String {
        switch self {
        case .encounter: return "bed.double.fill"
        case .diagnosis: return "cross.case.fill"
        case .procedure: return "scissors"
        case .lab: return "flask.fill"
        case .prescribing: return "pill.fill"
        case .dispensing: return "pills.fill"
        case .vital: return "heart.fill"
        case .condition: return "staroflife.fill"
        case .death: return "heart.slash.fill"
        }
    }

    /// Group index for 3D layout - events are arranged in concentric rings by type
    var groupIndex: Int {
        switch self {
        case .encounter: return 0
        case .diagnosis: return 1
        case .procedure: return 2
        case .lab: return 3
        case .prescribing: return 4
        case .dispensing: return 5
        case .vital: return 6
        case .condition: return 7
        case .death: return 8
        }
    }
}

// MARK: - Patient Model

/// Patient demographic information
struct Patient: Identifiable, Codable {
    let id: String
    let patientId: String
    let birthDate: Date?
    let deathDate: Date?
    let sex: String?
    let race: String?
    let ethnicity: String?
    let sourceSystems: [String]

    var age: Int? {
        guard let birth = birthDate else { return nil }
        let endDate = deathDate ?? Date()
        let components = Calendar.current.dateComponents([.year], from: birth, to: endDate)
        return components.year
    }

    var ageDescription: String {
        guard let age = age else { return "Unknown" }
        if deathDate != nil {
            return "\(age) (deceased)"
        }
        return "\(age)"
    }

    var sexDescription: String {
        switch sex?.uppercased() {
        case "M": return "Male"
        case "F": return "Female"
        case "OT": return "Other"
        default: return sex ?? "Unknown"
        }
    }
}

// MARK: - Timeline Event Model

/// A single event on the patient timeline
struct TimelineEvent: Identifiable, Codable, Equatable {
    let id: String
    let content: String
    let startDate: Date
    let endDate: Date?
    let eventType: EventType
    let sourceTable: String
    let sourceKey: String
    let details: [String: String]
    let isAbnormal: Bool

    /// Whether this is a range event (has both start and end dates)
    var isRangeEvent: Bool {
        endDate != nil && endDate != startDate
    }

    /// Duration in days for range events
    var durationDays: Int? {
        guard let end = endDate else { return nil }
        let components = Calendar.current.dateComponents([.day], from: startDate, to: end)
        return components.day
    }

    /// Formatted date string
    var dateDescription: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        if let end = endDate, end != startDate {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: end))"
        }
        return formatter.string(from: startDate)
    }

    static func == (lhs: TimelineEvent, rhs: TimelineEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Aggregated Event

/// Represents multiple events aggregated into a single marker
struct AggregatedEvent: Identifiable {
    let id: String
    let date: Date
    let eventType: EventType
    let events: [TimelineEvent]

    var count: Int { events.count }

    var content: String {
        "\(count) \(eventType.displayName.lowercased())"
    }
}

// MARK: - 3D Position

/// Position in 3D space for timeline events
struct TimelinePosition {
    let x: Float
    let y: Float
    let z: Float
    let angle: Float  // Radians around the user

    /// Create position from cylindrical coordinates
    static func fromCylindrical(angle: Float, radius: Float, height: Float) -> TimelinePosition {
        let x = radius * cos(angle)
        let z = radius * sin(angle)
        return TimelinePosition(x: x, y: height, z: z, angle: angle)
    }
}

// MARK: - Date Extensions

extension Date {
    /// Format date for display
    func formatted(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        return formatter.string(from: self)
    }

    /// ISO week string (e.g., "2024-W42")
    var isoWeekString: String {
        let calendar = Calendar(identifier: .iso8601)
        let weekOfYear = calendar.component(.weekOfYear, from: self)
        let year = calendar.component(.yearForWeekOfYear, from: self)
        return String(format: "%d-W%02d", year, weekOfYear)
    }

    /// Start of day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
