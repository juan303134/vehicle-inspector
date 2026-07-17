import Foundation
import SwiftUI

enum InspectionAngle: String, CaseIterable, Identifiable {
    case front = "Front"
    case driver = "Driver side"
    case passenger = "Passenger side"
    case rear = "Rear"
    case free = "Free photo"

    static let guidedAngles: [InspectionAngle] = [.front, .driver, .passenger, .rear]
    static let allCases: [InspectionAngle] = guidedAngles + [.free]

    var id: String { rawValue }

    var instruction: String {
        switch self {
        case .front:
            return "Take a full front photo, then add close-ups for visible damage. Avoid glare."
        case .driver:
            return "Include doors, fenders, wheels, and close-ups of scratches or dents."
        case .passenger:
            return "Include doors, fenders, wheels, and close-ups of scratches or dents."
        case .rear:
            return "Take a full rear photo with bumper, trunk/liftgate, and taillights visible."
        case .free:
            return "Capture any vehicle area you want to review in detail."
        }
    }

    var icon: String {
        switch self {
        case .front: return "car.front.waves.up"
        case .driver: return "car.side"
        case .passenger: return "car.side.front.open"
        case .rear: return "car.rear"
        case .free: return "viewfinder"
        }
    }
}

enum DamageType: String, CaseIterable {
    case scratch = "Scratch"
    case dent = "Dent"
    case paint = "Paint chip"
    case scuff = "Scuff"
    case glass = "Glass/Light"
}

enum DamageSeverity: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

enum FindingReviewStatus: String, Hashable {
    case pending = "Pending"
    case confirmed = "Confirmed"
    case dismissed = "Dismissed"

    var color: Color {
        switch self {
        case .pending: return AppTheme.warning
        case .confirmed: return .green
        case .dismissed: return AppTheme.muted
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .confirmed: return "checkmark"
        case .dismissed: return "xmark"
        }
    }
}

struct Vehicle: Identifiable, Hashable {
    let id: UUID
    var plate: String
    var makeModel: String
    var color: String
    var lastInspectionDate: Date?
}

struct InspectionPhoto: Identifiable, Hashable {
    let id: UUID
    let angle: InspectionAngle
    var captured: Bool
    var imageData: Data?
    var imageURL: URL?
}

struct DamageFinding: Identifiable, Hashable {
    let id: UUID
    let photoID: UUID?
    let angle: InspectionAngle
    let type: DamageType
    var severity: DamageSeverity
    let location: String
    let confidence: Double
    let isNew: Bool
    let region: DamageRegion
    var reviewStatus: FindingReviewStatus = .pending
    var note: String = ""
}

struct DamageRegion: Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum AnalysisSource: String, Hashable {
    case ai = "AI analysis"
    case simulated = "Simulated analysis"

    var icon: String {
        switch self {
        case .ai: return "sparkle.magnifyingglass"
        case .simulated: return "exclamationmark.triangle"
        }
    }

    var detail: String {
        switch self {
        case .ai:
            return "This inspection was analyzed with artificial intelligence."
        case .simulated:
            return "This inspection was not analyzed with artificial intelligence. Results are simulated."
        }
    }

    var color: Color {
        switch self {
        case .ai: return .green
        case .simulated: return AppTheme.warning
        }
    }
}

enum InspectionStatus: String, Hashable {
    case draft = "Draft"
    case analyzing = "AI analyzing"
    case needsReview = "Needs review"
    case completed = "Completed"
    case failed = "Failed"

    var icon: String {
        switch self {
        case .draft: return "doc"
        case .analyzing: return "hourglass"
        case .needsReview: return "exclamationmark.triangle"
        case .completed: return "checkmark.seal"
        case .failed: return "xmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .draft: return AppTheme.muted
        case .analyzing: return AppTheme.accent
        case .needsReview: return AppTheme.warning
        case .completed: return .green
        case .failed: return .red
        }
    }
}

enum ChecklistStatus: String, CaseIterable, Identifiable, Hashable {
    case pass = "Pass"
    case issue = "Issue"
    case notChecked = "Not checked"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pass: return "checkmark"
        case .issue: return "exclamationmark"
        case .notChecked: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .pass: return .green
        case .issue: return AppTheme.warning
        case .notChecked: return AppTheme.muted
        }
    }
}

struct InspectionChecklistItem: Identifiable, Hashable {
    let id: String
    var title: String
    var status: ChecklistStatus

    static let defaults: [InspectionChecklistItem] = [
        InspectionChecklistItem(id: "odometer", title: "Odometer", status: .notChecked),
        InspectionChecklistItem(id: "fuel", title: "Fuel level", status: .notChecked),
        InspectionChecklistItem(id: "tires", title: "Tires", status: .notChecked),
        InspectionChecklistItem(id: "lights", title: "Lights", status: .notChecked),
        InspectionChecklistItem(id: "windshield", title: "Windshield", status: .notChecked),
        InspectionChecklistItem(id: "mirrors", title: "Mirrors", status: .notChecked),
        InspectionChecklistItem(id: "interior", title: "Interior condition", status: .notChecked),
        InspectionChecklistItem(id: "documents", title: "Registration/insurance", status: .notChecked)
    ]
}

struct Inspection: Identifiable, Hashable {
    let id: UUID
    let vehicleID: UUID
    let date: Date
    var photos: [InspectionPhoto]
    var findings: [DamageFinding]
    var analysisSource: AnalysisSource
    var status: InspectionStatus = .needsReview
    var checklist: [InspectionChecklistItem] = InspectionChecklistItem.defaults
    var inspectorNotes: String = ""
    var odometerText: String = ""
    var odometerImageData: Data?
}

extension Date {
    var shortInspectionDate: String {
        formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }
}
