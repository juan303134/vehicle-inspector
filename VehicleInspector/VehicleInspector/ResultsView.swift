import SwiftUI
import UIKit

struct ResultsView: View {
    @EnvironmentObject private var store: InspectionStore

    let vehicle: Vehicle
    let inspection: Inspection
    @State private var isReanalyzing = false
    @State private var isFocusedAnalyzing = false
    @State private var reanalysisMessage: String?

    private var currentInspection: Inspection {
        store.inspections.first(where: { $0.id == inspection.id }) ?? inspection
    }

    private var activeFindings: [DamageFinding] {
        currentInspection.findings.filter { $0.reviewStatus != .dismissed }
    }

    private var dismissedFindings: [DamageFinding] {
        currentInspection.findings.filter { $0.reviewStatus == .dismissed }
    }

    var newFindings: [DamageFinding] {
        activeFindings.filter(\.isNew)
    }

    var existingFindings: [DamageFinding] {
        activeFindings.filter { !$0.isNew }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    resultHeader
                    analysisStatusCard
                    reportSummary
                    comparisonSummary
                    odometerSummary
                    checklistSummary
                    inspectionNotes
                    visualReview

                    FindingSection(
                        title: "Possible new damage",
                        emptyText: "No new damage detected.",
                        findings: newFindings,
                        onConfirm: confirmFinding,
                        onDismiss: dismissFinding,
                        onSeverityChange: updateFindingSeverity,
                        onNoteChange: updateFindingNote
                    )
                    FindingSection(
                        title: "Previously recorded damage",
                        emptyText: "No previous damage in this inspection.",
                        findings: existingFindings,
                        onConfirm: confirmFinding,
                        onDismiss: dismissFinding,
                        onSeverityChange: updateFindingSeverity,
                        onNoteChange: updateFindingNote
                    )

                    if !dismissedFindings.isEmpty {
                        FindingSection(
                            title: "Dismissed",
                            emptyText: "",
                            findings: dismissedFindings,
                            onConfirm: confirmFinding,
                            onDismiss: dismissFinding,
                            onSeverityChange: updateFindingSeverity,
                            onNoteChange: updateFindingNote
                        )
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resultHeader: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(vehicle.plate)
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(currentInspection.date.shortInspectionDate)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    StatusPill(text: "\(newFindings.count) new", systemImage: "exclamationmark.triangle", color: AppTheme.warning)
                }

                Divider()

                HStack {
                    ResultMetric(title: "Status", value: currentInspection.status.rawValue)
                    ResultMetric(title: "Photos", value: "\(currentInspection.photos.filter(\.captured).count)")
                    ResultMetric(title: "Active", value: "\(activeFindings.count)")
                    ResultMetric(title: "Avg. conf.", value: averageConfidence)
                }

                Button {
                    reanalyzeInspection()
                } label: {
                    Label(isReanalyzing ? "Reanalyzing..." : "Reanalyze", systemImage: isReanalyzing ? "hourglass" : "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(canReanalyze ? AppTheme.accent.opacity(0.12) : AppTheme.line.opacity(0.70))
                        .foregroundStyle(canReanalyze ? AppTheme.accent : AppTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!canReanalyze)
            }
        }
    }

    private var analysisStatusCard: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: currentInspection.analysisSource.icon)
                    .font(.title3)
                    .foregroundStyle(currentInspection.analysisSource.color)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text(currentInspection.analysisSource.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(reanalysisMessage ?? currentInspection.analysisSource.detail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
    }

    private var reportSummary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Inspection report", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    StatusPill(text: currentInspection.status.rawValue, systemImage: currentInspection.status.icon, color: currentInspection.status.color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ReportLine(label: "Vehicle", value: "\(vehicle.plate) · \(vehicle.makeModel)")
                    ReportLine(label: "Date", value: currentInspection.date.shortInspectionDate)
                    ReportLine(label: "Photos", value: "\(currentInspection.photos.filter(\.captured).count)")
                    ReportLine(label: "Confirmed", value: "\(currentInspection.findings.filter { $0.reviewStatus == .confirmed }.count)")
                    ReportLine(label: "Needs review", value: "\(currentInspection.findings.filter { $0.reviewStatus == .pending }.count)")
                    ReportLine(label: "Dismissed", value: "\(dismissedFindings.count)")
                }
            }
        }
    }

    private var comparisonSummary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Before vs after", systemImage: "rectangle.split.2x1")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                if let previousInspection {
                    Text("Compared with \(previousInspection.date.shortInspectionDate). New findings are marked separately from previously recorded damage.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)

                    HStack {
                        ResultMetric(title: "Previous findings", value: "\(previousInspection.findings.count)")
                        ResultMetric(title: "Current findings", value: "\(currentInspection.findings.count)")
                        ResultMetric(title: "Possible new", value: "\(newFindings.count)")
                    }
                } else {
                    Text("No earlier inspection is available for this vehicle yet.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private var odometerSummary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Odometer", systemImage: "gauge.with.dots.needle.50percent")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(currentInspection.odometerText.isEmpty ? "Not entered" : currentInspection.odometerText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }

                if let data = currentInspection.odometerImageData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var checklistSummary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Checklist", systemImage: "checklist")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    StatusPill(text: "\(currentInspection.checklist.filter { $0.status != .notChecked }.count)/\(currentInspection.checklist.count)", systemImage: "checkmark", color: AppTheme.accent)
                }

                ForEach(currentInspection.checklist) { item in
                    HStack {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Menu {
                            ForEach(ChecklistStatus.allCases) { status in
                                Button(status.rawValue) {
                                    store.updateChecklistItem(inspectionID: currentInspection.id, itemID: item.id, status: status)
                                }
                            }
                        } label: {
                            StatusPill(text: item.status.rawValue, systemImage: item.status.icon, color: item.status.color)
                        }
                    }
                }
            }
        }
    }

    private var inspectionNotes: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Inspector notes", systemImage: "note.text")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                TextField(
                    "Add inspection notes",
                    text: Binding(
                        get: { currentInspection.inspectorNotes },
                        set: { store.updateInspectionNotes(inspectionID: currentInspection.id, notes: $0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var visualReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visual review")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            ForEach(InspectionAngle.allCases) { angle in
                let anglePhotos = currentInspection.photos.filter { $0.angle == angle && $0.captured }
                if !anglePhotos.isEmpty {
                    ForEach(Array(anglePhotos.enumerated()), id: \.element.id) { index, photo in
                        DamagePhotoCard(
                            angle: angle,
                            photoNumber: index + 1,
                            photoCount: anglePhotos.count,
                            photo: photo,
                            findings: findings(for: photo, in: anglePhotos),
                            isFocusedAnalyzing: isFocusedAnalyzing,
                            onFocusedAnalyze: analyzeFocusedArea
                        )
                    }
                }
            }
        }
    }

    private var averageConfidence: String {
        guard !activeFindings.isEmpty else { return "0%" }
        let average = activeFindings.map(\.confidence).reduce(0, +) / Double(activeFindings.count)
        return "\(Int(average * 100))%"
    }

    private var previousInspection: Inspection? {
        store.inspections(for: vehicle).first { $0.id != currentInspection.id && $0.date < currentInspection.date }
    }

    private var canReanalyze: Bool {
        !isReanalyzing && !isFocusedAnalyzing && currentInspection.photos.contains { $0.captured && $0.imageData != nil }
    }

    private func confirmFinding(_ finding: DamageFinding) {
        store.updateFindingStatus(inspectionID: currentInspection.id, findingID: finding.id, status: .confirmed)
    }

    private func dismissFinding(_ finding: DamageFinding) {
        store.updateFindingStatus(inspectionID: currentInspection.id, findingID: finding.id, status: .dismissed)
    }

    private func updateFindingSeverity(_ finding: DamageFinding, severity: DamageSeverity) {
        store.updateFindingSeverity(inspectionID: currentInspection.id, findingID: finding.id, severity: severity)
    }

    private func updateFindingNote(_ finding: DamageFinding, note: String) {
        store.updateFindingNote(inspectionID: currentInspection.id, findingID: finding.id, note: note)
    }

    private func reanalyzeInspection() {
        guard canReanalyze else { return }

        isReanalyzing = true
        reanalysisMessage = nil

        let photos = currentInspection.photos.filter { $0.captured && $0.imageData != nil }

        Task {
            do {
                let findings = try await VehicleDamageAnalysisService.shared.analyze(photos: photos)
                await MainActor.run {
                    store.replaceAnalysis(inspectionID: currentInspection.id, findings: findings, source: .ai)
                    reanalysisMessage = "Reanalysis completed with artificial intelligence."
                    isReanalyzing = false
                }
            } catch {
                await MainActor.run {
                    reanalysisMessage = "AI reanalysis did not finish. Existing results were kept."
                    isReanalyzing = false
                }
            }
        }
    }

    private func analyzeFocusedArea(photo: InspectionPhoto, region: CGRect) {
        guard !isFocusedAnalyzing,
              let imageData = photo.imageData,
              let image = UIImage(data: imageData),
              let croppedImage = image.cropped(toNormalized: region),
              let croppedData = croppedImage.jpegData(compressionQuality: 0.96) else {
            return
        }

        isFocusedAnalyzing = true
        reanalysisMessage = "Analyzing selected area with artificial intelligence."

        let focusedPhoto = InspectionPhoto(id: photo.id, angle: photo.angle, captured: true, imageData: croppedData)

        Task {
            do {
                let findings = try await VehicleDamageAnalysisService.shared.analyze(photos: [focusedPhoto])
                let mappedFindings = findings.map { finding in
                    DamageFinding(
                        id: UUID(),
                        photoID: photo.id,
                        angle: photo.angle,
                        type: finding.type,
                        severity: finding.severity,
                        location: "Selected area · \(finding.location)",
                        confidence: finding.confidence,
                        isNew: finding.isNew,
                        region: DamageRegion(
                            x: min(max(region.minX + finding.region.x * region.width, 0), 1),
                            y: min(max(region.minY + finding.region.y * region.height, 0), 1),
                            width: min(max(finding.region.width * region.width, 0.01), 1),
                            height: min(max(finding.region.height * region.height, 0.01), 1)
                        )
                    )
                }

                await MainActor.run {
                    store.appendFindings(inspectionID: currentInspection.id, findings: mappedFindings, source: .ai)
                    reanalysisMessage = mappedFindings.isEmpty ? "Selected area was analyzed with AI. No damage was detected." : "Selected area was analyzed with AI and added to the review."
                    isFocusedAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    reanalysisMessage = "AI focused analysis failed. Try a tighter or clearer area."
                    isFocusedAnalyzing = false
                }
            }
        }
    }

    private func findings(for photo: InspectionPhoto, in anglePhotos: [InspectionPhoto]) -> [DamageFinding] {
        let firstPhotoID = anglePhotos.first?.id

        return activeFindings.filter { finding in
            guard finding.angle == photo.angle else { return false }

            if let photoID = finding.photoID {
                return photoID == photo.id
            }

            return photo.id == firstPhotoID
        }
    }
}

struct ResultMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReportLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DamagePhotoCard: View {
    let angle: InspectionAngle
    let photoNumber: Int
    let photoCount: Int
    let photo: InspectionPhoto
    let findings: [DamageFinding]
    let isFocusedAnalyzing: Bool
    let onFocusedAnalyze: (InspectionPhoto, CGRect) -> Void

    @State private var showingPhotoViewer = false

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(photoCount > 1 ? "\(angle.rawValue) \(photoNumber)" : angle.rawValue, systemImage: angle.icon)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    StatusPill(text: findings.isEmpty ? "No damage" : "\(findings.count) detected", systemImage: findings.isEmpty ? "checkmark" : "scope", color: findings.isEmpty ? .green : AppTheme.warning)
                }

                ZStack {
                    if let image = uiImage {
                        Button {
                            showingPhotoViewer = true
                        } label: {
                            AspectFitDamageImage(image: image, findings: findings)
                        }
                        .buttonStyle(.plain)

                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(.black.opacity(0.58))
                                    .clipShape(Circle())
                                    .padding(10)
                            }
                            Spacer()
                        }
                    } else {
                        ZStack {
                            Color(red: 0.17, green: 0.20, blue: 0.22)
                            Image(systemName: angle.icon)
                                .font(.system(size: 58, weight: .light))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.line, lineWidth: 1)
                }

                if findings.isEmpty {
                    Text("No damage was marked in this photo.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .frame(width: 22, height: 22)
                                    .background(finding.isNew ? AppTheme.warning : AppTheme.accent)
                                    .foregroundStyle(.white)
                                    .clipShape(Circle())

                                Text("\(finding.type.rawValue) · \(finding.location)")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(2)

                                Spacer()

                                if finding.reviewStatus == .confirmed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingPhotoViewer) {
            if let image = uiImage {
                DamagePhotoViewer(
                    angle: angle,
                    photo: photo,
                    image: image,
                    findings: findings,
                    isFocusedAnalyzing: isFocusedAnalyzing,
                    onFocusedAnalyze: onFocusedAnalyze
                )
            }
        }
    }

    private var uiImage: UIImage? {
        guard let imageData = photo.imageData else { return nil }
        return UIImage(data: imageData)
    }
}

struct DamagePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss

    let angle: InspectionAngle
    let photo: InspectionPhoto
    let image: UIImage
    let findings: [DamageFinding]
    let isFocusedAnalyzing: Bool
    let onFocusedAnalyze: (InspectionPhoto, CGRect) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isSelectingArea = false
    @State private var selectionStart: CGPoint?
    @State private var selectedRegion: CGRect?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let imageRect = fittedImageRect(imageSize: image.size, containerSize: proxy.size)

                ZStack(alignment: .topLeading) {
                    AspectFitDamageImage(image: image, findings: findings)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .gesture(isSelectingArea ? nil : zoomGesture.simultaneously(with: dragGesture))
                        .onTapGesture(count: 2) {
                            guard !isSelectingArea else { return }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                if scale > 1.05 {
                                    resetZoom()
                                } else {
                                    scale = 2.2
                                    lastScale = scale
                                }
                            }
                        }

                    if isSelectingArea {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()

                        Rectangle()
                            .stroke(.white.opacity(0.86), style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                            .frame(width: imageRect.width, height: imageRect.height)
                            .offset(x: imageRect.minX, y: imageRect.minY)

                        if let selectedRegion {
                            let rect = displayRect(for: selectedRegion, in: imageRect)
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(AppTheme.warning, lineWidth: 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AppTheme.warning.opacity(0.22))
                                )
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(isSelectingArea ? selectionGesture(in: imageRect) : nil)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.16))
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(angle.rawValue)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(findings.isEmpty ? "No damage detected" : "\(findings.count) marked damage item(s)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isSelectingArea.toggle()
                            resetZoom()
                            selectedRegion = nil
                            selectionStart = nil
                        }
                    } label: {
                        Image(systemName: isSelectingArea ? "hand.draw.fill" : "square.dashed")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background((isSelectingArea ? AppTheme.warning : Color.white).opacity(isSelectingArea ? 0.82 : 0.16))
                            .clipShape(Circle())
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            resetZoom()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.16))
                            .clipShape(Circle())
                    }
                    .disabled(scale == 1 && offset == .zero)
                    .opacity(scale == 1 && offset == .zero ? 0.45 : 1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(.black.opacity(0.58))

                Spacer()

                if isSelectingArea {
                    VStack(spacing: 10) {
                        Text("Drag over the damage area, then analyze the selection.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            Button {
                                selectedRegion = nil
                                selectionStart = nil
                            } label: {
                                Label("Clear", systemImage: "xmark")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(.white.opacity(0.14))
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            Button {
                                guard let selectedRegion else { return }
                                onFocusedAnalyze(photo, selectedRegion)
                                dismiss()
                            } label: {
                                Label(isFocusedAnalyzing ? "Analyzing..." : "Analyze area", systemImage: isFocusedAnalyzing ? "hourglass" : "scope")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(canAnalyzeSelection ? AppTheme.warning : Color.white.opacity(0.14))
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .disabled(!canAnalyzeSelection)
                        }
                    }
                    .padding(18)
                    .background(.black.opacity(0.64))
                }

                if !findings.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                                HStack(spacing: 6) {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .frame(width: 22, height: 22)
                                        .background(finding.isNew ? AppTheme.warning : AppTheme.accent)
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())

                                    Text(finding.type.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.58))
                }
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
            }
            .onEnded { _ in
                if scale <= 1.02 {
                    resetZoom()
                } else {
                    lastScale = scale
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private var canAnalyzeSelection: Bool {
        guard let selectedRegion else { return false }
        return !isFocusedAnalyzing && selectedRegion.width >= 0.03 && selectedRegion.height >= 0.03
    }

    private func selectionGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let currentPoint = clampedPoint(value.location, in: imageRect)
                let startPoint = selectionStart ?? currentPoint
                selectionStart = startPoint
                selectedRegion = normalizedRect(from: startPoint, to: currentPoint, in: imageRect)
            }
            .onEnded { value in
                let currentPoint = clampedPoint(value.location, in: imageRect)
                if let selectionStart {
                    selectedRegion = normalizedRect(from: selectionStart, to: currentPoint, in: imageRect)
                }
                selectionStart = nil
            }
    }

    private func clampedPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint, in imageRect: CGRect) -> CGRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)

        return CGRect(
            x: min(max((minX - imageRect.minX) / imageRect.width, 0), 1),
            y: min(max((minY - imageRect.minY) / imageRect.height, 0), 1),
            width: min(max((maxX - minX) / imageRect.width, 0), 1),
            height: min(max((maxY - minY) / imageRect.height, 0), 1)
        )
    }

    private func displayRect(for normalizedRect: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalizedRect.minX * imageRect.width,
            y: imageRect.minY + normalizedRect.minY * imageRect.height,
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
    }

    private func fittedImageRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        let fittedSize: CGSize

        if imageAspect > containerAspect {
            fittedSize = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            fittedSize = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }

        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

struct AspectFitDamageImage: View {
    let image: UIImage
    let findings: [DamageFinding]

    var body: some View {
        GeometryReader { proxy in
            let imageRect = aspectFitRect(imageSize: image.size, containerSize: proxy.size)

            ZStack(alignment: .topLeading) {
                Color.black

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                ZStack(alignment: .topLeading) {
                    ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                        DamageOverlayMarker(index: index + 1, finding: finding, size: imageRect.size)
                    }
                }
                .frame(width: imageRect.width, height: imageRect.height)
                .offset(x: imageRect.minX, y: imageRect.minY)
            }
        }
    }

    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        let fittedSize: CGSize

        if imageAspect > containerAspect {
            fittedSize = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            fittedSize = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }

        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

struct DamageOverlayMarker: View {
    let index: Int
    let finding: DamageFinding
    let size: CGSize

    var body: some View {
        let rect = CGRect(
            x: finding.region.x * size.width,
            y: finding.region.y * size.height,
            width: finding.region.width * size.width,
            height: finding.region.height * size.height
        )

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(markerColor, lineWidth: 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(markerColor.opacity(0.14))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            Text("\(index)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(markerColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
                .position(x: rect.minX, y: rect.minY)
        }
    }

    private var markerColor: Color {
        finding.isNew ? AppTheme.warning : AppTheme.accent
    }
}

struct FindingSection: View {
    let title: String
    let emptyText: String
    let findings: [DamageFinding]
    let onConfirm: (DamageFinding) -> Void
    let onDismiss: (DamageFinding) -> Void
    let onSeverityChange: (DamageFinding, DamageSeverity) -> Void
    let onNoteChange: (DamageFinding, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if findings.isEmpty {
                SurfaceCard {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(findings) { finding in
                    FindingRow(
                        finding: finding,
                        onConfirm: onConfirm,
                        onDismiss: onDismiss,
                        onSeverityChange: onSeverityChange,
                        onNoteChange: onNoteChange
                    )
                }
            }
        }
    }
}

struct FindingRow: View {
    let finding: DamageFinding
    let onConfirm: (DamageFinding) -> Void
    let onDismiss: (DamageFinding) -> Void
    let onSeverityChange: (DamageFinding, DamageSeverity) -> Void
    let onNoteChange: (DamageFinding, String) -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: finding.angle.icon)
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(finding.type.rawValue)
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text("\(Int(finding.confidence * 100))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.muted)
                        }

                        Text(finding.location)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)

                        HStack {
                            Menu {
                                ForEach(DamageSeverity.allCases) { severity in
                                    Button(severity.rawValue) {
                                        onSeverityChange(finding, severity)
                                    }
                                }
                            } label: {
                                StatusPill(text: finding.severity.rawValue, systemImage: "gauge.with.dots.needle.50percent", color: finding.severity.color)
                            }
                            StatusPill(text: finding.angle.rawValue, systemImage: "viewfinder", color: AppTheme.accent)
                            StatusPill(text: finding.reviewStatus.rawValue, systemImage: finding.reviewStatus.icon, color: finding.reviewStatus.color)
                        }
                    }
                }

                TextField(
                    "Add finding note",
                    text: Binding(
                        get: { finding.note },
                        set: { onNoteChange(finding, $0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        onConfirm(finding)
                    } label: {
                        Label(finding.reviewStatus == .confirmed ? "Confirmed" : "Confirm", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background((finding.reviewStatus == .confirmed ? Color.green : AppTheme.accent).opacity(0.10))
                            .foregroundStyle(finding.reviewStatus == .confirmed ? .green : AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(finding.reviewStatus == .confirmed)

                    Button {
                        onDismiss(finding)
                    } label: {
                        Label(finding.reviewStatus == .dismissed ? "Dismissed" : "Dismiss", systemImage: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.line.opacity(0.70))
                            .foregroundStyle(AppTheme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private extension UIImage {
    func cropped(toNormalized region: CGRect) -> UIImage? {
        guard let cgImage else { return nil }

        let clampedRegion = CGRect(
            x: min(max(region.minX, 0), 1),
            y: min(max(region.minY, 0), 1),
            width: min(max(region.width, 0.01), 1),
            height: min(max(region.height, 0.01), 1)
        )

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: clampedRegion.minX * pixelWidth,
            y: clampedRegion.minY * pixelHeight,
            width: min(clampedRegion.width * pixelWidth, pixelWidth - clampedRegion.minX * pixelWidth),
            height: min(clampedRegion.height * pixelHeight, pixelHeight - clampedRegion.minY * pixelHeight)
        ).integral

        guard cropRect.width > 1,
              cropRect.height > 1,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: scale, orientation: imageOrientation)
    }
}
