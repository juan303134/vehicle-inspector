import SwiftUI

struct VehicleListView: View {
    @EnvironmentObject private var store: InspectionStore
    @State private var showingAddVehicle = false
    @State private var backendStatus: BackendConnectionStatus = .checking

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        BackendStatusBanner(status: backendStatus) {
                            checkBackendConnection()
                        }
                        summaryStrip

                        VStack(spacing: 12) {
                            ForEach(store.vehicles) { vehicle in
                                NavigationLink(value: vehicle) {
                                    VehicleRow(vehicle: vehicle, inspectionCount: store.inspections(for: vehicle).count)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationDestination(for: Vehicle.self) { vehicle in
                VehicleDetailView(vehicle: vehicle)
            }
            .sheet(isPresented: $showingAddVehicle) {
                AddVehicleView()
            }
            .task {
                checkBackendConnection()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddVehicle = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add vehicle")
                }
            }
        }
    }

    private func checkBackendConnection() {
        backendStatus = .checking

        Task {
            do {
                let health = try await VehicleDamageAnalysisService.shared.checkHealth()
                await MainActor.run {
                    backendStatus = health.hasApiKey
                        ? .connected(model: health.model)
                        : .missingApiKey(model: health.model)
                }
            } catch {
                await MainActor.run {
                    backendStatus = .disconnected
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inspections")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.ink)
            Text("Daily vehicle inspections and possible new damage.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            SummaryMetric(title: "Vehicles", value: "\(store.vehicles.count)", icon: "car.2")
            SummaryMetric(title: "Today", value: "\(store.inspections.filter { Calendar.current.isDateInToday($0.date) }.count)", icon: "checklist")
        }
    }
}

enum BackendConnectionStatus: Equatable {
    case checking
    case connected(model: String)
    case missingApiKey(model: String)
    case disconnected

    var title: String {
        switch self {
        case .checking:
            return "Checking connection"
        case .connected:
            return "AI connected"
        case .missingApiKey:
            return "Backend missing API key"
        case .disconnected:
            return "Backend disconnected"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "Testing connection to your Mac."
        case .connected(let model):
            return "Ready to analyze with \(model)."
        case .missingApiKey:
            return "The server is responding, but OPENAI_API_KEY is missing."
        case .disconnected:
            return "Start the backend on your Mac and check the same WiFi."
        }
    }

    var icon: String {
        switch self {
        case .checking: return "wifi"
        case .connected: return "checkmark.circle.fill"
        case .missingApiKey: return "key.slash"
        case .disconnected: return "wifi.slash"
        }
    }

    var color: Color {
        switch self {
        case .checking: return AppTheme.accent
        case .connected: return .green
        case .missingApiKey: return AppTheme.warning
        case .disconnected: return .red
        }
    }
}

struct BackendStatusBanner: View {
    let status: BackendConnectionStatus
    let onRetry: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                Image(systemName: status.icon)
                    .font(.title3)
                    .foregroundStyle(status.color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(status.color.opacity(0.12))
                        .foregroundStyle(status.color)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Retry connection")
            }
        }
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle
    let inspectionCount: Int

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accent.opacity(0.10))
                    Image(systemName: "car.side")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(vehicle.plate)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.muted)
                    }

                    Text(vehicle.makeModel)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)

                    HStack {
                        StatusPill(text: vehicle.color, systemImage: "paintpalette", color: AppTheme.accent)
                        Text("\(inspectionCount) inspections")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
        }
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        SurfaceCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }
}
