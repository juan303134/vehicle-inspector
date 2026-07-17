import Foundation

@MainActor
final class InspectionStore: ObservableObject {
    @Published var vehicles: [Vehicle] = []

    @Published var inspections: [Inspection] = []
    @Published var isLoadingCloudData = false
    @Published var cloudMessage: String?

    func addVehicle(plate: String, makeModel: String, color: String) -> Vehicle {
        let vehicle = Vehicle(id: UUID(), plate: plate.uppercased(), makeModel: makeModel, color: color, lastInspectionDate: nil)
        vehicles.insert(vehicle, at: 0)
        return vehicle
    }

    func loadCloudVehicles() async {
        isLoadingCloudData = true
        cloudMessage = nil

        do {
            vehicles = try await VehicleDamageAnalysisService.shared.fetchVehicles()
            cloudMessage = "Cloud vehicles loaded."
        } catch {
            cloudMessage = "Could not load cloud vehicles."
        }

        isLoadingCloudData = false
    }

    func loadCloudInspections(for vehicle: Vehicle) async {
        isLoadingCloudData = true
        cloudMessage = nil

        do {
            let loadedInspections = try await VehicleDamageAnalysisService.shared.fetchInspections(vehicleID: vehicle.id)
            inspections.removeAll { $0.vehicleID == vehicle.id }
            inspections.append(contentsOf: loadedInspections)

            if let latestDate = loadedInspections.map(\.date).max(),
               let vehicleIndex = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
                vehicles[vehicleIndex].lastInspectionDate = latestDate
            }

            cloudMessage = "Cloud inspections loaded."
        } catch {
            cloudMessage = "Could not load cloud inspections."
        }

        isLoadingCloudData = false
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

    func upsertInspection(_ inspection: Inspection) {
        inspections.removeAll { $0.id == inspection.id }
        inspections.insert(inspection, at: 0)

        if let index = vehicles.firstIndex(where: { $0.id == inspection.vehicleID }) {
            vehicles[index].lastInspectionDate = inspection.date
        }
    }

    func removeInspection(_ inspection: Inspection) {
        inspections.removeAll { $0.id == inspection.id }

        if let vehicleIndex = vehicles.firstIndex(where: { $0.id == inspection.vehicleID }) {
            vehicles[vehicleIndex].lastInspectionDate = inspections
                .filter { $0.vehicleID == inspection.vehicleID }
                .map(\.date)
                .max()
        }
    }

    func removeAllCloudDataLocally() {
        vehicles.removeAll()
        inspections.removeAll()
        cloudMessage = "All cloud data was deleted."
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
