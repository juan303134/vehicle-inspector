import Foundation

struct VehicleDamageAnalysisService {
    static let shared = VehicleDamageAnalysisService()

    private let baseURL = URL(string: "https://vehicle-inspector-zgsi.onrender.com")!

    private var analyzeEndpoint: URL {
        baseURL.appendingPathComponent("analyze")
    }

    private var healthEndpoint: URL {
        baseURL.appendingPathComponent("health")
    }

    private var vehiclesEndpoint: URL {
        baseURL.appendingPathComponent("vehicles")
    }

    func checkHealth() async throws -> BackendHealth {
        var request = URLRequest(url: healthEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AnalysisError.backendUnavailable
        }

        return try JSONDecoder().decode(BackendHealth.self, from: data)
    }

    func analyze(photos: [InspectionPhoto]) async throws -> [DamageFinding] {
        let payload = AnalysisRequest(
            photos: photos.compactMap { photo in
                guard let imageData = photo.imageData else { return nil }
                return AnalysisPhoto(id: photo.id.uuidString, angle: photo.angle.rawValue, imageBase64: imageData.base64EncodedString())
            }
        )

        var request = URLRequest(url: analyzeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 360
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AnalysisError.backendUnavailable
        }

        let analysis = try JSONDecoder().decode(AnalysisResponse.self, from: data)

        return analysis.findings.compactMap { finding in
            guard
                let angle = InspectionAngle(rawValue: finding.angle),
                let type = DamageType(rawValue: finding.type),
                let severity = DamageSeverity(rawValue: finding.severity)
            else {
                return nil
            }

            return DamageFinding(
                id: UUID(),
                photoID: UUID(uuidString: finding.photoID),
                angle: angle,
                type: type,
                severity: severity,
                location: finding.location,
                confidence: finding.confidence,
                isNew: finding.isNew,
                region: DamageRegion(
                    x: finding.region.x,
                    y: finding.region.y,
                    width: finding.region.width,
                    height: finding.region.height
                )
            )
        }
    }

    func saveInspection(vehicle: Vehicle, inspection: Inspection) async throws {
        try await saveVehicle(vehicle)

        let endpoint = vehiclesEndpoint
            .appendingPathComponent(vehicle.id.uuidString)
            .appendingPathComponent("inspections")

        let payload = CloudInspectionRequest(
            status: inspection.status.rawValue,
            odometerText: inspection.odometerText,
            inspectorNotes: inspection.inspectorNotes,
            aiAnalyzed: inspection.analysisSource == .ai,
            summary: CloudInspectionSummary(
                inspectionID: inspection.id.uuidString,
                photoCount: inspection.photos.filter(\.captured).count,
                findingCount: inspection.findings.count
            ),
            photos: inspection.photos.compactMap { photo in
                guard let imageData = photo.imageData else { return nil }
                return CloudInspectionPhoto(
                    id: photo.id.uuidString,
                    angle: photo.angle.rawValue,
                    imageBase64: imageData.base64EncodedString()
                )
            },
            findings: inspection.findings.map { finding in
                CloudDamageFinding(
                    photoID: finding.photoID?.uuidString,
                    angle: finding.angle.rawValue,
                    type: finding.type.rawValue,
                    severity: finding.severity.rawValue,
                    location: finding.location,
                    confidence: finding.confidence,
                    isNew: finding.isNew,
                    region: CloudDamageRegion(
                        x: finding.region.x,
                        y: finding.region.y,
                        width: finding.region.width,
                        height: finding.region.height
                    ),
                    note: finding.note
                )
            },
            checklist: inspection.checklist.map { item in
                CloudChecklistItem(
                    title: item.title,
                    status: item.status.rawValue,
                    note: nil
                )
            }
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 360
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AnalysisError.backendUnavailable
        }
    }

    private func saveVehicle(_ vehicle: Vehicle) async throws {
        let parts = vehicle.makeModel.split(separator: " ", maxSplits: 1).map(String.init)
        let payload = CloudVehicleRequest(
            id: vehicle.id.uuidString,
            label: "\(vehicle.plate) \(vehicle.makeModel)",
            plate: vehicle.plate,
            make: parts.first,
            model: parts.count > 1 ? parts[1] : nil,
            year: nil,
            color: vehicle.color
        )

        var request = URLRequest(url: vehiclesEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AnalysisError.backendUnavailable
        }
    }
}

enum AnalysisError: Error {
    case backendUnavailable
}

struct BackendHealth: Decodable {
    let ok: Bool
    let model: String
    let hasApiKey: Bool

    private enum CodingKeys: String, CodingKey {
        case ok
        case model
        case models
        case workingModel
        case hasApiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        hasApiKey = try container.decode(Bool.self, forKey: .hasApiKey)

        let workingModel = try container.decodeIfPresent(String.self, forKey: .workingModel)
        let model = try container.decodeIfPresent(String.self, forKey: .model)
        let models = try container.decodeIfPresent([String].self, forKey: .models)
        self.model = workingModel ?? model ?? models?.first ?? "AI"
    }
}

private struct AnalysisRequest: Encodable {
    let photos: [AnalysisPhoto]
}

private struct AnalysisPhoto: Encodable {
    let id: String
    let angle: String
    let imageBase64: String
}

private struct AnalysisResponse: Decodable {
    let findings: [AnalysisFinding]
}

private struct AnalysisFinding: Decodable {
    let photoID: String
    let angle: String
    let type: String
    let severity: String
    let location: String
    let confidence: Double
    let isNew: Bool
    let region: AnalysisRegion
}

private struct AnalysisRegion: Decodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct CloudVehicleRequest: Encodable {
    let id: String
    let label: String
    let plate: String
    let make: String?
    let model: String?
    let year: Int?
    let color: String
}

private struct CloudInspectionRequest: Encodable {
    let status: String
    let odometerText: String
    let inspectorNotes: String
    let aiAnalyzed: Bool
    let summary: CloudInspectionSummary
    let photos: [CloudInspectionPhoto]
    let findings: [CloudDamageFinding]
    let checklist: [CloudChecklistItem]
}

private struct CloudInspectionSummary: Encodable {
    let inspectionID: String
    let photoCount: Int
    let findingCount: Int
}

private struct CloudInspectionPhoto: Encodable {
    let id: String
    let angle: String
    let imageBase64: String
}

private struct CloudDamageFinding: Encodable {
    let photoID: String?
    let angle: String
    let type: String
    let severity: String
    let location: String
    let confidence: Double
    let isNew: Bool
    let region: CloudDamageRegion
    let note: String
}

private struct CloudDamageRegion: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct CloudChecklistItem: Encodable {
    let title: String
    let status: String
    let note: String?
}
