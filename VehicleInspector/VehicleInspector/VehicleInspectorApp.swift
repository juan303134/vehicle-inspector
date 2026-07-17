import SwiftUI

@main
struct VehicleInspectorApp: App {
    @StateObject private var store = InspectionStore()

    var body: some Scene {
        WindowGroup {
            VehicleListView()
                .environmentObject(store)
        }
    }
}
