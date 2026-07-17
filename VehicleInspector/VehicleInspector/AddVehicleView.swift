import SwiftUI

struct AddVehicleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InspectionStore

    @State private var plate = ""
    @State private var makeModel = ""
    @State private var color = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle details") {
                    TextField("Plate", text: $plate)
                        .textInputAutocapitalization(.characters)
                    TextField("Make and model", text: $makeModel)
                    TextField("Color", text: $color)
                }
            }
            .navigationTitle("New vehicle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let vehicle = store.addVehicle(plate: plate, makeModel: makeModel, color: color)
                        Task {
                            try? await VehicleDamageAnalysisService.shared.saveVehicle(vehicle)
                            await store.loadCloudVehicles()
                        }
                        dismiss()
                    }
                    .disabled(plate.trimmingCharacters(in: .whitespaces).isEmpty || makeModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
