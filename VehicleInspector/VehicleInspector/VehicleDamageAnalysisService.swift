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

    func fetchVehicles() async throws -> [Vehicle] {
        var request = URLRequest(url: vehiclesEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AnalysisError.backendUnavailable
        }

        let cloudResponse = try cloudDecoder.decode(CloudVehiclesResponse.self, from: data)
        return cloudResponse.vehicles.compactMap { $0.vehicle }
    }

    func fetchInspections(vehicleID: UUID) async throws -> [Inspection] {
        let listEndpoint = vehiclesEndpoint
            .appendingPathComponent(vehicleID.uuidString)
            .appendingPathComponent("inspections")

        var request = URLRequest(url: listEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AnalysisError.backendUnavailable
        }

        let list = try cloudDecoder.decode(CloudInspectionListResponse.self, from: data)
        var inspections: [Inspection] = []

        for item in list.inspections {
            if let inspectionID = UUID(uuidString: item.id),
               let inspection = try await fetchInspection(inspectionID: inspectionID) {
                inspections.append(inspection)
            }
        }

        return inspections.sorted { $0.date > $1.date }
    }

    func fetchInspection(inspectionID: UUID) async throws -> Inspection? {
        let endpoint = baseURL
            .appendingPathComponent("inspections")
            .appendingPathComponent(inspectionID.uuidString.lowercased())

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AnalysisError.backendUnavailable
        }

        let cloudResponse = try cloudDecoder.decode(CloudInspectionDetailResponse.self, from: data)
        return cloudResponse.inspection.inspection
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

    func saveVehicle(_ vehicle: Vehicle) async throws {
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

    private var cloudDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = ISO8601DateFormatter.cloud.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid cloud date \(string)")
        }
        return decoder
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

private struct CloudVehiclesResponse: Decodable {
    let vehicles: [CloudVehicle]
}

private struct CloudVehicle: Decodable {
    let id: String
    let plate: String?
    let make: String?
    let model: String?
    let year: Int?
    let color: String?
    let label: String?
    let lastInspectionAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case plate
        case make
        case model
        case year
        case color
        case label
        case lastInspectionAt = "last_inspection_at"
    }

    var vehicle: Vehicle? {
        guard let uuid = UUID(uuidString: id) else { return nil }

        let makeModel = [year.map(String.init), make, model]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return Vehicle(
            id: uuid,
            plate: plate?.isEmpty == false ? plate! : "No plate",
            makeModel: makeModel.isEmpty ? (label ?? "Unknown vehicle") : makeModel,
            color: color?.isEmpty == false ? color! : "Unknown",
            lastInspectionDate: lastInspectionAt
        )
    }
}

private struct CloudInspectionListResponse: Decodable {
    let inspections: [CloudInspectionListItem]
}

private struct CloudInspectionListItem: Decodable {
    let id: String
}

private struct CloudInspectionDetailResponse: Decodable {
    let inspection: CloudInspectionDetail
}

private struct CloudInspectionDetail: Decodable {
    let id: String
    let vehicleID: String
    let status: String
    let odometerText: String?
    let inspectorNotes: String?
    let aiAnalyzed: Bool
    let createdAt: Date
    let photos: [CloudSavedPhoto]
    let findings: [CloudSavedFinding]
    let checklist: [CloudSavedChecklistItem]

    private enum CodingKeys: String, CodingKey {
        case id
        case vehicleID = "vehicle_id"
        case status
        case odometerText = "odometer_text"
        case inspectorNotes = "inspector_notes"
        case aiAnalyzed = "ai_analyzed"
        case createdAt = "created_at"
        case photos
        case findings
        case checklist
    }

    var inspection: Inspection? {
        guard let inspectionID = UUID(uuidString: id),
              let vehicleUUID = UUID(uuidString: vehicleID) else {
            return nil
        }

        let mappedPhotos = photos.compactMap(\.photo)
        let mappedFindings = findings.compactMap(\.finding)
        let mappedChecklist = checklist.compactMap(\.item)

        return Inspection(
            id: inspectionID,
            vehicleID: vehicleUUID,
            date: createdAt,
            photos: mappedPhotos,
            findings: mappedFindings,
            analysisSource: aiAnalyzed ? .ai : .simulated,
            status: InspectionStatus(rawValue: status) ?? .needsReview,
            checklist: mappedChecklist.isEmpty ? InspectionChecklistItem.defaults : mappedChecklist,
            inspectorNotes: inspectorNotes ?? "",
            odometerText: odometerText ?? "",
            odometerImageData: nil
        )
    }
}

private struct CloudSavedPhoto: Decodable {
    let id: String
    let angle: String
    let imageBase64: String?
    let imageURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id
        case angle
        case imageBase64 = "image_base64"
        case imageURL = "image_url"
    }

    var photo: InspectionPhoto? {
        guard let uuid = UUID(uuidString: id),
              let inspectionAngle = InspectionAngle(rawValue: angle) else {
            return nil
        }

        let data = imageBase64.flatMap { Data(base64Encoded: $0) }
        return InspectionPhoto(id: uuid, angle: inspectionAngle, captured: true, imageData: data, imageURL: imageURL)
    }
}

private struct CloudSavedFinding: Decodable {
    let id: String
    let photoID: String?
    let angle: String?
    let type: String
    let severity: String
    let location: String
    let confidence: FlexibleDouble
    let isNew: Bool
    let region: CloudDamageRegion
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case photoID = "photo_id"
        case angle
        case type
        case severity
        case location
        case confidence
        case isNew = "is_new"
        case region
        case note
    }

    var finding: DamageFinding? {
        guard let uuid = UUID(uuidString: id),
              let inspectionAngle = angle.flatMap(InspectionAngle.init(rawValue:)),
              let damageType = DamageType(rawValue: type),
              let damageSeverity = DamageSeverity(rawValue: severity) else {
            return nil
        }

        return DamageFinding(
            id: uuid,
            photoID: photoID.flatMap(UUID.init(uuidString:)),
            angle: inspectionAngle,
            type: damageType,
            severity: damageSeverity,
            location: location,
            confidence: confidence.value,
            isNew: isNew,
            region: DamageRegion(x: region.x, y: region.y, width: region.width, height: region.height),
            note: note ?? ""
        )
    }
}

private struct CloudSavedChecklistItem: Decodable {
    let id: String
    let title: String
    let status: String

    var item: InspectionChecklistItem? {
        InspectionChecklistItem(id: id, title: title, status: ChecklistStatus(rawValue: status) ?? .notChecked)
    }
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

extension CloudDamageRegion: Decodable {}

private struct CloudChecklistItem: Encodable {
    let title: String
    let status: String
    let note: String?
}

private struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let double = try? container.decode(Double.self) {
            value = double
            return
        }

        if let string = try? container.decode(String.self),
           let double = Double(string) {
            value = double
            return
        }

        value = 0
    }
}

private extension ISO8601DateFormatter {
    static let cloud: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
