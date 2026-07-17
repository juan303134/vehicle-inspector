import SwiftUI

struct VehicleDetailView: View {
    @EnvironmentObject private var store: InspectionStore
    let vehicle: Vehicle

    var currentVehicle: Vehicle {
        store.vehicles.first(where: { $0.id == vehicle.id }) ?? vehicle
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    vehicleHeader

                    VStack(spacing: 10) {
                        NavigationLink {
                            CaptureFlowView(vehicle: currentVehicle, mode: .guided)
                        } label: {
                            Label("New inspection", systemImage: "camera.viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.accent)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        NavigationLink {
                            CaptureFlowView(vehicle: currentVehicle, mode: .free)
                        } label: {
                            Label("Free analysis", systemImage: "viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .foregroundStyle(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
                                }
                        }
                    }

                    Text("History")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .padding(.top, 6)

                    HStack {
                        if store.isLoadingCloudData {
                            Label("Loading cloud history...", systemImage: "icloud.and.arrow.down")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.muted)
                        } else {
                            Label("Cloud history", systemImage: "icloud")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.muted)
                        }

                        Spacer()

                        Button {
                            loadCloudHistory()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background(AppTheme.accent.opacity(0.12))
                                .foregroundStyle(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityLabel("Refresh cloud history")
                    }

                    if store.inspections(for: currentVehicle).isEmpty {
                        EmptyHistoryView()
                    } else {
                        ForEach(store.inspections(for: currentVehicle)) { inspection in
                            NavigationLink {
                                ResultsView(vehicle: currentVehicle, inspection: inspection)
                            } label: {
                                InspectionHistoryRow(inspection: inspection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle(currentVehicle.plate)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: currentVehicle.id) {
            await store.loadCloudInspections(for: currentVehicle)
        }
    }

    private func loadCloudHistory() {
        Task {
            await store.loadCloudInspections(for: currentVehicle)
        }
    }

    private var vehicleHeader: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentVehicle.makeModel)
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text("Color \(currentVehicle.color)")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "car.side")
                        .font(.title)
                        .foregroundStyle(AppTheme.accent)
                }

                Divider()

                HStack {
                    Label(lastInspectionText, systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                }
            }
        }
    }

    private var lastInspectionText: String {
        guard let date = currentVehicle.lastInspectionDate else {
            return "No inspections yet"
        }

        return "Last inspection: \(date.shortInspectionDate)"
    }
}

struct InspectionHistoryRow: View {
    let inspection: Inspection

    var body: some View {
        SurfaceCard {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(inspection.date.shortInspectionDate)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("\(inspection.photos.count) photos · \(inspection.findings.count) findings")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                StatusPill(text: "\(inspection.findings.filter(\.isNew).count) new", systemImage: "sparkle.magnifyingglass", color: AppTheme.warning)
            }
        }
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        SurfaceCard {
            VStack(spacing: 10) {
                Image(systemName: "camera.metering.unknown")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.accent)
                Text("No inspections yet")
                    .font(.headline)
                Text("Take the four base photos to create the first vehicle record.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
