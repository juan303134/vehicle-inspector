import SwiftUI

struct AddVehicleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InspectionStore

    @State private var plate = ""
    @State private var vanNumber = ""
    @State private var makeModel = ""
    @State private var color = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle details") {
                    TextField("Van number", text: $vanNumber)
                        .keyboardType(.numberPad)
                    TextField("Plate (optional)", text: $plate)
                        .textInputAutocapitalization(.characters)
                    TextField("Make and model (optional)", text: $makeModel)
                    TextField("Color (optional)", text: $color)
                }

                Section {
                    Text("Only one identifier is required. Van number, plate, make/model, or color is enough to create the vehicle.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
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
                        let vehicle = store.addVehicle(plate: plate, vanNumber: vanNumber, makeModel: makeModel, color: color)
                        Task {
                            try? await VehicleDamageAnalysisService.shared.saveVehicle(vehicle)
                            await store.loadCloudVehicles()
                        }
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        [plate, vanNumber, makeModel, color].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
