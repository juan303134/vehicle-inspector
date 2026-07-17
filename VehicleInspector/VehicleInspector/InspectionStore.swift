import Foundation

@MainActor
final class InspectionStore: ObservableObject {
    @Published var vehicles: [Vehicle] = [
        Vehicle(id: UUID(), plate: "TXK-482", makeModel: "Toyota Corolla 2023", color: "White", lastInspectionDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())),
        Vehicle(id: UUID(), plate: "LMP-914", makeModel: "Ford Transit 2022", color: "Gray", lastInspectionDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()))
    ]

    @Published var inspections: [Inspection] = []

    init() {
        seedInspections()
    }

    func addVehicle(plate: String, makeModel: String, color: String) {
        let vehicle = Vehicle(id: UUID(), plate: plate.uppercased(), makeModel: makeModel, color: color, lastInspectionDate: nil)
        vehicles.insert(vehicle, at: 0)
    }

    func inspections(for vehicle: Vehicle) -> [Inspection] {
        inspections
            .filter { $0.vehicleID == vehicle.id }
            .sorted { $0.date > $1.date }
    }

    func createInspection(
        for vehicle: Vehicle,
        photos: [InspectionPhoto],
        findings: [DamageFinding]? = nil,
        analysisSource: AnalysisSource = .simulated,
        status: InspectionStatus = .needsReview,
        checklist: [InspectionChecklistItem] = InspectionChecklistItem.defaults,
        inspectorNotes: String = "",
        odometerText: String = "",
        odometerImageData: Data? = nil
    ) -> Inspection {
        let findings = findings ?? mockFindings(for: photos)
        let inspection = Inspection(
            id: UUID(),
            vehicleID: vehicle.id,
            date: Date(),
            photos: photos,
            findings: findings,
            analysisSource: analysisSource,
            status: status,
            checklist: checklist,
            inspectorNotes: inspectorNotes,
            odometerText: odometerText,
            odometerImageData: odometerImageData
        )
        inspections.insert(inspection, at: 0)

        if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index].lastInspectionDate = inspection.date
        }

        return inspection
    }

    func fallbackFindings(for photos: [InspectionPhoto]) -> [DamageFinding] {
        mockFindings(for: photos)
    }

    func updateFindingStatus(inspectionID: UUID, findingID: UUID, status: FindingReviewStatus) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let findingIndex = inspections[inspectionIndex].findings.firstIndex(where: { $0.id == findingID }) else {
            return
        }

        inspections[inspectionIndex].findings[findingIndex].reviewStatus = status
    }

    func updateFindingSeverity(inspectionID: UUID, findingID: UUID, severity: DamageSeverity) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let findingIndex = inspections[inspectionIndex].findings.firstIndex(where: { $0.id == findingID }) else {
            return
        }

        inspections[inspectionIndex].findings[findingIndex].severity = severity
    }

    func updateFindingNote(inspectionID: UUID, findingID: UUID, note: String) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let findingIndex = inspections[inspectionIndex].findings.firstIndex(where: { $0.id == findingID }) else {
            return
        }

        inspections[inspectionIndex].findings[findingIndex].note = note
    }

    func updateInspectionNotes(inspectionID: UUID, notes: String) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }) else {
            return
        }

        inspections[inspectionIndex].inspectorNotes = notes
    }

    func updateChecklistItem(inspectionID: UUID, itemID: String, status: ChecklistStatus) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let itemIndex = inspections[inspectionIndex].checklist.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        inspections[inspectionIndex].checklist[itemIndex].status = status
    }

    func replaceAnalysis(inspectionID: UUID, findings: [DamageFinding], source: AnalysisSource) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }) else {
            return
        }

        inspections[inspectionIndex].findings = findings
        inspections[inspectionIndex].analysisSource = source
        inspections[inspectionIndex].status = findings.isEmpty ? .completed : .needsReview
    }

    func appendFindings(inspectionID: UUID, findings: [DamageFinding], source: AnalysisSource) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }) else {
            return
        }

        inspections[inspectionIndex].findings.append(contentsOf: findings)
        inspections[inspectionIndex].analysisSource = source
        inspections[inspectionIndex].status = inspections[inspectionIndex].findings.isEmpty ? .completed : .needsReview
    }

    private func seedInspections() {
        guard let first = vehicles.first else { return }

        let photos = InspectionAngle.guidedAngles.map {
            InspectionPhoto(id: UUID(), angle: $0, captured: true, imageData: nil)
        }

        inspections = [
            Inspection(
                id: UUID(),
                vehicleID: first.id,
                date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
                photos: photos,
                findings: [
                    DamageFinding(id: UUID(), photoID: nil, angle: .driver, type: .scratch, severity: .low, location: "Lower driver door area", confidence: 0.88, isNew: false, region: DamageRegion(x: 0.33, y: 0.58, width: 0.28, height: 0.14)),
                    DamageFinding(id: UUID(), photoID: nil, angle: .rear, type: .paint, severity: .medium, location: "Right rear bumper", confidence: 0.81, isNew: false, region: DamageRegion(x: 0.58, y: 0.64, width: 0.22, height: 0.16))
                ],
                analysisSource: .simulated,
                status: .needsReview,
                checklist: InspectionChecklistItem.defaults,
                inspectorNotes: "Previous inspection record.",
                odometerText: "42,180"
            )
        ]
    }

    private func mockFindings(for photos: [InspectionPhoto]) -> [DamageFinding] {
        [
            DamageFinding(id: UUID(), photoID: nil, angle: .front, type: .scratch, severity: .low, location: "Front bumper, left side", confidence: 0.84, isNew: true, region: DamageRegion(x: 0.18, y: 0.62, width: 0.26, height: 0.13)),
            DamageFinding(id: UUID(), photoID: nil, angle: .driver, type: .dent, severity: .medium, location: "Driver-side rear door", confidence: 0.79, isNew: true, region: DamageRegion(x: 0.50, y: 0.43, width: 0.22, height: 0.18)),
            DamageFinding(id: UUID(), photoID: nil, angle: .rear, type: .paint, severity: .medium, location: "Right rear bumper", confidence: 0.86, isNew: false, region: DamageRegion(x: 0.57, y: 0.62, width: 0.24, height: 0.16))
        ].filter { finding in
            photos.contains { $0.angle == finding.angle && $0.captured }
        }
    }
}
