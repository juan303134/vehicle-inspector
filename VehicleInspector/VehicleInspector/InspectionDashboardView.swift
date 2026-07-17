import SwiftUI

struct InspectionDashboardView: View {
    @EnvironmentObject private var store: InspectionStore
    @State private var selectedVehicleID: UUID?
    @State private var selectedDateFilter: DashboardDateFilter = .all
    @State private var selectedSeverity: DamageSeverity?
    @State private var selectedComparison: DamageComparisonStatus?
    @State private var selectedReviewStatus: FindingReviewStatus?

    private var filteredFindings: [DashboardFinding] {
        store.inspections.flatMap { inspection in
            inspection.findings.compactMap { finding in
                guard let vehicle = store.vehicles.first(where: { $0.id == inspection.vehicleID }) else {
                    return nil
                }

                return DashboardFinding(vehicle: vehicle, inspection: inspection, finding: finding)
            }
        }
        .filter { item in
            (selectedVehicleID == nil || item.vehicle.id == selectedVehicleID) &&
            selectedDateFilter.includes(item.inspection.date) &&
            (selectedSeverity == nil || item.finding.severity == selectedSeverity) &&
            (selectedComparison == nil || item.finding.comparisonStatus == selectedComparison) &&
            (selectedReviewStatus == nil || item.finding.reviewStatus == selectedReviewStatus)
        }
        .sorted { left, right in
            if left.finding.severity.rank != right.finding.severity.rank {
                return left.finding.severity.rank > right.finding.severity.rank
            }

            return left.inspection.date > right.inspection.date
        }
    }

    private var filteredInspections: [Inspection] {
        store.inspections
            .filter { inspection in
                (selectedVehicleID == nil || inspection.vehicleID == selectedVehicleID) &&
                selectedDateFilter.includes(inspection.date)
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        metrics
                        filters
                        findingsSection
                        inspectionsSection
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.inspections.isEmpty {
                    await store.loadAllCloudData()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await store.loadAllCloudData()
                        }
                    } label: {
                        Image(systemName: store.isLoadingCloudData ? "hourglass" : "arrow.clockwise")
                    }
                    .disabled(store.isLoadingCloudData)
                    .accessibilityLabel("Refresh dashboard")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inspection Dashboard")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.ink)
            Text("Filter damage findings by vehicle, date, severity, review state, and change type.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metrics: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SummaryMetric(title: "Findings", value: "\(filteredFindings.count)", icon: "scope")
                SummaryMetric(title: "High", value: "\(filteredFindings.filter { $0.finding.severity == .high }.count)", icon: "exclamationmark.triangle")
            }

            HStack(spacing: 10) {
                SummaryMetric(title: "New", value: "\(filteredFindings.filter { $0.finding.comparisonStatus == .new }.count)", icon: "sparkle.magnifyingglass")
                SummaryMetric(title: "Changed", value: "\(filteredFindings.filter { $0.finding.comparisonStatus == .changed }.count)", icon: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var filters: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Picker("Vehicle", selection: $selectedVehicleID) {
                    Text("All vehicles").tag(UUID?.none)
                    ForEach(store.vehicles) { vehicle in
                        Text(vehicle.displayName).tag(Optional(vehicle.id))
                    }
                }
                .pickerStyle(.menu)

                Picker("Date", selection: $selectedDateFilter) {
                    ForEach(DashboardDateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                FilterMenu(
                    title: "Severity",
                    value: selectedSeverity?.rawValue ?? "All",
                    systemImage: "gauge.with.dots.needle.50percent",
                    color: selectedSeverity?.color ?? AppTheme.accent
                ) {
                    Button("All") { selectedSeverity = nil }
                    ForEach(DamageSeverity.allCases) { severity in
                        Button(severity.rawValue) { selectedSeverity = severity }
                    }
                }

                FilterMenu(
                    title: "Change type",
                    value: selectedComparison?.shortLabel ?? "All",
                    systemImage: selectedComparison?.icon ?? "rectangle.split.2x1",
                    color: selectedComparison?.color ?? AppTheme.accent
                ) {
                    Button("All") { selectedComparison = nil }
                    Button(DamageComparisonStatus.new.rawValue) { selectedComparison = .new }
                    Button(DamageComparisonStatus.changed.rawValue) { selectedComparison = .changed }
                    Button(DamageComparisonStatus.existing.rawValue) { selectedComparison = .existing }
                }

                FilterMenu(
                    title: "Review state",
                    value: selectedReviewStatus?.rawValue ?? "All",
                    systemImage: selectedReviewStatus?.icon ?? "checklist",
                    color: selectedReviewStatus?.color ?? AppTheme.accent
                ) {
                    Button("All") { selectedReviewStatus = nil }
                    Button(FindingReviewStatus.pending.rawValue) { selectedReviewStatus = .pending }
                    Button(FindingReviewStatus.confirmed.rawValue) { selectedReviewStatus = .confirmed }
                    Button(FindingReviewStatus.dismissed.rawValue) { selectedReviewStatus = .dismissed }
                }
            }
        }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filtered findings")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if filteredFindings.isEmpty {
                SurfaceCard {
                    Text(store.isLoadingCloudData ? "Loading dashboard data." : "No findings match these filters.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(filteredFindings) { item in
                    NavigationLink {
                        ResultsView(vehicle: item.vehicle, inspection: item.inspection)
                    } label: {
                        DashboardFindingRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var inspectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent inspections")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            ForEach(filteredInspections.prefix(6)) { inspection in
                if let vehicle = store.vehicles.first(where: { $0.id == inspection.vehicleID }) {
                    NavigationLink {
                        ResultsView(vehicle: vehicle, inspection: inspection)
                    } label: {
                        DashboardInspectionRow(vehicle: vehicle, inspection: inspection)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct DashboardFinding: Identifiable {
    let vehicle: Vehicle
    let inspection: Inspection
    let finding: DamageFinding

    var id: String {
        "\(inspection.id.uuidString)-\(finding.id.uuidString)"
    }
}

enum DashboardDateFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case week = "7 days"
    case month = "30 days"

    var id: String { rawValue }

    func includes(_ date: Date) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return Calendar.current.isDateInToday(date)
        case .week:
            return date >= Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? date
        case .month:
            return date >= Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? date
        }
    }
}

struct FilterMenu<Content: View>: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Menu {
                content
            } label: {
                StatusPill(text: value, systemImage: "chevron.down", color: color)
            }
        }
    }
}

struct DashboardFindingRow: View {
    let item: DashboardFinding

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.vehicle.displayName) · \(item.finding.type.rawValue)")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text(item.finding.location)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(2)
                    }
                    Spacer()
                    StatusPill(text: item.finding.severity.rawValue, systemImage: "gauge.with.dots.needle.50percent", color: item.finding.severity.color)
                }

                HStack(spacing: 8) {
                    StatusPill(text: item.finding.comparisonStatus.shortLabel, systemImage: item.finding.comparisonStatus.icon, color: item.finding.comparisonStatus.color)
                    StatusPill(text: item.finding.reviewStatus.rawValue, systemImage: item.finding.reviewStatus.icon, color: item.finding.reviewStatus.color)
                }

                HStack {
                    Label(item.inspection.date.shortInspectionDate, systemImage: "calendar")
                    Spacer()
                    Label(item.finding.angle.rawValue, systemImage: item.finding.angle.icon)
                }
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            }
        }
    }
}

struct DashboardInspectionRow: View {
    let vehicle: Vehicle
    let inspection: Inspection

    var body: some View {
        SurfaceCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("\(inspection.date.shortInspectionDate) · \(inspection.photos.count) photos")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                StatusPill(text: "\(inspection.findings.count) findings", systemImage: "scope", color: AppTheme.accent)
            }
        }
    }
}

private extension DamageSeverity {
    var rank: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
}
