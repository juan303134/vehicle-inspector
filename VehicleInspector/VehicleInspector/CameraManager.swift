import AVFoundation
import UIKit

final class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    @Published var lastError: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "vehicle-inspector.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private var isConfigured = false

    override init() {
        super.init()
        checkPermission()
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.configureIfNeeded()
                    }
                }
            }
        default:
            isAuthorized = false
            lastError = "Camera permission denied."
        }
    }

    func start() {
        guard isCameraAvailable else { return }
        configureIfNeeded()
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard isConfigured else {
            completion(nil)
            return
        }

        captureCompletion = completion

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureIfNeeded() {
        guard isCameraAvailable, isAuthorized, !isConfigured else { return }

        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            defer {
                self.session.commitConfiguration()
            }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput)
            else {
                DispatchQueue.main.async {
                    self.lastError = "Could not start the camera."
                }
                return
            }

            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.isConfigured = true
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = error.localizedDescription
                self?.captureCompletion?(nil)
                self?.captureCompletion = nil
            }
            return
        }

        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))

        DispatchQueue.main.async { [weak self] in
            self?.captureCompletion?(image)
            self?.captureCompletion = nil
        }
    }
}
