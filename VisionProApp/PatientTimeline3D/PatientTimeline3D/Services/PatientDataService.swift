import Foundation

/// Service for fetching patient data
/// In production, this would connect to a REST API backend
/// Currently uses mock data for development and testing
actor PatientDataService {

    // MARK: - Configuration

    enum DataSource {
        case mock
        case api(baseURL: URL)
    }

    private let dataSource: DataSource

    init(dataSource: DataSource = .mock) {
        self.dataSource = dataSource
    }

    // MARK: - Public API

    /// Fetch patient demographics by patient ID
    func fetchPatient(patientId: String) async throws -> Patient {
        switch dataSource {
        case .mock:
            return fetchMockPatient(patientId: patientId)
        case .api(let baseURL):
            return try await fetchPatientFromAPI(patientId: patientId, baseURL: baseURL)
        }
    }

    /// Fetch all timeline events for a patient
    func fetchTimelineEvents(patientId: String) async throws -> [TimelineEvent] {
        switch dataSource {
        case .mock:
            return fetchMockTimelineEvents(patientId: patientId)
        case .api(let baseURL):
            return try await fetchTimelineEventsFromAPI(patientId: patientId, baseURL: baseURL)
        }
    }

    /// Search patients by criteria
    func searchPatients(query: String) async throws -> [Patient] {
        switch dataSource {
        case .mock:
            // Return sample patient if query matches
            let sample = MockDataGenerator.samplePatient
            if sample.patientId.contains(query) {
                return [sample]
            }
            return []
        case .api(let baseURL):
            return try await searchPatientsFromAPI(query: query, baseURL: baseURL)
        }
    }

    // MARK: - Mock Data Implementation

    private func fetchMockPatient(patientId: String) -> Patient {
        // Simulate network delay
        // In mock mode, return generated patient
        return MockDataGenerator.generatePatient(patientId: patientId)
    }

    private func fetchMockTimelineEvents(patientId: String) -> [TimelineEvent] {
        // Return pre-generated or new mock events
        if patientId == "SAMPLE_001" {
            return MockDataGenerator.sampleEvents
        }
        return MockDataGenerator.generateTimelineEvents(patientId: patientId)
    }

    // MARK: - API Implementation (for future use)

    private func fetchPatientFromAPI(patientId: String, baseURL: URL) async throws -> Patient {
        let url = baseURL.appendingPathComponent("patients/\(patientId)")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DataServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Patient.self, from: data)
    }

    private func fetchTimelineEventsFromAPI(patientId: String, baseURL: URL) async throws -> [TimelineEvent] {
        let url = baseURL.appendingPathComponent("patients/\(patientId)/timeline")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DataServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TimelineEvent].self, from: data)
    }

    private func searchPatientsFromAPI(query: String, baseURL: URL) async throws -> [Patient] {
        var components = URLComponents(url: baseURL.appendingPathComponent("patients/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else {
            throw DataServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DataServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Patient].self, from: data)
    }
}

// MARK: - Errors

enum DataServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    case notFound
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Failed to decode response"
        case .notFound:
            return "Patient not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Event Aggregation

extension PatientDataService {

    /// Aggregate events by day
    func aggregateEventsByDay(events: [TimelineEvent]) -> [Date: [TimelineEvent]] {
        Dictionary(grouping: events) { event in
            event.startDate.startOfDay
        }
    }

    /// Aggregate events by week
    func aggregateEventsByWeek(events: [TimelineEvent]) -> [String: [TimelineEvent]] {
        Dictionary(grouping: events) { event in
            event.startDate.isoWeekString
        }
    }

    /// Create aggregated events for display
    func createAggregatedEvents(events: [TimelineEvent], aggregation: AggregationLevel) -> [AggregatedEvent] {
        switch aggregation {
        case .individual:
            return []  // No aggregation needed
        case .daily:
            return aggregateDaily(events: events)
        case .weekly:
            return aggregateWeekly(events: events)
        }
    }

    private func aggregateDaily(events: [TimelineEvent]) -> [AggregatedEvent] {
        var aggregated: [AggregatedEvent] = []

        // Group by date and event type
        let grouped = Dictionary(grouping: events) { event in
            "\(event.startDate.startOfDay.timeIntervalSince1970)_\(event.eventType.rawValue)"
        }

        for (key, groupedEvents) in grouped {
            guard groupedEvents.count > 1 else { continue }

            let firstEvent = groupedEvents[0]
            aggregated.append(AggregatedEvent(
                id: "AGG_\(key)",
                date: firstEvent.startDate.startOfDay,
                eventType: firstEvent.eventType,
                events: groupedEvents
            ))
        }

        return aggregated
    }

    private func aggregateWeekly(events: [TimelineEvent]) -> [AggregatedEvent] {
        var aggregated: [AggregatedEvent] = []

        // Group by ISO week and event type
        let grouped = Dictionary(grouping: events) { event in
            "\(event.startDate.isoWeekString)_\(event.eventType.rawValue)"
        }

        for (key, groupedEvents) in grouped {
            guard groupedEvents.count > 1 else { continue }

            let firstEvent = groupedEvents[0]
            aggregated.append(AggregatedEvent(
                id: "AGG_\(key)",
                date: firstEvent.startDate.startOfDay,
                eventType: firstEvent.eventType,
                events: groupedEvents
            ))
        }

        return aggregated
    }
}

// MARK: - Aggregation Level

enum AggregationLevel: String, CaseIterable, Identifiable {
    case individual = "Individual"
    case daily = "Daily"
    case weekly = "Weekly"

    var id: String { rawValue }
}
