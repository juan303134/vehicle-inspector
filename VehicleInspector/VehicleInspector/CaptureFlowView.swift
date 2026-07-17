import SwiftUI
import UIKit

enum CaptureMode {
    case guided
    case free

    var title: String {
        switch self {
        case .guided: return "Guided capture"
        case .free: return "Free analysis"
        }
    }

    var analyzeButtonTitle: String {
        switch self {
        case .guided: return "Analyze inspection"
        case .free: return "Analyze photos"
        }
    }
}

private enum CapturePickerTarget {
    case vehiclePhoto
    case odometer
}

struct CaptureFlowView: View {
    @EnvironmentObject private var store: InspectionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraManager()

    let vehicle: Vehicle
    let mode: CaptureMode

    @State private var selectedAngle: InspectionAngle = .front
    @State private var capturedImages: [InspectionAngle: [Data]] = [:]
    @State private var createdInspection: Inspection?
    @State private var showingResults = false
    @State private var showingImagePicker = false
    @State private var pickerTarget: CapturePickerTarget = .vehiclePhoto
    @State private var isAnalyzing = false
    @State private var analysisMessage: String?
    @State private var checklistItems = InspectionChecklistItem.defaults
    @State private var inspectorNotes = ""
    @State private var odometerText = ""
    @State private var odometerImageData: Data?
    @State private var cloudSaveMessage: String?
    @State private var lastPinchZoom: CGFloat = 1
    @State private var selectedAnalysisMode: AnalysisMode = .accurate

    init(vehicle: Vehicle, mode: CaptureMode = .guided) {
        self.vehicle = vehicle
        self.mode = mode
        _selectedAngle = State(initialValue: mode == .free ? .free : .front)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        progressHeader
                        cameraCapture
                        analysisModeSection
                        if let analysisMessage {
                            analysisNotice(analysisMessage)
                        }
                        if let cloudSaveMessage {
                            cloudSaveNotice(cloudSaveMessage)
                        }
                        if mode == .guided {
                            odometerSection
                            checklistSection
                            notesSection
                        }
                        if mode == .guided {
                            angleChecklist
                        }
                    }
                    .padding(18)
                }

                footer
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .navigationDestination(isPresented: $showingResults) {
            if let createdInspection {
                ResultsView(vehicle: vehicle, inspection: createdInspection)
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: .photoLibrary) { image in
                switch pickerTarget {
                case .vehiclePhoto:
                    saveCapturedImage(image)
                case .odometer:
                    saveOdometerImage(image)
                }
            }
        }
    }

    private var progressHeader: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vehicle.displayName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text(progressText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    CircularProgressView(progress: progressValue)
                }

                ProgressView(value: progressValue)
                    .tint(AppTheme.accent)
            }
        }
    }

    private var cameraCapture: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(selectedAngle.rawValue, systemImage: selectedAngle.icon)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                StatusPill(text: "\(photoCount(for: selectedAngle)) photo(s)", systemImage: hasPhotos(for: selectedAngle) ? "checkmark" : "clock", color: hasPhotos(for: selectedAngle) ? .green : AppTheme.warning)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.18), Color(red: 0.24, green: 0.29, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing))

                if camera.isAuthorized && camera.isCameraAvailable {
                    CameraPreview(session: camera.session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if let uiImage = selectedUIImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: selectedAngle.icon)
                            .font(.system(size: 72, weight: .light))
                            .foregroundStyle(.white.opacity(0.84))

                        Text(cameraPlaceholderText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }

                if camera.isAuthorized && camera.isCameraAvailable {
                    VStack {
                        Spacer()
                        cameraControlBar
                    }
                }
            }
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .simultaneousGesture(cameraZoomGesture)

            selectedPhotoStrip

            HStack(spacing: 10) {
                if mode == .guided {
                    Button {
                        moveToPreviousAngle()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 48, height: 54)
                            .background(canMoveToPreviousAngle ? AppTheme.line.opacity(0.8) : AppTheme.line.opacity(0.35))
                            .foregroundStyle(canMoveToPreviousAngle ? AppTheme.ink : AppTheme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(!canMoveToPreviousAngle)
                    .accessibilityLabel("Previous angle")
                }

                Button {
                    takePhoto()
                } label: {
                    Label(hasPhotos(for: selectedAngle) ? "Add another" : "Take photo", systemImage: "camera")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(camera.isAuthorized && camera.isCameraAvailable ? AppTheme.ink : AppTheme.line)
                        .foregroundStyle(camera.isAuthorized && camera.isCameraAvailable ? .white : AppTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!camera.isAuthorized || !camera.isCameraAvailable)

                Button {
                    pickerTarget = .vehiclePhoto
                    showingImagePicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.headline)
                        .frame(width: 54, height: 54)
                        .background(AppTheme.accent.opacity(0.10))
                        .foregroundStyle(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Upload photo")

                if mode == .guided {
                    Button {
                        moveToNextAngle()
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .font(.headline)
                            .frame(width: 86, height: 54)
                            .background(canMoveToNextAngle ? AppTheme.accent.opacity(0.12) : AppTheme.line.opacity(0.35))
                            .foregroundStyle(canMoveToNextAngle ? AppTheme.accent : AppTheme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(!canMoveToNextAngle)
                }
            }
        }
    }

    private var cameraControlBar: some View {
        VStack(spacing: 10) {
            if camera.availableLenses.count > 1 {
                HStack(spacing: 8) {
                    ForEach(camera.availableLenses) { lens in
                        Button {
                            camera.selectLens(lens)
                            lastPinchZoom = 1
                        } label: {
                            VStack(spacing: 2) {
                                Text(lens.rawValue)
                                    .font(.subheadline.weight(.bold))
                                Text(lens.title)
                                    .font(.caption2.weight(.semibold))
                            }
                            .frame(minWidth: 58)
                            .padding(.vertical, 8)
                            .background(camera.selectedLens == lens ? Color.white : Color.white.opacity(0.14))
                            .foregroundStyle(camera.selectedLens == lens ? Color.black : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.76))

                Slider(
                    value: Binding(
                        get: { Double(camera.zoomFactor) },
                        set: { camera.setZoomFactor(CGFloat($0)) }
                    ),
                    in: Double(camera.minimumZoomFactor)...Double(camera.maximumZoomFactor)
                )
                .tint(.white)

                Text(String(format: "%.1fx", camera.zoomFactor))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44)
            }
        }
        .padding(12)
        .background(.black.opacity(0.54))
    }

    private var cameraZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let nextZoom = lastPinchZoom * value
                camera.setZoomFactor(nextZoom)
            }
            .onEnded { _ in
                lastPinchZoom = camera.zoomFactor
            }
    }

    private var odometerSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Odometer", systemImage: "gauge.with.dots.needle.50percent")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    StatusPill(text: odometerImageData == nil ? "Optional photo" : "Photo saved", systemImage: odometerImageData == nil ? "camera" : "checkmark", color: odometerImageData == nil ? AppTheme.muted : .green)
                }

                TextField("Mileage reading", text: $odometerText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    if let odometerImage {
                        Image(uiImage: odometerImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 86, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        takeOdometerPhoto()
                    } label: {
                        Label(odometerImageData == nil ? "Take odometer photo" : "Retake photo", systemImage: "camera")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(camera.isAuthorized && camera.isCameraAvailable ? AppTheme.ink : AppTheme.line)
                            .foregroundStyle(camera.isAuthorized && camera.isCameraAvailable ? .white : AppTheme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(!camera.isAuthorized || !camera.isCameraAvailable)

                    Button {
                        pickerTarget = .odometer
                        showingImagePicker = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                            .font(.headline)
                            .frame(width: 46, height: 46)
                            .background(AppTheme.accent.opacity(0.10))
                            .foregroundStyle(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("Upload odometer photo")
                }
            }
        }
    }

    private var analysisModeSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Analysis mode", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Picker("Analysis mode", selection: $selectedAnalysisMode) {
                    ForEach(AnalysisMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedAnalysisMode.subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    private var checklistSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Inspection checklist")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    StatusPill(text: "\(checklistItems.filter { $0.status != .notChecked }.count)/\(checklistItems.count)", systemImage: "checklist", color: AppTheme.accent)
                }

                ForEach($checklistItems) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)

                        HStack(spacing: 8) {
                            ForEach(ChecklistStatus.allCases) { status in
                                Button {
                                    item.status = status
                                } label: {
                                    Label(status.rawValue, systemImage: status.icon)
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(item.status == status ? status.color.opacity(0.14) : AppTheme.line.opacity(0.55))
                                        .foregroundStyle(item.status == status ? status.color : AppTheme.muted)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var notesSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Inspector notes", systemImage: "note.text")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                TextField("Add inspection notes", text: $inspectorNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var angleChecklist: some View {
        VStack(spacing: 10) {
            ForEach(InspectionAngle.allCases) { angle in
                Button {
                    selectedAngle = angle
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: hasPhotos(for: angle) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(hasPhotos(for: angle) ? .green : AppTheme.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(angle.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text(hasPhotos(for: angle) ? "\(photoCount(for: angle)) saved photo(s)" : angle.instruction)
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: angle.icon)
                            .foregroundStyle(selectedAngle == angle ? AppTheme.accent : AppTheme.muted)
                    }
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedAngle == angle ? AppTheme.accent : AppTheme.line, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                analyzeInspection()
            } label: {
                Label(isAnalyzing ? "Analyzing..." : mode.analyzeButtonTitle, systemImage: isAnalyzing ? "hourglass" : "sparkle.magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAnalyze ? AppTheme.accent : AppTheme.line)
                    .foregroundStyle(canAnalyze ? .white : AppTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(!canAnalyze)
        }
        .padding(18)
        .background(.white)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.line)
                .frame(height: 1)
        }
    }

    private func moveToNextAngle() {
        guard mode == .guided,
              let index = requiredAngles.firstIndex(of: selectedAngle) else { return }
        let nextIndex = requiredAngles.index(after: index)
        if nextIndex < requiredAngles.endIndex {
            selectedAngle = requiredAngles[nextIndex]
        }
    }

    private func moveToPreviousAngle() {
        guard mode == .guided,
              let index = requiredAngles.firstIndex(of: selectedAngle),
              index > requiredAngles.startIndex else { return }
        let previousIndex = requiredAngles.index(before: index)
        selectedAngle = requiredAngles[previousIndex]
    }

    private var canMoveToNextAngle: Bool {
        guard mode == .guided,
              let index = requiredAngles.firstIndex(of: selectedAngle) else { return false }
        return requiredAngles.index(after: index) < requiredAngles.endIndex
    }

    private var canMoveToPreviousAngle: Bool {
        guard mode == .guided,
              let index = requiredAngles.firstIndex(of: selectedAngle) else { return false }
        return index > requiredAngles.startIndex
    }

    private var selectedUIImage: UIImage? {
        guard let imageData = capturedImages[selectedAngle]?.last else { return nil }
        return UIImage(data: imageData)
    }

    private var odometerImage: UIImage? {
        guard let odometerImageData else { return nil }
        return UIImage(data: odometerImageData)
    }

    private var canAnalyze: Bool {
        if isAnalyzing {
            return false
        }

        switch mode {
        case .guided:
            return completedAngleCount == requiredAngles.count
        case .free:
            return totalPhotoCount > 0
        }
    }

    private var completedAngleCount: Int {
        requiredAngles.filter { hasPhotos(for: $0) }.count
    }

    private var totalPhotoCount: Int {
        capturedImages.values.reduce(0) { $0 + $1.count }
    }

    private var requiredAngles: [InspectionAngle] {
        mode == .guided ? InspectionAngle.guidedAngles : [.free]
    }

    private var progressValue: Double {
        switch mode {
        case .guided:
            return Double(completedAngleCount) / Double(requiredAngles.count)
        case .free:
            return totalPhotoCount > 0 ? 1 : 0
        }
    }

    private var progressText: String {
        switch mode {
        case .guided:
            return "\(completedAngleCount) of \(requiredAngles.count) angles ready · \(totalPhotoCount) photos"
        case .free:
            return totalPhotoCount == 0 ? "Take or upload a photo to analyze" : "\(totalPhotoCount) photo(s) ready to analyze"
        }
    }

    private var selectedPhotoStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let images = capturedImages[selectedAngle], !images.isEmpty {
                HStack {
                    Text("\(selectedAngle.rawValue) photos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text("\(images.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, imageData in
                            if let image = UIImage(data: imageData) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 78, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Text("\(index + 1)")
                                        .font(.caption2.bold())
                                        .frame(width: 20, height: 20)
                                        .background(AppTheme.accent)
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())
                                        .padding(4)

                                    Button {
                                        deletePhoto(at: index)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2.bold())
                                            .frame(width: 22, height: 22)
                                            .background(Color.red)
                                            .foregroundStyle(.white)
                                            .clipShape(Circle())
                                    }
                                    .offset(x: 7, y: -7)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func analysisNotice(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppTheme.warning)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppTheme.muted)
            Spacer()
        }
        .padding(12)
        .background(AppTheme.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cloudSaveNotice(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud")
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppTheme.muted)
            Spacer()
        }
        .padding(12)
        .background(AppTheme.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cameraPlaceholderText: String {
        if !camera.isCameraAvailable {
            return "Camera unavailable on this device. You can upload a photo."
        }

        if !camera.isAuthorized {
            return "Enable camera permission to take photos inside the app."
        }

        return camera.lastError ?? "Preparing camera..."
    }

    private func takePhoto() {
        camera.capturePhoto { image in
            guard let image else { return }
            saveCapturedImage(image)
        }
    }

    private func saveCapturedImage(_ image: UIImage) {
        let optimizedImage = image.resizedForAnalysis(maxDimension: 3200)
        guard let imageData = optimizedImage.jpegData(compressionQuality: 0.94) else { return }
        capturedImages[selectedAngle, default: []].append(imageData)
    }

    private func takeOdometerPhoto() {
        camera.capturePhoto { image in
            guard let image else { return }
            saveOdometerImage(image)
        }
    }

    private func saveOdometerImage(_ image: UIImage) {
        let optimizedImage = image.resizedForAnalysis(maxDimension: 1800)
        odometerImageData = optimizedImage.jpegData(compressionQuality: 0.92)
    }

    private func analyzeInspection() {
        let photos = requiredAngles.flatMap { angle in
            (capturedImages[angle] ?? []).map { imageData in
                InspectionPhoto(id: UUID(), angle: angle, captured: true, imageData: imageData, imageURL: nil)
            }
        }

        let inspection = store.startAnalysis(
            for: vehicle,
            photos: photos,
            mode: selectedAnalysisMode,
            checklist: checklistItems,
            inspectorNotes: inspectorNotes,
            odometerText: odometerText,
            odometerImageData: odometerImageData
        )

        createdInspection = inspection
        isAnalyzing = false
        cloudSaveMessage = "Analysis is running in the background."
        showingResults = true
    }

    private func hasPhotos(for angle: InspectionAngle) -> Bool {
        photoCount(for: angle) > 0
    }

    private func photoCount(for angle: InspectionAngle) -> Int {
        capturedImages[angle]?.count ?? 0
    }

    private func deletePhoto(at index: Int) {
        guard var images = capturedImages[selectedAngle], images.indices.contains(index) else { return }
        images.remove(at: index)

        if images.isEmpty {
            capturedImages.removeValue(forKey: selectedAngle)
        } else {
            capturedImages[selectedAngle] = images
        }
    }
}

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.line, lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.ink)
        }
        .frame(width: 54, height: 54)
    }
}

private extension UIImage {
    func resizedForAnalysis(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
