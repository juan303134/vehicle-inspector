import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onImagesPicked: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.dismiss()
                return
            }

            let group = DispatchGroup()
            var selectedImages = Array<UIImage?>(repeating: nil, count: results.count)

            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                    continue
                }

                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    selectedImages[index] = object as? UIImage
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.parent.onImagesPicked(selectedImages.compactMap { $0 })
                self.parent.dismiss()
            }
        }
    }
}
