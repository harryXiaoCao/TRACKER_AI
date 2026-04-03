import AVKit
import SwiftUI

struct WorkspaceDeckView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            HeroPanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tracker AI")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("Commercialization-ready native macOS shell for motion tracking, review, and reproducible exports.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.86))

                    HStack(spacing: 10) {
                        Button("Upload Video", action: openVideo)
                            .buttonStyle(PrimaryActionButtonStyle())
                        Button("Load Saved Session", action: loadSession)
                            .buttonStyle(GhostActionButtonStyle())
                        Toggle("Advanced Mode", isOn: $model.advancedMode)
                            .toggleStyle(.switch)
                            .foregroundStyle(Color.white)
                    }
                }
            }

            HStack(spacing: 16) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Workspace")
                        Text("Active clips")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TrackerTheme.ink)
                        ForEach(model.workspaceClips) { clip in
                            Button(action: { model.activateWorkspaceClip(clip) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(clip.label)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(clip.sessionPath.isEmpty ? clip.videoPath : clip.sessionPath)
                                            .font(.system(size: 11))
                                            .foregroundStyle(TrackerTheme.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if clip.videoPath == model.currentVideoURL?.path {
                                        StatusPill(text: "Active", tone: TrackerTheme.success)
                                    }
                                }
                                .padding(12)
                                .background(TrackerTheme.steel.opacity(0.45))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HeroPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Current Trial")
                        Text(model.currentTrialHeadline)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text(model.currentTrialContext)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 210)

            TrackerPanel {
                HStack(spacing: 10) {
                    ForEach(["1 Video", "2 Range", "3 Scale", "4 Target", "5 Review"], id: \.self) { step in
                        Text(step)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TrackerTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(TrackerTheme.steel.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
            }

            TrackerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionEyebrow(text: "Live Video Workspace")
                            Text(model.selectionMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(TrackerTheme.muted)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button("Step -1", action: stepBackward)
                                .buttonStyle(GhostActionButtonStyle())
                            Button("Step +1", action: stepForward)
                                .buttonStyle(GhostActionButtonStyle())
                        }
                    }
                    VideoWorkspaceView(model: model)
                        .frame(minHeight: 420)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(alignment: .top, spacing: 16) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Instrument HUD")
                        if model.trackBundles.count > 1 {
                            Picker(
                                "Track",
                                selection: Binding(
                                    get: { model.activeTrackID },
                                    set: { model.activateAnalysisTrack($0) }
                                )
                            ) {
                                ForEach(model.trackBundles) { bundle in
                                    Text("\(bundle.trackName) [\(bundle.trackKind)]").tag(bundle.trackID)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        WorkspaceMetricRow(label: "Frame", value: "\(model.currentFrame)")
                        WorkspaceMetricRow(label: "Time", value: model.currentFrameTimestampText)
                        WorkspaceMetricRow(label: "Track", value: model.currentFrameTrackName)
                        WorkspaceMetricRow(label: "State", value: model.currentFrameStateText)
                        WorkspaceMetricRow(label: "Tracker", value: model.currentFrameConfidenceText)
                        WorkspaceMetricRow(label: "Scientific", value: model.currentFrameScientificConfidenceText)
                        WorkspaceMetricRow(label: "BBox", value: model.currentFrameBBoxText)
                        WorkspaceMetricRow(label: "Speed", value: model.currentFrameSpeedText)
                        WorkspaceMetricRow(label: "Accel", value: model.currentFrameAccelerationText)
                        WorkspaceMetricRow(label: "Reference", value: model.currentFrameReferenceText)
                        WorkspaceMetricRow(label: "Engine", value: model.engineState.rawValue)
                    }
                }
                .frame(width: 280)

                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Range + Review Controls")
                        HStack(spacing: 8) {
                            Button("Use This Frame", action: useCurrentFrameAsStart)
                                .buttonStyle(GhostActionButtonStyle())
                            Button("Use As End", action: useCurrentFrameAsEnd)
                                .buttonStyle(GhostActionButtonStyle())
                            Button("Next Problem", action: jumpNextProblem)
                                .buttonStyle(GhostActionButtonStyle())
                                .disabled(!model.canNavigateToNextReviewIssue)
                            Button("Next Correction", action: jumpNextCorrection)
                                .buttonStyle(GhostActionButtonStyle())
                                .disabled(!model.canNavigateToNextCorrection)
                        }
                        HStack(spacing: 8) {
                            Button("Jump Overview", action: jumpOverview)
                                .buttonStyle(GhostActionButtonStyle())
                            Button("Jump Setup", action: jumpSetup)
                                .buttonStyle(GhostActionButtonStyle())
                            Button("Jump Review", action: jumpReview)
                                .buttonStyle(GhostActionButtonStyle())
                            Button("Jump Results", action: jumpResults)
                                .buttonStyle(GhostActionButtonStyle())
                        }
                        Text(model.statusMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TrackerTheme.ink)
                    }
                }
            }

            TrackerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionEyebrow(text: "Timeline")
                    Text("Frame \(model.currentFrame) / \(model.endFrame)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TrackerTheme.ink)
                    Slider(
                        value: Binding(
                            get: { Double(model.currentFrame) },
                            set: { model.setCurrentFrame(from: $0) }
                        ),
                        in: Double(model.startFrame)...model.maxFrame
                    )
                }
            }
        }
    }

    private func openVideo() {
        model.openVideo()
    }

    private func loadSession() {
        model.loadSession()
    }

    private func stepBackward() {
        model.stepFrame(by: -1)
    }

    private func stepForward() {
        model.stepFrame(by: 1)
    }

    private func useCurrentFrameAsStart() {
        model.setStartFrameToCurrentFrame()
    }

    private func useCurrentFrameAsEnd() {
        model.setEndFrameToCurrentFrame()
    }

    private func jumpNextProblem() {
        model.jumpToNextProblemFrame()
    }

    private func jumpNextCorrection() {
        model.jumpToNextCorrectionFrame()
    }

    private func jumpOverview() {
        model.selectedTab = .overview
    }

    private func jumpSetup() {
        model.selectedTab = .setup
    }

    private func jumpReview() {
        model.selectedTab = .review
    }

    private func jumpResults() {
        model.selectedTab = .results
    }
}

private struct VideoWorkspaceView: View {
    @Bindable var model: AppModel
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.06))

            if let player = model.player {
                GeometryReader { proxy in
                    let videoRect = aspectFitRect(content: model.sourceVideoSize, in: proxy.size)

                    MacVideoPlayerView(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            overlayBadges
                        }
                        .overlay {
                            ZStack(alignment: .topLeading) {
                                annotationContent(videoRect: videoRect)
                                if model.annotationMode != .idle {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .frame(width: videoRect.width, height: videoRect.height)
                                        .position(x: videoRect.midX, y: videoRect.midY)
                                        .gesture(drawingGesture(videoRect: videoRect))
                                }
                            }
                        }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(TrackerTheme.muted)
                    Text("No video loaded")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(TrackerTheme.ink)
                    Text("Open a video or activate a workspace clip to populate the native tracking workspace.")
                        .font(.system(size: 14))
                        .foregroundStyle(TrackerTheme.muted)
                }
            }
        }
    }

    private var overlayBadges: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusPill(text: model.engineState.rawValue, tone: badgeColor)
            if model.isScaleReady { StatusPill(text: "Calibration Ready", tone: TrackerTheme.accent) }
            if model.isTargetReady { StatusPill(text: "Target Ready", tone: TrackerTheme.success) }
            if model.isReferenceReady { StatusPill(text: "Reference Ready", tone: TrackerTheme.navy) }
            if !model.additionalObjects.isEmpty { StatusPill(text: "\(model.additionalObjects.count) Companion Object(s)", tone: TrackerTheme.navy) }
            if model.annotationMode != .idle {
                StatusPill(text: "Drawing \(model.annotationMode.rawValue.capitalized)", tone: TrackerTheme.warning)
            }
        }
        .padding(18)
    }

    private var badgeColor: Color {
        switch model.engineState {
        case .ready: return TrackerTheme.success
        case .running: return TrackerTheme.warning
        case .unavailable: return TrackerTheme.critical
        }
    }

    @ViewBuilder
    private func annotationContent(videoRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            if let rect = model.targetBox.cgRect {
                let displayRect = videoRectForDisplay(rect, videoRect: videoRect)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TrackerTheme.success, lineWidth: 3)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
            }

            if let rect = model.referenceBox.cgRect {
                let displayRect = videoRectForDisplay(rect, videoRect: videoRect)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TrackerTheme.navy, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
                    .overlay(alignment: .topLeading) {
                        Text("Reference")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TrackerTheme.navy)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.92))
                            .clipShape(Capsule())
                            .padding(8)
                    }
            }

            ForEach(model.additionalObjects) { object in
                if let rect = CGRect(
                    x: Double(object.x) ?? -1,
                    y: Double(object.y) ?? -1,
                    width: Double(object.width) ?? -1,
                    height: Double(object.height) ?? -1
                ).validRect {
                    let displayRect = videoRectForDisplay(rect, videoRect: videoRect)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TrackerTheme.navy, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                        .frame(width: displayRect.width, height: displayRect.height)
                        .position(x: displayRect.midX, y: displayRect.midY)
                }
            }

            if let points = model.scaleLine.points {
                Path { path in
                    path.move(to: displayPoint(for: points.0, videoRect: videoRect))
                    path.addLine(to: displayPoint(for: points.1, videoRect: videoRect))
                }
                .stroke(TrackerTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }

            ForEach(model.corrections) { correction in
                if correction.frameIndex == model.currentFrame, let rect = correction.bbox.cgRect {
                    let displayRect = videoRectForDisplay(rect, videoRect: videoRect)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TrackerTheme.warning, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                        .frame(width: displayRect.width, height: displayRect.height)
                        .position(x: displayRect.midX, y: displayRect.midY)
                }
            }

            previewShape(videoRect: videoRect)
        }
    }

    @ViewBuilder
    private func previewShape(videoRect: CGRect) -> some View {
        if let dragStart, let dragCurrent {
            switch model.annotationMode {
            case .target, .reference, .correction, .companion:
                let rect = normalizedRect(from: dragStart, to: dragCurrent)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(previewColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            case .scale:
                Path { path in
                    path.move(to: dragStart)
                    path.addLine(to: dragCurrent)
                }
                .stroke(TrackerTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [10, 6]))
            case .idle:
                EmptyView()
            }
        }
    }

    private func drawingGesture(videoRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let clampedStart = clamp(point: value.startLocation, to: videoRect)
                let clampedCurrent = clamp(point: value.location, to: videoRect)
                dragStart = clampedStart
                dragCurrent = clampedCurrent
            }
            .onEnded { value in
                let start = clamp(point: value.startLocation, to: videoRect)
                let end = clamp(point: value.location, to: videoRect)
                commitDrawing(from: start, to: end, videoRect: videoRect)
                dragStart = nil
                dragCurrent = nil
            }
    }

    private func commitDrawing(from start: CGPoint, to end: CGPoint, videoRect: CGRect) {
        let displayBounds = normalizedRect(from: start, to: end)
        guard model.annotationMode == .scale || (displayBounds.width > 2 && displayBounds.height > 2) else {
            return
        }
        switch model.annotationMode {
        case .target:
            let videoBounds = videoRectToVideo(displayBounds, videoRect: videoRect)
            model.applyDrawnTargetBox(videoBounds)
        case .reference:
            let videoBounds = videoRectToVideo(displayBounds, videoRect: videoRect)
            model.applyDrawnReferenceBox(videoBounds)
        case .scale:
            let videoStart = videoPoint(fromDisplay: start, videoRect: videoRect)
            let videoEnd = videoPoint(fromDisplay: end, videoRect: videoRect)
            model.applyDrawnScaleLine(videoStart, videoEnd)
        case .correction:
            let videoBounds = videoRectToVideo(displayBounds, videoRect: videoRect)
            model.applyDrawnCorrection(videoBounds)
        case .companion:
            let videoBounds = videoRectToVideo(displayBounds, videoRect: videoRect)
            model.applyDrawnAdditionalObject(videoBounds)
        case .idle:
            break
        }
    }

    private var previewColor: Color {
        switch model.annotationMode {
        case .target:
            return TrackerTheme.success
        case .reference:
            return TrackerTheme.navy
        case .correction:
            return TrackerTheme.warning
        case .companion:
            return TrackerTheme.navy
        case .scale, .idle:
            return TrackerTheme.accent
        }
    }

    private func aspectFitRect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / content.width, container.height / content.height)
        let width = content.width * scale
        let height = content.height * scale
        let origin = CGPoint(x: (container.width - width) / 2, y: (container.height - height) / 2)
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func clamp(point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func videoRectToVideo(_ displayRect: CGRect, videoRect: CGRect) -> CGRect {
        let origin = videoPoint(fromDisplay: displayRect.origin, videoRect: videoRect)
        let opposite = videoPoint(
            fromDisplay: CGPoint(x: displayRect.maxX, y: displayRect.maxY),
            videoRect: videoRect
        )
        return CGRect(
            x: min(origin.x, opposite.x),
            y: min(origin.y, opposite.y),
            width: abs(opposite.x - origin.x),
            height: abs(opposite.y - origin.y)
        )
    }

    private func videoPoint(fromDisplay point: CGPoint, videoRect: CGRect) -> CGPoint {
        let normalizedX = (point.x - videoRect.minX) / max(videoRect.width, 1)
        let normalizedY = (point.y - videoRect.minY) / max(videoRect.height, 1)
        return CGPoint(
            x: normalizedX * model.sourceVideoSize.width,
            y: normalizedY * model.sourceVideoSize.height
        )
    }

    private func displayPoint(for videoPoint: CGPoint, videoRect: CGRect) -> CGPoint {
        CGPoint(
            x: videoRect.minX + (videoPoint.x / max(model.sourceVideoSize.width, 1)) * videoRect.width,
            y: videoRect.minY + (videoPoint.y / max(model.sourceVideoSize.height, 1)) * videoRect.height
        )
    }

    private func videoRectForDisplay(_ videoSpaceRect: CGRect, videoRect: CGRect) -> CGRect {
        let origin = displayPoint(for: videoSpaceRect.origin, videoRect: videoRect)
        let opposite = displayPoint(
            for: CGPoint(x: videoSpaceRect.maxX, y: videoSpaceRect.maxY),
            videoRect: videoRect
        )
        return CGRect(
            x: min(origin.x, opposite.x),
            y: min(origin.y, opposite.y),
            width: abs(opposite.x - origin.x),
            height: abs(opposite.y - origin.y)
        )
    }
}

private struct MacVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

private extension CGRect {
    var validRect: CGRect? {
        guard width > 0, height > 0 else { return nil }
        return self
    }
}

private struct WorkspaceMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TrackerTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TrackerTheme.ink)
        }
    }
}
