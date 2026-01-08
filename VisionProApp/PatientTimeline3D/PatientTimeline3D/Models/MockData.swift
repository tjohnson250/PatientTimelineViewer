import Foundation

/// Mock data generator for testing the Vision Pro app
/// Generates realistic patient timeline data matching PCORnet CDM structure
struct MockDataGenerator {

    /// Generate a mock patient
    static func generatePatient(patientId: String = "12345") -> Patient {
        Patient(
            id: UUID().uuidString,
            patientId: patientId,
            birthDate: Calendar.current.date(byAdding: .year, value: -65, to: Date()),
            deathDate: nil,
            sex: "M",
            race: "White",
            ethnicity: "Not Hispanic or Latino",
            sourceSystems: ["Epic", "Cerner", "Claims"]
        )
    }

    /// Generate mock timeline events for a patient
    static func generateTimelineEvents(patientId: String, count: Int = 150) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        let calendar = Calendar.current
        let today = Date()

        // Generate events over the past 10 years
        let startDate = calendar.date(byAdding: .year, value: -10, to: today)!

        // Encounters (20-30)
        let encounterCount = Int.random(in: 20...30)
        for i in 0..<encounterCount {
            let randomDays = Int.random(in: 0...3650)
            let admitDate = calendar.date(byAdding: .day, value: randomDays, to: startDate)!
            let lengthOfStay = Int.random(in: 1...7)
            let dischargeDate = calendar.date(byAdding: .day, value: lengthOfStay, to: admitDate)

            let encounterTypes = ["IP", "ED", "AV", "OS"]
            let encounterType = encounterTypes.randomElement()!

            events.append(TimelineEvent(
                id: "ENC_\(i)",
                content: "\(encounterTypeDescription(encounterType))",
                startDate: admitDate,
                endDate: dischargeDate,
                eventType: .encounter,
                sourceTable: "ENCOUNTER",
                sourceKey: "ENC_\(1000 + i)",
                details: [
                    "Encounter Type": encounterTypeDescription(encounterType),
                    "Admit Date": formatDate(admitDate),
                    "Discharge Date": formatDate(dischargeDate ?? admitDate),
                    "Length of Stay": "\(lengthOfStay) days",
                    "Discharge Status": "Alive",
                    "Facility": "Main Hospital"
                ],
                isAbnormal: false
            ))
        }

        // Diagnoses (30-50)
        let diagnosisCount = Int.random(in: 30...50)
        let diagnosisCodes = [
            ("E11.9", "Type 2 diabetes mellitus without complications"),
            ("I10", "Essential hypertension"),
            ("J06.9", "Acute upper respiratory infection"),
            ("M54.5", "Low back pain"),
            ("K21.0", "Gastroesophageal reflux disease with esophagitis"),
            ("F32.9", "Major depressive disorder, single episode"),
            ("J45.909", "Unspecified asthma, uncomplicated"),
            ("E78.5", "Hyperlipidemia, unspecified"),
            ("G47.33", "Obstructive sleep apnea")
        ]

        for i in 0..<diagnosisCount {
            let randomDays = Int.random(in: 0...3650)
            let dxDate = calendar.date(byAdding: .day, value: randomDays, to: startDate)!
            let (code, description) = diagnosisCodes.randomElement()!

            events.append(TimelineEvent(
                id: "DX_\(i)",
                content: code,
                startDate: dxDate,
                endDate: nil,
                eventType: .diagnosis,
                sourceTable: "DIAGNOSIS",
                sourceKey: "DX_\(2000 + i)",
                details: [
                    "ICD-10 Code": code,
                    "Description": description,
                    "Diagnosis Date": formatDate(dxDate),
                    "Principal": i % 5 == 0 ? "Yes" : "No"
                ],
                isAbnormal: false
            ))
        }

        // Procedures (15-25)
        let procedureCount = Int.random(in: 15...25)
        let procedureCodes = [
            ("99213", "Office visit, established patient"),
            ("99214", "Office visit, established patient - moderate"),
            ("36415", "Venipuncture"),
            ("93000", "Electrocardiogram, complete"),
            ("71046", "Chest X-ray, 2 views"),
            ("80053", "Comprehensive metabolic panel"),
            ("85025", "Complete blood count with differential")
        ]

        for i in 0..<procedureCount {
            let randomDays = Int.random(in: 0...3650)
            let pxDate = calendar.date(byAdding: .day, value: randomDays, to: startDate)!
            let (code, description) = procedureCodes.randomElement()!

            events.append(TimelineEvent(
                id: "PX_\(i)",
                content: code,
                startDate: pxDate,
                endDate: nil,
                eventType: .procedure,
                sourceTable: "PROCEDURES",
                sourceKey: "PX_\(3000 + i)",
                details: [
                    "CPT Code": code,
                    "Description": description,
                    "Procedure Date": formatDate(pxDate)
                ],
                isAbnormal: false
            ))
        }

        // Labs (40-60)
        let labCount = Int.random(in: 40...60)
        let labTests = [
            ("Glucose", "mg/dL", 70...100, 50...200),
            ("Hemoglobin A1c", "%", 4.0...5.6, 4.0...12.0),
            ("Creatinine", "mg/dL", 0.7...1.3, 0.5...3.0),
            ("Potassium", "mEq/L", 3.5...5.0, 2.5...6.5),
            ("Sodium", "mEq/L", 136...145, 130...155),
            ("Total Cholesterol", "mg/dL", 0...200, 100...350),
            ("LDL Cholesterol", "mg/dL", 0...100, 50...250),
            ("HDL Cholesterol", "mg/dL", 40...60, 20...100),
            ("Triglycerides", "mg/dL", 0...150, 50...500)
        ]

        for i in 0..<labCount {
            let randomDays = Int.random(in: 0...3650)
            let labDate = calendar.date(byAdding: .day, value: randomDays, to: startDate)!
            let testIndex = i % labTests.count
            let (name, unit, normalRange, possibleRange) = labTests[testIndex]

            let value = Double.random(in: possibleRange.lowerBound...possibleRange.upperBound)
            let isAbnormal = value < normalRange.lowerBound || value > normalRange.upperBound
            let abnormalFlag = isAbnormal ? (value < normalRange.lowerBound ? "L" : "H") : ""

            events.append(TimelineEvent(
                id: "LAB_\(i)",
                content: name,
                startDate: labDate,
                endDate: nil,
                eventType: .lab,
                sourceTable: "LAB_RESULT_CM",
                sourceKey: "LAB_\(4000 + i)",
                details: [
                    "Lab Test": name,
                    "Result": String(format: "%.1f", value),
                    "Unit": unit,
                    "Reference Range": "\(normalRange.lowerBound) - \(normalRange.upperBound)",
                    "Abnormal Flag": abnormalFlag,
                    "Collection Date": formatDate(labDate)
                ],
                isAbnormal: isAbnormal
            ))
        }

        // Prescriptions (20-35)
        let prescriptionCount = Int.random(in: 20...35)
        let medications = [
            "Metformin 500mg",
            "Lisinopril 10mg",
            "Atorvastatin 20mg",
            "Omeprazole 20mg",
            "Metoprolol 25mg",
            "Amlodipine 5mg",
            "Gabapentin 300mg",
            "Sertraline 50mg"
        ]

        for i in 0..<prescriptionCount {
            let randomDays = Int.random(in: 0...3650)
            let rxStartDate = calendar.date(byAdding: .day, value: randomDays, to: startDate)!
            let rxDuration = Int.random(in: 30...180)
            let rxEndDate = calendar.date(byAdding: .day, value: rxDuration, to: rxStartDate)
            let medication = medications.randomElement()!

            events.append(TimelineEvent(
                id: "RX_\(i)",
                content: medication,
                startDate: rxStartDate,
                endDate: rxEndDate,
                eventType: .prescribing,
                sourceTable: "PRESCRIBING",
                sourceKey: "RX_\(5000 + i)",
                details: [
                    "Medication": medication,
                    "Start Date": formatDate(rxStartDate),
                    "End Date": formatDate(rxEndDate ?? rxStartDate),
                    "Quantity": "\(Int.random(in: 30...90))",
                    "Refills": "\(Int.random(in: 0...5))"
                ],
                isAbnormal: false
            ))
        }

        // Dispensing events (15-25)
        let dispensingCount = Int.random(in: 15...25)
        for i in 0..<dispensingCount {
            let randomDays = Int.random(in: 0...3650)
            let dispDate = calendar.date(byAdding: .day, value: randomDays, to: startDate)!
            let medication = medications.randomElement()!

            events.append(TimelineEvent(
                id: "DISP_\(i)",
                content: medication,
                startDate: dispDate,
                endDate: nil,
                eventType: .dispensing,
                sourceTable: "DISPENSING",
                sourceKey: "DISP_\(6000 + i)",
                details: [
                    "Medication": medication,
                    "Dispense Date": formatDate(dispDate),
                    "Days Supply": "\(Int.random(in: 30...90))",
                    "NDC": String(format: "%05d-%04d-%02d", Int.random(in: 0...99999), Int.random(in: 0...9999), Int.random(in: 0...99))
                ],
                isAbnormal: false
            ))
        }

        // Vitals (30-50)
        let vitalCount = Int.random(in: 30...50)
        for i in 0..<vitalCount {
            let randomDays = Int.random(in: 0...3650)
            let vitalDate = calendar.date(byAdding: .day, value: randomDays, to: startDate)!

            let systolic = Int.random(in: 110...160)
            let diastolic = Int.random(in: 60...100)
            let heartRate = Int.random(in: 60...100)
            let weight = Double.random(in: 150...250)
            let isHypertensive = systolic >= 140 || diastolic >= 90

            events.append(TimelineEvent(
                id: "VIT_\(i)",
                content: "BP: \(systolic)/\(diastolic)",
                startDate: vitalDate,
                endDate: nil,
                eventType: .vital,
                sourceTable: "VITAL",
                sourceKey: "VIT_\(7000 + i)",
                details: [
                    "Systolic BP": "\(systolic) mmHg",
                    "Diastolic BP": "\(diastolic) mmHg",
                    "Heart Rate": "\(heartRate) bpm",
                    "Weight": String(format: "%.1f lbs", weight),
                    "Measurement Date": formatDate(vitalDate)
                ],
                isAbnormal: isHypertensive
            ))
        }

        // Conditions (5-10)
        let conditionCount = Int.random(in: 5...10)
        let conditions = [
            "Type 2 Diabetes Mellitus",
            "Essential Hypertension",
            "Hyperlipidemia",
            "Obesity",
            "Chronic Kidney Disease Stage 3"
        ]

        for i in 0..<conditionCount {
            let randomDays = Int.random(in: 0...3650)
            let onsetDate = calendar.date(byAdding: .day, value: randomDays, to: startDate)!
            let condition = conditions[i % conditions.count]

            events.append(TimelineEvent(
                id: "COND_\(i)",
                content: condition,
                startDate: onsetDate,
                endDate: nil,
                eventType: .condition,
                sourceTable: "CONDITION",
                sourceKey: "COND_\(8000 + i)",
                details: [
                    "Condition": condition,
                    "Status": "Active",
                    "Onset Date": formatDate(onsetDate)
                ],
                isAbnormal: false
            ))
        }

        return events.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Helper Functions

    private static func encounterTypeDescription(_ type: String) -> String {
        switch type {
        case "IP": return "Inpatient"
        case "ED": return "Emergency"
        case "AV": return "Ambulatory Visit"
        case "OS": return "Outpatient Services"
        default: return type
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Sample Data

extension MockDataGenerator {
    /// Pre-generated sample patient for quick testing
    static let samplePatient = generatePatient(patientId: "SAMPLE_001")

    /// Pre-generated sample events for quick testing
    static let sampleEvents = generateTimelineEvents(patientId: "SAMPLE_001", count: 100)
}
