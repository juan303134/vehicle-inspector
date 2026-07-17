import SwiftUI

@main
struct VehicleInspectorApp: App {
    @StateObject private var store = InspectionStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            VehicleListView()
                .tabItem {
                    Label("Vehicles", systemImage: "car.2")
                }

            InspectionDashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.doc.horizontal")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "car.side.and.exclamationmark")
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(AppTheme.accent.opacity(0.12))
                                        .foregroundStyle(AppTheme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Vehicle Inspector")
                                            .font(.headline)
                                            .foregroundStyle(AppTheme.ink)
                                        Text("AI vehicle damage inspection")
                                            .font(.subheadline)
                                            .foregroundStyle(AppTheme.muted)
                                    }
                                }
                            }
                        }

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Credits", systemImage: "person.crop.circle")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)

                                Text("Created for Juan Bedoya")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)

                                Text("Daily vehicle inspections, AI damage review, cloud reports, and photo storage.")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Cloud stack", systemImage: "icloud")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)

                                VStack(alignment: .leading, spacing: 8) {
                                    SettingsInfoRow(title: "Backend", value: "Render")
                                    SettingsInfoRow(title: "Database", value: "PostgreSQL")
                                    SettingsInfoRow(title: "Photos", value: "Cloudinary")
                                    SettingsInfoRow(title: "Analysis", value: "OpenAI")
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.ink)
        }
        .font(.subheadline)
    }
}
