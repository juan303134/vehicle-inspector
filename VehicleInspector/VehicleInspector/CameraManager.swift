import AVFoundation
import UIKit

enum CameraLens: String, CaseIterable, Identifiable {
    case ultraWide = "0.5x"
    case wide = "1x"
    case telephoto = "2x"

    var id: String { rawValue }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }

    var title: String {
        switch self {
        case .ultraWide: return "Wide"
        case .wide: return "Standard"
        case .telephoto: return "Tele"
        }
    }
}

final class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    @Published var lastError: String?
    @Published var availableLenses: [CameraLens] = [.wide]
    @Published var selectedLens: CameraLens = .wide
    @Published var zoomFactor: CGFloat = 1
    @Published var minimumZoomFactor: CGFloat = 1
    @Published var maximumZoomFactor: CGFloat = 6

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "vehicle-inspector.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
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

    func selectLens(_ lens: CameraLens) {
        guard availableLenses.contains(lens) else { return }

        sessionQueue.async { [weak self] in
            self?.switchCamera(to: lens)
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let currentDevice else { return }
            let clampedFactor = min(max(factor, self.minimumZoomFactor), self.maximumZoomFactor)

            do {
                try currentDevice.lockForConfiguration()
                currentDevice.videoZoomFactor = clampedFactor
                currentDevice.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.zoomFactor = clampedFactor
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = "Could not adjust camera zoom."
                }
            }
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

            let lenses = self.detectAvailableLenses()
            let lens = lenses.contains(.wide) ? CameraLens.wide : (lenses.first ?? .wide)

            guard self.addCameraInput(for: lens),
                  self.session.canAddOutput(self.photoOutput) else {
                DispatchQueue.main.async {
                    self.lastError = "Could not start the camera."
                }
                return
            }

            self.session.addOutput(self.photoOutput)
            self.isConfigured = true

            DispatchQueue.main.async {
                self.availableLenses = lenses.isEmpty ? [.wide] : lenses
                self.selectedLens = lens
                self.updateZoomState()
            }
        }
    }

    private func detectAvailableLenses() -> [CameraLens] {
        CameraLens.allCases.filter { lens in
            AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) != nil
        }
    }

    private func addCameraInput(for lens: CameraLens) -> Bool {
        guard
            let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return false
        }

        session.addInput(input)
        currentInput = input
        currentDevice = device
        configureZoom(for: device, resetToMinimum: true)
        return true
    }

    private func switchCamera(to lens: CameraLens) {
        guard isConfigured, selectedLens != lens else { return }

        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        if let currentInput {
            session.removeInput(currentInput)
        }

        guard addCameraInput(for: lens) else {
            if let currentInput, session.canAddInput(currentInput) {
                session.addInput(currentInput)
            }
            return
        }

        DispatchQueue.main.async {
            self.selectedLens = lens
            self.updateZoomState()
        }
    }

    private func configureZoom(for device: AVCaptureDevice, resetToMinimum: Bool) {
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 8)
        let minZoom: CGFloat = 1
        let requestedZoom = resetToMinimum ? minZoom : min(max(zoomFactor, minZoom), maxZoom)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = requestedZoom
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async {
                self.lastError = "Could not configure camera zoom."
            }
        }
    }

    private func updateZoomState() {
        guard let currentDevice else { return }
        minimumZoomFactor = 1
        maximumZoomFactor = min(currentDevice.activeFormat.videoMaxZoomFactor, 8)
        zoomFactor = currentDevice.videoZoomFactor
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
