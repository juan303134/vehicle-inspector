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
        }
    }
}
