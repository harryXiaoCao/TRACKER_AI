import AVFoundation
import AVKit
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var selectedTab: LabTab = .overview
    var selectedResultsTab: ResultsSubtab = .insights
    var engineState: EngineState = .ready
    var statusMessage = "Native shell ready. Import a video or load a Python session to begin."
    var selectionMessage = "Choose a preset, then calibrate and define the target box."
    var analysisProgressFraction = 0.0

    var presets = ResearchPreset.all
    var selectedPresetID = ResearchPreset.all.first?.id ?? "general"

    var workspaceClips: [WorkspaceClip] = []
    var currentVideoURL: URL?
    var sourceVideoMetadata: NativeVideoMetadata?
    var player: AVPlayer?
    var sourceVideoSize = CGSize(width: 1920, height: 1080)

    var experimentLabel = ""
    var trialID = ""
    var operatorName = ""
    var notes = ""
    var tags = ""

    var startFrame = 0
    var endFrame = 240
    var currentFrame = 0
    var playbackFPS = 30.0

    var referenceLength = "1.0"
    var unitLabel = "m"
    var smoothingWindow = "7"
    var polyorder = "2"
    var trackingProfile: TrackingProfileOption = .auto
    var trackingRobustRecovery = true
    var trackingBidirectionalRefinement = true
    var debugTracking = false
    var includeOverlay = true
    var includePlots = true
    var reportTemplate = "research"
    var advancedMode = false {
        didSet {
            guard oldValue != advancedMode else { return }
            statusMessage = advancedMode
                ? "Advanced calibration controls enabled."
                : "Advanced calibration controls hidden. The current scientific setup is still preserved."
        }
    }
    var calibrationMode = "single_line"
    var calibrationOriginXInput = "0"
    var calibrationOriginYInput = "0"
    var calibrationAxisAngleInput = "0"
    var calibrationInvertX = false
    var calibrationInvertY = false
    var calibrationHomographyInput = ""
    var calibrationPresetName = ""
    var calibrationPixelDistanceInput = "20"

    var targetBox = BoundingBoxDraft()
    var scaleLine = ScaleLineDraft()
    var referenceBox = BoundingBoxDraft()
    var annotationMode: AnnotationMode = .idle
    var editingCorrectionID: String?
    var editingAdditionalObjectID: String?
    var additionalObjectDraft = AdditionalObjectDraft()
    var additionalObjects: [AdditionalObjectDraft] = []
    var corrections: [CorrectionRecord] = []

    var manualEventName = "release"
    var manualEventValue = ""
    var manualEventUnit = ""
    var manualEventNote = ""
    var manualEvents: [EventMarkerRecord] = []
    var derivedEvents: [EventMarkerRecord] = []
    var reviewQueue: [ReviewIssue] = []
    var dismissedReviewFrames = Set<Int>()
    var selectedWindowStart: Int?
    var selectedWindowEnd: Int?
    var selectedTablePreset: ResultsTablePreset = .core

    var metricTiles: [MetricTile] = [
        MetricTile(title: "Avg Confidence", value: "--"),
        MetricTile(title: "Peak Speed", value: "--"),
        MetricTile(title: "Peak Accel", value: "--"),
        MetricTile(title: "Path Length", value: "--"),
    ]
    var analysisModules: [AnalysisModuleSummary] = []
    var analysisRows: [AnalysisRow] = []
    var qualityNotes: [String] = []
    var qcBadge = "pending"
    var reportMarkdown = ""
    var exportDirectory: URL?
    var nativeBundleDirectory: URL?
    var reproduceCommand = "python3 -m tracker_ai.cli analyze ..."
    var summarySnapshot: SummarySnapshot?
    var qualitySnapshot: QualitySnapshot?
    var analyzerSnapshots: [AnalyzerSnapshot] = []
    var sessionTrackQuality: TrackQualitySnapshot?
    var batchAggregate: NativeBatchAggregateSnapshot?
    var trackBundles: [AnalysisTrackBundle] = []
    var activeTrackID = "primary"
    var pairwiseMetrics: [PairwiseMetricSnapshot] = []
    var selectedPairwiseMetricID: String?

    var calibrationValidationMessage: String? {
        guard CalibrationProfile.normalizedMode(calibrationMode) == "homography" else { return nil }
        let trimmed = calibrationHomographyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter 9 numeric homography values separated by spaces or commas." }
        let components = trimmed
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
        guard components.count == 9 else {
            return "Homography mode requires exactly 9 numeric values."
        }
        if components.contains(where: { Double($0) == nil }) {
            return "Homography values must all be numeric."
        }
        return nil
    }

    private let engine = PythonEngineBridge()
    private let nativeExporter = NativeResearchBundleExporter()
    private let nativeScientificProcessor = NativeScientificProcessor()
    private let nativeTrackingPipeline = NativeTrackingPipeline()
    private let nativeTrackingRunner = NativeSingleObjectTrackingRunner()
    private let nativeScientificReporter = NativeResearchReporter()
    private let analysisCoordinator = NativeAnalysisCoordinator()
    private let batchCoordinator = NativeBatchCoordinator()
    private var currentVideoSource: NativeVideoSource?
    private var pendingVideoLoadID = UUID()
    private var internalTrackingConfig = TrackingConfigSnapshot.pythonDefaults
    @ObservationIgnored private var analysisRunTask: Task<AnalysisLoadResult, Error>?

    init() {
        bootstrapWorkspace()
    }

    var selectedPreset: ResearchPreset {
        presets.first(where: { $0.id == selectedPresetID }) ?? presets[0]
    }

    var currentTrialHeadline: String {
        if let url = currentVideoURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "No active trial"
    }

    var currentTrialContext: String {
        if currentVideoURL == nil {
            return "Load a clip or session to start the commercialization-ready native workflow."
        }
        let classification = summarySnapshot?.classification?.title ?? "pending"
        let referenceState = isReferenceReady ? "enabled" : "optional"
        return "Preset: \(selectedPreset.title)\nFrame range: \(startFrame) → \(endFrame)\nActive track: \(activeTrackLabel)\nClassification: \(classification)\nReference marker: \(referenceState)\nManual events: \(manualEvents.count) | Derived events: \(derivedEvents.count) | Review items: \(reviewQueue.count) | Secondary objects: \(additionalObjects.count)"
    }

    var isTargetReady: Bool { targetBox.isComplete }
    var isScaleReady: Bool { scaleLine.isComplete }
    var isReferenceReady: Bool { referenceBox.isComplete }
    var referenceMarkerStatus: String {
        if isReferenceReady {
            return "Ready"
        }
        if annotationMode == .reference {
            return "Drawing"
        }
        return "Optional"
    }
    var canRunAnalysis: Bool { currentVideoURL != nil && isTargetReady && isScaleReady && calibrationValidationMessage == nil }
    var canCancelAnalysis: Bool { analysisRunTask != nil && engineState == .running }
    var maxFrame: Double { Double(max(endFrame, startFrame + 1)) }
    var allEvents: [EventMarkerRecord] { nativeScientificReporter.mergeEventMarkers(manualEvents, withDerived: derivedEvents) }
    var activeTrackBundle: AnalysisTrackBundle? {
        trackBundles.first(where: { $0.trackID == activeTrackID }) ?? trackBundles.first
    }
    var activeTrackLabel: String {
        guard let activeTrackBundle else { return "Primary Object" }
        return "\(activeTrackBundle.trackName) [\(activeTrackBundle.trackKind)]"
    }
    var selectedPairwiseMetric: PairwiseMetricSnapshot? {
        if let selectedPairwiseMetricID {
            return pairwiseMetrics.first(where: { $0.id == selectedPairwiseMetricID }) ?? pairwiseMetrics.first
        }
        return pairwiseMetrics.first
    }
    var timelineMarkers: [String] {
        var markers = ["start \(startFrame)", "end \(endFrame)"]
        if let selectedWindowStart, let selectedWindowEnd {
            markers.append("window \(selectedWindowStart)-\(selectedWindowEnd)")
        }
        markers.append(contentsOf: reviewQueue.prefix(4).map { issue in
            if let endFrame = issue.endFrame, endFrame != issue.frameIndex {
                return "\(issue.severity) \(issue.frameIndex)-\(endFrame)"
            }
            return "\(issue.severity) \(issue.frameIndex)"
        })
        markers.append(contentsOf: allEvents.prefix(6).map { "event \($0.name)@\($0.frameIndex)" })
        return markers
    }
    var trackingControlsSummary: String {
        "User-facing in Swift: profile, robust recovery, bidirectional refinement, and debug export."
    }
    var internalTrackingControlsSummary: String {
        "Session-persistent but internal-only for now: search margins, thresholds, interpolation, scale factors, template update tuning, and marker confidence bias."
    }
    var currentFrameTimestampText: String {
        String(format: "%.3f s", currentFrameTimestamp)
    }
    var currentFrameTrackName: String {
        trackDisplayName(for: activeTrackID)
    }
    var currentFrameStateText: String {
        if let observation = currentObservation {
            let state = observation.state.trimmingCharacters(in: .whitespacesAndNewlines)
            return state.isEmpty ? "--" : state.capitalized
        }
        if let row = currentAnalysisRow {
            let state = row.state.trimmingCharacters(in: .whitespacesAndNewlines)
            if !state.isEmpty {
                return state.capitalized
            }
            if row.lost {
                return "Lost"
            }
        }
        return "--"
    }
    var currentFrameConfidenceText: String {
        if let observation = currentObservation {
            return formatted(observation.confidence)
        }
        return formatted(currentAnalysisRow?.trackerConfidence)
    }
    var currentFrameScientificConfidenceText: String {
        formatted(currentAnalysisRow?.scientificConfidence)
    }
    var currentFrameBBoxText: String {
        if let bbox = currentObservation?.bbox {
            return "\(Int(bbox.width.rounded()))x\(Int(bbox.height.rounded())) px"
        }
        if
            let width = targetBox.cgRect?.width,
            let height = targetBox.cgRect?.height
        {
            return "\(Int(width.rounded()))x\(Int(height.rounded())) px"
        }
        return "--"
    }
    var currentFrameSpeedText: String {
        if let speed = currentAnalysisRow?.speed {
            return "\(formatted(speed)) \(unitLabel)/s"
        }
        return "--"
    }
    var currentFrameAccelerationText: String {
        if let acceleration = currentAnalysisRow?.accelerationMagnitude {
            return "\(formatted(acceleration)) \(unitLabel)/s²"
        }
        return "--"
    }
    var currentFrameReferenceText: String {
        isReferenceReady ? "Enabled" : "Off"
    }
    var canNavigateToNextReviewIssue: Bool {
        nextProblemFrame(after: currentFrame) != nil
    }
    var canNavigateToNextCorrection: Bool {
        nextCorrectionFrame(after: currentFrame) != nil
    }
    var windowSummary: WindowStatsSnapshot? {
        guard !analysisRows.isEmpty else { return nil }
        let start = max(selectedWindowStart ?? startFrame, analysisRows.first?.frameIndex ?? startFrame)
        let end = min(selectedWindowEnd ?? endFrame, analysisRows.last?.frameIndex ?? endFrame)
        guard end > start else { return nil }
        let rows = analysisRows.filter { $0.frameIndex >= start && $0.frameIndex <= end }
        guard let first = rows.first, let last = rows.last, rows.count > 1 else { return nil }
        let dx = last.xUnits - first.xUnits
        let dy = last.yUnits - first.yUnits
        return WindowStatsSnapshot(
            startFrame: start,
            endFrame: end,
            durationSeconds: max(last.timeSeconds - first.timeSeconds, 0),
            displacement: sqrt((dx * dx) + (dy * dy)),
            meanSpeed: rows.map(\.speed).reduce(0, +) / Double(rows.count),
            maxSpeed: rows.map(\.speed).max() ?? 0,
            maxAcceleration: rows.map(\.accelerationMagnitude).max() ?? 0
        )
    }

    private var currentFrameTimestamp: Double {
        timestampForFrame(currentFrame)
    }

    func bootstrapWorkspace() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sampleVideo = root.appendingPathComponent("sample_data/projectile_sample.mp4")
        if FileManager.default.fileExists(atPath: sampleVideo.path) {
            let clip = WorkspaceClip(label: "projectile_sample", videoPath: sampleVideo.path)
            workspaceClips = [clip]
            loadVideo(sampleVideo)
        }
        applyPreset(selectedPreset)
        loadSampleInsights()
    }

    func applyPreset(_ preset: ResearchPreset) {
        selectedPresetID = preset.id
        trackingProfile = preset.trackingProfile
        smoothingWindow = String(preset.smoothingWindow)
        polyorder = String(preset.polyorder)
        reportTemplate = preset.reportTemplate
        selectionMessage = preset.reviewFocus
        statusMessage = "Applied preset: \(preset.title)"
        reproduceCommand = "python3 -m tracker_ai.cli analyze --tracking-profile \(preset.trackingProfile.rawValue) --window \(preset.smoothingWindow) --polyorder \(preset.polyorder) --report-template \(preset.reportTemplate) ..."
    }

    func openVideo() {
        guard let url = FilePanels.openVideo() else { return }
        loadVideo(url)
        addOrActivateWorkspaceClip(videoURL: url, sessionPath: "")
        selectedTab = .setup
        statusMessage = "Loaded \(url.lastPathComponent)"
        selectionMessage = "Define the range, calibration line, and target box before running analysis."
    }

    func loadSession() {
        guard let url = FilePanels.openJSON(title: "Load Tracker Session") else { return }
        do {
            let snapshot = try engine.loadSession(from: url)
            apply(session: snapshot, sessionURL: url, loadBundle: true)
            addOrActivateWorkspaceClip(videoURL: URL(fileURLWithPath: snapshot.videoPath), sessionPath: url.path)
            selectedTab = .overview
            statusMessage = "Loaded session \(url.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadWorkspace() {
        guard let url = FilePanels.openJSON(title: "Load Tracker Workspace") else { return }
        do {
            let snapshot = try engine.loadWorkspace(from: url)
            workspaceClips = snapshot.items
            if let active = workspaceClips.first(where: { $0.videoPath == snapshot.activeVideoPath }) ?? workspaceClips.first {
                activateWorkspaceClip(active)
            }
            statusMessage = "Loaded workspace \(snapshot.title)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveWorkspace() {
        guard let url = FilePanels.saveJSON(title: "Save Workspace", suggestedName: "tracker-workspace.json") else { return }
        do {
            let snapshot = WorkspaceSnapshot(
                title: experimentLabel.isEmpty ? "Tracker AI Workspace" : experimentLabel,
                activeVideoPath: currentVideoURL?.path ?? "",
                items: workspaceClips
            )
            try engine.saveWorkspace(snapshot, to: url)
            statusMessage = "Saved workspace to \(url.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveSession() {
        guard let videoURL = currentVideoURL else {
            statusMessage = "Load a video before saving a session."
            return
        }
        guard isTargetReady && isScaleReady else {
            statusMessage = "Define the target box and scale line before saving a session."
            return
        }
        guard let url = FilePanels.saveJSON(title: "Save Tracker Session", suggestedName: "tracker-session.json") else { return }
        do {
            let snapshot = try buildSessionSnapshot(videoURL: videoURL)
            try engine.saveSession(snapshot, to: url)
            addOrActivateWorkspaceClip(videoURL: videoURL, sessionPath: url.path)
            statusMessage = "Saved native session to \(url.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func exportNativeResearchPackage() {
        guard let videoURL = currentVideoURL else {
            statusMessage = NativeResearchExportError.missingVideoPath.localizedDescription
            return
        }
        guard let directory = FilePanels.chooseDirectory(title: "Choose Native Research Package Directory") else { return }
        do {
            let session = try buildSessionSnapshot(videoURL: videoURL)
            let payload = NativeResearchBundlePayload(
                session: session,
                trackID: activeTrackID,
                trackName: activeTrackLabel,
                analysisRows: analysisRows,
                pairwiseMetrics: pairwiseMetrics,
                eventMarkers: allEvents,
                outputDirectory: directory,
                reportTemplate: reportTemplate,
                trackingProfile: trackingProfile,
                includeOverlay: includeOverlay,
                includePlots: includePlots,
                debugTracking: debugTracking,
                summary: summarySnapshot,
                quality: qualitySnapshot,
                modules: analyzerSnapshots
            )
            let outputs = try nativeExporter.export(payload)
            nativeBundleDirectory = directory
            exportDirectory = directory
            if let manifest = outputs["manifest"] {
                statusMessage = "Exported native research package to \(manifest.deletingLastPathComponent().lastPathComponent)"
            } else {
                statusMessage = "Exported native research package."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func runWorkspaceBatchAnalysis() async {
        guard let outputRoot = FilePanels.chooseDirectory(title: "Choose Native Batch Export Directory") else { return }

        do {
            let sessions = try collectBatchSessions()
            guard !sessions.isEmpty else {
                statusMessage = NativeResearchExportError.emptyWorkspaceBatch.localizedDescription
                return
            }

            engineState = .running
            statusMessage = "Preparing native batch coordinator for \(sessions.count) trial(s)..."

            let result = try await batchCoordinator.run(
                entries: sessions,
                outputRoot: outputRoot,
                makeRunConfiguration: { [self] entry, outputDirectory in
                    try await MainActor.run {
                        try runConfiguration(from: entry.session, outputDirectory: outputDirectory)
                    }
                },
                postProcess: { [self] loadResult, session in
                    await MainActor.run {
                        postProcess(loadResult: loadResult, sessionOverride: session)
                    }
                }
            ) { [self] stage in
                await MainActor.run {
                    analysisProgressFraction = stage.progressFraction
                    statusMessage = stage.statusMessage
                }
            }

            batchAggregate = result.aggregate
            exportDirectory = result.outputRoot
            selectedTab = .results
            selectedResultsTab = .reproduce
            analysisProgressFraction = 1
            engineState = .ready
            statusMessage = "Native workspace batch finished for \(result.aggregate.trialCount) trial(s)."
        } catch {
            analysisProgressFraction = 0
            engineState = .unavailable
            statusMessage = error.localizedDescription
        }
    }

    func activateWorkspaceClip(_ clip: WorkspaceClip) {
        let videoURL = URL(fileURLWithPath: clip.videoPath)
        loadVideo(videoURL)
        if !clip.sessionPath.isEmpty, FileManager.default.fileExists(atPath: clip.sessionPath) {
            do {
                let snapshot = try engine.loadSession(from: URL(fileURLWithPath: clip.sessionPath))
                apply(session: snapshot, sessionURL: URL(fileURLWithPath: clip.sessionPath), loadBundle: true)
            } catch {
                statusMessage = "Loaded clip, but session parsing failed: \(error.localizedDescription)"
            }
        } else {
            statusMessage = "Activated workspace clip \(clip.label)"
        }
    }

    func stepFrame(by delta: Int) {
        currentFrame = max(startFrame, min(endFrame, currentFrame + delta))
        seekPlayer()
    }

    func setCurrentFrame(from sliderValue: Double) {
        currentFrame = Int(sliderValue.rounded())
        seekPlayer()
    }

    func setStartFrameToCurrentFrame() {
        startFrame = currentFrame
        if endFrame < startFrame {
            endFrame = startFrame
        }
        clampSelectedWindowToFrameRange()
        statusMessage = "Start frame set to \(startFrame)."
        selectionMessage = "Start frame saved. Set the end frame or keep the full range before analysis."
    }

    func setEndFrameToCurrentFrame() {
        endFrame = currentFrame
        if endFrame < startFrame {
            startFrame = endFrame
        }
        clampSelectedWindowToFrameRange()
        statusMessage = "End frame set to \(endFrame)."
        selectionMessage = "End frame saved. The analysis will stop at this frame."
    }

    func startTargetDrawing() {
        annotationMode = .target
        editingCorrectionID = nil
        editingAdditionalObjectID = nil
        selectionMessage = "Drag directly on the video to define the primary target box."
    }

    func startScaleDrawing() {
        annotationMode = .scale
        editingCorrectionID = nil
        editingAdditionalObjectID = nil
        selectionMessage = "Drag across the reference object in the video to define the calibration line."
    }

    func startReferenceDrawing() {
        annotationMode = .reference
        editingCorrectionID = nil
        editingAdditionalObjectID = nil
        selectionMessage = "Drag directly on the video to define the reference marker used for motion correction."
    }

    func startCorrectionDrawing(existing: CorrectionRecord? = nil) {
        annotationMode = .correction
        editingCorrectionID = existing?.id
        editingAdditionalObjectID = nil
        if let existing {
            currentFrame = existing.frameIndex
            seekPlayer()
            selectionMessage = "Redraw the correction anchor for \(trackDisplayName(for: existing.trackID)) at frame \(existing.frameIndex) directly on the video."
        } else {
            selectionMessage = "Draw a correction box for \(activeTrackLabel) at the current frame."
        }
    }

    func startAdditionalObjectDrawing(existing: AdditionalObjectDraft? = nil) {
        annotationMode = .companion
        editingCorrectionID = nil
        if let existing {
            additionalObjectDraft = existing
            editingAdditionalObjectID = existing.trackID
            selectionMessage = "Redraw \(existing.name) directly on the video, then save the companion object."
        } else {
            var draft = additionalObjectDraft
            if draft.trackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.trackID = "secondary_\(additionalObjects.count + 1)"
            }
            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.name = "Secondary Object \(additionalObjects.count + 1)"
            }
            additionalObjectDraft = draft
            editingAdditionalObjectID = nil
            selectionMessage = "Drag a companion object directly on the video, then save it for pairwise analysis."
        }
    }

    func cancelAnnotation() {
        annotationMode = .idle
        editingCorrectionID = nil
        editingAdditionalObjectID = nil
        selectionMessage = "Choose a preset, then calibrate and define the target box."
    }

    func clearTargetBox() {
        targetBox = BoundingBoxDraft()
        if annotationMode == .target {
            annotationMode = .idle
        }
        statusMessage = "Cleared target box."
    }

    func clearScaleLine() {
        scaleLine = ScaleLineDraft()
        if annotationMode == .scale {
            annotationMode = .idle
        }
        statusMessage = "Cleared scale line."
    }

    func clearReferenceBox() {
        referenceBox = BoundingBoxDraft()
        if annotationMode == .reference {
            annotationMode = .idle
        }
        statusMessage = "Cleared reference marker."
        selectionMessage = "Reference marker removed. You can redraw it later if the apparatus or camera may drift."
    }

    func removeCorrection(_ correction: CorrectionRecord) {
        corrections.removeAll { $0.id == correction.id }
        if editingCorrectionID == correction.id {
            editingCorrectionID = nil
            annotationMode = .idle
        }
        refreshReviewQueue(trackQuality: sessionTrackQuality)
        statusMessage = "Removed correction at frame \(correction.frameIndex)."
    }

    func applyDrawnTargetBox(_ rect: CGRect) {
        targetBox = Self.boundingBoxDraft(from: rect)
        annotationMode = .idle
        statusMessage = "Updated target box from native canvas."
        selectionMessage = "Target box updated. Calibrate and run analysis when ready."
    }

    func applyDrawnScaleLine(_ start: CGPoint, _ end: CGPoint) {
        scaleLine = Self.scaleLineDraft(from: start, to: end)
        annotationMode = .idle
        statusMessage = "Updated scale line from native canvas."
        selectionMessage = "Scale line updated. Confirm reference length and unit before analysis."
    }

    func applyDrawnReferenceBox(_ rect: CGRect) {
        referenceBox = Self.boundingBoxDraft(from: rect)
        annotationMode = .idle
        statusMessage = "Updated reference marker from native canvas."
        selectionMessage = "Reference marker updated. The analysis can now compensate for apparatus or camera drift when available."
    }

    func applyDrawnCorrection(_ rect: CGRect) {
        let record = CorrectionRecord(
            trackID: editingCorrectionID.flatMap { existingCorrection(id: $0)?.trackID } ?? activeTrackID,
            frameIndex: currentFrame,
            note: "manual_correction",
            bbox: Self.boundingBoxDraft(from: rect)
        )
        if let editingCorrectionID, let index = corrections.firstIndex(where: { $0.id == editingCorrectionID }) {
            corrections[index] = record
            statusMessage = "Updated correction at frame \(record.frameIndex)."
        } else if let index = corrections.firstIndex(where: { $0.frameIndex == currentFrame }) {
            corrections[index] = record
            statusMessage = "Replaced correction at frame \(record.frameIndex)."
        } else {
            corrections.append(record)
            corrections.sort { $0.frameIndex < $1.frameIndex }
            statusMessage = "Added correction at frame \(record.frameIndex)."
        }
        annotationMode = .idle
        editingCorrectionID = nil
        refreshReviewQueue(trackQuality: sessionTrackQuality)
        selectionMessage = "Correction anchor stored for \(trackDisplayName(for: record.trackID)) in the native review workflow."
    }

    func applyDrawnAdditionalObject(_ rect: CGRect) {
        var draft = additionalObjectDraft
        if draft.trackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.trackID = "secondary_\(additionalObjects.count + 1)"
        }
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = "Secondary Object \(additionalObjects.count + 1)"
        }
        if draft.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.kind = "secondary"
        }
        draft.x = Self.formattedCoordinate(rect.minX)
        draft.y = Self.formattedCoordinate(rect.minY)
        draft.width = Self.formattedCoordinate(rect.width)
        draft.height = Self.formattedCoordinate(rect.height)
        additionalObjectDraft = draft
        annotationMode = .idle
        selectionMessage = "Companion object geometry captured. Review the metadata, then save it into the session."
        statusMessage = "Updated \(draft.name) from the native canvas."
    }

    func addManualEvent() {
        let event = EventMarkerRecord(
            name: manualEventName.isEmpty ? "manual_event" : manualEventName,
            frameIndex: currentFrame,
            timeSeconds: currentFrameTimestamp,
            value: Double(manualEventValue) ?? 0,
            unitLabel: manualEventUnit,
            note: manualEventNote,
            origin: "manual"
        )
        manualEvents.append(event)
        manualEvents.sort { ($0.frameIndex, $0.name) < ($1.frameIndex, $1.name) }
        refreshReviewQueue(trackQuality: sessionTrackQuality)
        statusMessage = "Marked \(event.name) at frame \(event.frameIndex)"
    }

    func addAdditionalObject() {
        guard additionalObjectDraft.isComplete else {
            statusMessage = "Fill in track id, name, and bbox fields before adding a companion object."
            return
        }
        if let editingAdditionalObjectID,
           let index = additionalObjects.firstIndex(where: { $0.trackID == editingAdditionalObjectID }) {
            additionalObjects[index] = additionalObjectDraft
            statusMessage = "Updated secondary object \(additionalObjectDraft.name)."
        } else if let index = additionalObjects.firstIndex(where: { $0.id == additionalObjectDraft.id }) {
            additionalObjects[index] = additionalObjectDraft
            statusMessage = "Updated secondary object \(additionalObjectDraft.name)."
        } else {
            additionalObjects.append(additionalObjectDraft)
            statusMessage = "Added secondary object \(additionalObjectDraft.name)."
        }
        additionalObjects.sort { $0.trackID < $1.trackID }
        editingAdditionalObjectID = nil
        annotationMode = .idle
        additionalObjectDraft = AdditionalObjectDraft()
    }

    func removeAdditionalObject(_ object: AdditionalObjectDraft) {
        additionalObjects.removeAll { $0.id == object.id }
        if editingAdditionalObjectID == object.trackID {
            editingAdditionalObjectID = nil
            if annotationMode == .companion {
                annotationMode = .idle
            }
        }
        statusMessage = "Removed secondary object \(object.name)."
    }

    func activateAnalysisTrack(_ trackID: String) {
        guard let bundle = trackBundles.first(where: { $0.trackID == trackID }) else { return }
        activeTrackID = bundle.trackID
        hydrateResults(from: bundle)
        refreshReviewQueue(trackQuality: sessionTrackQuality)
        statusMessage = "Loaded results for \(bundle.trackName)."
    }

    func selectPairwiseMetric(_ metricID: String) {
        guard pairwiseMetrics.contains(where: { $0.id == metricID }) else { return }
        selectedPairwiseMetricID = metricID
    }

    func trackDisplayName(for trackID: String) -> String {
        if let bundle = trackBundles.first(where: { $0.trackID == trackID }) {
            return bundle.trackName
        }
        if trackID == "primary" {
            return "Primary Object"
        }
        if trackID == "reference" {
            return "Reference Marker"
        }
        if let object = additionalObjects.first(where: { $0.trackID == trackID }) {
            return object.name
        }
        return trackID.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func existingCorrection(id: String) -> CorrectionRecord? {
        corrections.first(where: { $0.id == id })
    }

    func jumpToReviewIssue(_ issue: ReviewIssue) {
        currentFrame = issue.frameIndex
        seekPlayer()
        selectedTab = .review
        statusMessage = "Jumped to frame \(issue.frameIndex) for \(issue.title.lowercased())."
    }

    func jumpToNextProblemFrame() {
        guard let frameIndex = nextProblemFrame(after: currentFrame) else {
            statusMessage = "No later review frame was found for \(activeTrackLabel)."
            return
        }
        currentFrame = frameIndex
        seekPlayer()
        selectedTab = .review
        statusMessage = "Jumped to review frame \(frameIndex) for \(activeTrackLabel)."
    }

    func jumpToNextCorrectionFrame() {
        guard let frameIndex = nextCorrectionFrame(after: currentFrame) else {
            statusMessage = "No later correction anchor was found for \(activeTrackLabel)."
            return
        }
        currentFrame = frameIndex
        seekPlayer()
        selectedTab = .review
        statusMessage = "Jumped to correction frame \(frameIndex) for \(activeTrackLabel)."
    }

    func dismissReviewIssue(_ issue: ReviewIssue) {
        guard issue.dismissible else { return }
        dismissedReviewFrames.insert(issue.frameIndex)
        refreshReviewQueue(trackQuality: sessionTrackQuality)
        statusMessage = "Dismissed review item at frame \(issue.frameIndex) for this session."
    }

    func dismissCurrentFrameFromReview() {
        dismissedReviewFrames.insert(currentFrame)
        refreshReviewQueue(trackQuality: sessionTrackQuality)
        statusMessage = "Dismissed frame \(currentFrame) from the review queue for this session."
    }

    func restoreDismissedReviews() {
        dismissedReviewFrames.removeAll()
        refreshReviewQueue(trackQuality: sessionTrackQuality)
        statusMessage = "Restored dismissed review items."
    }

    func setWindowStartToCurrentFrame() {
        selectedWindowStart = currentFrame
        if let selectedWindowEnd, selectedWindowEnd < currentFrame {
            self.selectedWindowEnd = currentFrame
        }
        statusMessage = "Selected window start set to frame \(currentFrame)."
    }

    func setWindowEndToCurrentFrame() {
        selectedWindowEnd = currentFrame
        if let selectedWindowStart, selectedWindowStart > currentFrame {
            self.selectedWindowStart = currentFrame
        }
        statusMessage = "Selected window end set to frame \(currentFrame)."
    }

    func resetWindowSelection() {
        selectedWindowStart = startFrame
        selectedWindowEnd = endFrame
        statusMessage = "Reset the analysis window to the current frame range."
    }

    func setTablePreset(_ preset: ResultsTablePreset) {
        selectedTablePreset = preset
    }

    func tableColumns(for preset: ResultsTablePreset) -> [String] {
        switch preset {
        case .core:
            return ["frame", "t", "x", "y", "|v|", "angle", "conf", "state", "flags"]
        case .velocity:
            return ["frame", "t", "vx", "vy", "|v|", "angle", "state"]
        case .acceleration:
            return ["frame", "t", "ax", "ay", "|a|", "pos unc", "vel unc", "acc unc"]
        case .confidence:
            return ["frame", "t", "tracker", "scientific", "state", "reason", "flags"]
        case .all:
            return ["frame", "t", "raw x", "raw y", "x", "y", "vx", "vy", "|v|", "ax", "ay", "|a|", "angle", "tracker", "scientific", "pos unc", "vel unc", "acc unc", "state", "reason", "flags"]
        }
    }

    func tableValue(for row: AnalysisRow, column: String) -> String {
        switch column {
        case "frame":
            return String(row.frameIndex)
        case "t":
            return formatted(row.timeSeconds)
        case "raw x":
            return formatted(row.rawXUnits)
        case "raw y":
            return formatted(row.rawYUnits)
        case "x":
            return formatted(row.xUnits)
        case "y":
            return formatted(row.yUnits)
        case "vx":
            return formatted(row.xVelocity)
        case "vy":
            return formatted(row.yVelocity)
        case "|v|":
            return formatted(row.speed)
        case "ax":
            return formatted(row.xAcceleration)
        case "ay":
            return formatted(row.yAcceleration)
        case "|a|":
            return formatted(row.accelerationMagnitude)
        case "angle":
            return formatted(row.angleDegrees)
        case "tracker":
            return formatted(row.trackerConfidence)
        case "scientific":
            return formatted(row.scientificConfidence)
        case "pos unc":
            return formatted(row.positionUncertainty)
        case "vel unc":
            return formatted(row.velocityUncertainty)
        case "acc unc":
            return formatted(row.accelerationUncertainty)
        case "state":
            return row.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--" : row.state
        case "reason":
            return row.failureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--" : row.failureReason
        case "flags":
            if row.corrected { return "corrected" }
            if row.lost { return "lost" }
            return "--"
        default:
            return "--"
        }
    }

    private func refreshReviewQueue(trackQuality: TrackQualitySnapshot?) {
        var issues: [ReviewIssue] = []
        if let trackQuality {
            trackQuality.suspectSpans?.forEach { span in
                guard !dismissedReviewFrames.contains(span.startFrame) else { return }
                issues.append(
                    ReviewIssue(
                        title: "Suspect Span",
                        detail: span.reason,
                        frameIndex: span.startFrame,
                        endFrame: span.endFrame,
                        severity: "warning"
                    )
                )
            }
            trackQuality.lostSpans?.forEach { span in
                guard !dismissedReviewFrames.contains(span.startFrame) else { return }
                issues.append(
                    ReviewIssue(
                        title: "Lost Span",
                        detail: span.reason,
                        frameIndex: span.startFrame,
                        endFrame: span.endFrame,
                        severity: "critical"
                    )
                )
            }
            trackQuality.correctedSpans?.forEach { span in
                guard !dismissedReviewFrames.contains(span.startFrame) else { return }
                issues.append(
                    ReviewIssue(
                        title: "Corrected Span",
                        detail: span.reason,
                        frameIndex: span.startFrame,
                        endFrame: span.endFrame,
                        severity: "resolved",
                        dismissible: false
                    )
                )
            }
        }

        corrections.forEach { correction in
            issues.append(
                ReviewIssue(
                    title: "Correction Anchor",
                    detail: "\(trackDisplayName(for: correction.trackID)) • \(correction.note)",
                    frameIndex: correction.frameIndex,
                    endFrame: correction.frameIndex,
                    severity: "resolved",
                    dismissible: false
                )
            )
        }
        allEvents.forEach { event in
            issues.append(
                ReviewIssue(
                    title: "Event \(event.name)",
                    detail: event.note.isEmpty ? event.origin : event.note,
                    frameIndex: event.frameIndex,
                    endFrame: event.frameIndex,
                    severity: event.origin == "manual" ? "resolved" : "warning",
                    dismissible: false
                )
            )
        }

        reviewQueue = issues.sorted { lhs, rhs in
            if lhs.frameIndex == rhs.frameIndex {
                return lhs.title < rhs.title
            }
            return lhs.frameIndex < rhs.frameIndex
        }
    }

    func removeManualEvent(_ event: EventMarkerRecord) {
        manualEvents.removeAll { $0.id == event.id }
        refreshReviewQueue(trackQuality: sessionTrackQuality)
        statusMessage = "Removed event \(event.name)"
    }

    func applyCorrectionReplay(for correction: CorrectionRecord? = nil) async {
        guard let videoURL = currentVideoURL else {
            statusMessage = "Load a video before replaying a correction."
            return
        }
        guard let currentVideoSource else {
            statusMessage = "The native video source is still loading. Try replaying the correction again in a moment."
            return
        }
        guard !trackBundles.isEmpty else {
            statusMessage = "Run or load an analysis before replaying a correction."
            return
        }

        let targetCorrection: CorrectionRecord?
        if let correction {
            targetCorrection = correction
        } else {
            targetCorrection = corrections.first(where: { $0.trackID == activeTrackID && $0.frameIndex == currentFrame })
                ?? corrections.last(where: { $0.trackID == activeTrackID && $0.frameIndex <= currentFrame })
        }
        guard let targetCorrection else {
            statusMessage = "No stored correction anchor was found for \(activeTrackLabel) at or before frame \(currentFrame)."
            return
        }
        guard let bundle = trackBundles.first(where: { $0.trackID == targetCorrection.trackID }) else {
            statusMessage = "The current results do not contain a track for \(trackDisplayName(for: targetCorrection.trackID))."
            return
        }

        let baseSession: SessionSnapshot
        do {
            baseSession = try buildSessionSnapshot(videoURL: videoURL)
        } catch {
            statusMessage = error.localizedDescription
            return
        }
        guard let baseTrack = nativeTrackingPipeline.reconstructTrack(bundle: bundle, session: baseSession) else {
            statusMessage = "Unable to reconstruct the selected track for correction replay."
            return
        }

        let correctedBBox = BBoxSnapshot(
            x: Double(targetCorrection.bbox.x) ?? 0,
            y: Double(targetCorrection.bbox.y) ?? 0,
            width: Double(targetCorrection.bbox.width) ?? 0,
            height: Double(targetCorrection.bbox.height) ?? 0
        )

        engineState = .running
        analysisProgressFraction = 0.7
        statusMessage = "Replaying correction for \(trackDisplayName(for: targetCorrection.trackID)) from frame \(targetCorrection.frameIndex)..."

        do {
            let replayBaseTrack: NativeTrackResult
            if baseSession.referenceBbox != nil {
                let replayStartFrame = baseSession.selectedStartFrame ?? 0
                if targetCorrection.frameIndex > replayStartFrame {
                    replayBaseTrack = try nativeTrackingRunner.runSingleObjectTracking(
                        video: currentVideoSource,
                        initialBBox: correctedBBoxForTrack(trackID: targetCorrection.trackID, session: baseSession),
                        startFrame: replayStartFrame,
                        endFrame: targetCorrection.frameIndex - 1,
                        corrected: false,
                        config: baseSession.resolvedTrackingConfig,
                        trackID: bundle.trackID,
                        trackName: bundle.trackName,
                        trackKind: bundle.trackKind
                    )
                } else {
                    replayBaseTrack = NativeTrackResult(
                        observations: [],
                        trackerName: "robust_hybrid_tracker",
                        averageConfidence: 0,
                        startFrame: replayStartFrame,
                        endFrame: replayStartFrame,
                        initialBBox: correctedBBoxForTrack(trackID: targetCorrection.trackID, session: baseSession),
                        quality: NativeTrackRuntimeDerivation.emptyQuality(),
                        trackingConfig: baseSession.resolvedTrackingConfig,
                        trackID: bundle.trackID,
                        trackName: bundle.trackName,
                        trackKind: bundle.trackKind
                    )
                }
            } else {
                replayBaseTrack = NativeTrackResult(
                    observations: baseTrack.observations,
                    trackerName: "robust_hybrid_tracker",
                    averageConfidence: baseTrack.averageConfidence,
                    startFrame: baseTrack.observations.first?.frameIndex ?? targetCorrection.frameIndex,
                    endFrame: baseTrack.observations.last?.frameIndex ?? targetCorrection.frameIndex,
                    initialBBox: correctedBBoxForTrack(trackID: targetCorrection.trackID, session: baseSession),
                    quality: baseTrack.quality,
                    trackingConfig: baseSession.resolvedTrackingConfig,
                    trackID: baseTrack.trackID,
                    trackName: baseTrack.trackName,
                    trackKind: baseTrack.trackKind
                )
            }

            let mergedDisplayTrack = try nativeTrackingRunner.replayCorrection(
                video: currentVideoSource,
                baseTrack: replayBaseTrack,
                correctedBBox: correctedBBox,
                startFrame: targetCorrection.frameIndex,
                endFrame: baseSession.selectedEndFrame,
                config: baseSession.resolvedTrackingConfig,
                trackID: baseTrack.trackID,
                trackName: baseTrack.trackName,
                trackKind: baseTrack.trackKind
            )

            let resolvedTrack: NativeTrackResult
            if let referenceBBox = baseSession.referenceBbox {
                let referenceTrack = try nativeTrackingRunner.runSingleObjectTracking(
                    video: currentVideoSource,
                    initialBBox: referenceBBox,
                    startFrame: baseSession.selectedStartFrame ?? 0,
                    endFrame: baseSession.selectedEndFrame,
                    corrected: false,
                    config: nativeTrackingRunner.referenceTrackingConfig(from: baseSession.resolvedTrackingConfig),
                    trackID: "reference",
                    trackName: "Reference Marker",
                    trackKind: "reference"
                )
                resolvedTrack = nativeTrackingRunner.applyReferenceMotionCorrection(
                    primaryTrack: mergedDisplayTrack,
                    referenceTrack: referenceTrack
                )
            } else {
                resolvedTrack = mergedDisplayTrack
            }

            let rebuiltRows = nativeScientificProcessor.process(
                observations: resolvedTrack.observations,
                calibration: try baseSession.calibration.makeCalibrationProfile(),
                config: baseSession.analysisConfig
            )

            let rebuiltBundles = trackBundles.map { existingBundle in
                guard existingBundle.trackID == targetCorrection.trackID else { return existingBundle }
                return rebuiltTrackBundle(
                    trackID: existingBundle.trackID,
                    trackName: existingBundle.trackName,
                    trackKind: existingBundle.trackKind,
                    processedRows: rebuiltRows,
                    reportMarkdown: existingBundle.reportMarkdown,
                    exportDirectory: existingBundle.exportDirectory,
                    session: baseSession,
                    pairwiseMetrics: pairwiseMetrics,
                    reproduceCommand: nativeReproduceCommand(for: baseSession, outputDirectory: exportDirectory ?? existingBundle.exportDirectory),
                    manualEventCount: existingBundle.trackID == "primary"
                        ? (baseSession.eventMarkers ?? []).filter { ($0.origin ?? "manual") == "manual" }.count
                        : 0
                )
            }

            let updatedLoadResult = AnalysisLoadResult(
                summary: rebuiltBundles.first(where: { $0.trackID == "primary" })?.summary,
                quality: rebuiltBundles.first(where: { $0.trackID == "primary" })?.quality,
                modules: rebuiltBundles.first(where: { $0.trackID == "primary" })?.modules ?? [],
                analysisRows: rebuiltBundles.first(where: { $0.trackID == "primary" })?.analysisRows ?? rebuiltRows,
                session: baseSession,
                reportMarkdown: rebuiltBundles.first(where: { $0.trackID == "primary" })?.reportMarkdown ?? "",
                exportDirectory: exportDirectory ?? nativeBundleDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                trackBundles: rebuiltBundles,
                pairwiseMetrics: []
            )
            let previousActiveTrackID = activeTrackID
            apply(loadResult: updatedLoadResult)
            activeTrackID = trackBundles.contains(where: { $0.trackID == previousActiveTrackID }) ? previousActiveTrackID : targetCorrection.trackID
            if let activeTrackBundle {
                hydrateResults(from: activeTrackBundle)
            }
            currentFrame = targetCorrection.frameIndex
            seekPlayer()
            analysisProgressFraction = 1
            engineState = .ready
            statusMessage = "Correction replay updated \(trackDisplayName(for: targetCorrection.trackID)) from frame \(targetCorrection.frameIndex)."
            selectedTab = .review
        } catch {
            analysisProgressFraction = 0
            engineState = .unavailable
            statusMessage = error.localizedDescription
        }
    }

    func runAnalysis() async {
        guard let videoURL = currentVideoURL else {
            statusMessage = "Load a video before running analysis."
            return
        }
        guard canRunAnalysis else {
            statusMessage = "The target box and scale line need complete numeric values before analysis."
            return
        }
        guard let directory = FilePanels.chooseDirectory(title: "Choose Analysis Export Directory") else { return }
        analysisRunTask?.cancel()
        analysisProgressFraction = 0
        engineState = .running
        statusMessage = "Preparing native analysis bundle..."

        let preservedSession: SessionSnapshot
        do {
            preservedSession = try buildSessionSnapshot(videoURL: videoURL)
        } catch {
            engineState = .unavailable
            statusMessage = error.localizedDescription
            return
        }

        let config = NativeRunConfiguration(
            videoURL: videoURL,
            outputDirectory: directory,
            targetBox: targetBox,
            scaleLine: scaleLine,
            referenceBox: referenceBox.isComplete ? referenceBox : nil,
            referenceLength: Double(referenceLength) ?? 1.0,
            unitLabel: unitLabel.isEmpty ? "m" : unitLabel,
            startFrame: startFrame,
            endFrame: endFrame >= startFrame ? endFrame : nil,
            smoothingWindow: Int(smoothingWindow) ?? 7,
            polyorder: Int(polyorder) ?? 2,
            trackingConfig: resolvedTrackingConfigSnapshot(),
            trackingProfile: trackingProfile,
            debugTracking: debugTracking,
            includeOverlay: includeOverlay,
            includePlots: includePlots,
            reportTemplate: reportTemplate,
            experimentLabel: experimentLabel,
            trialID: trialID,
            operatorName: operatorName,
            notes: notes,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            additionalObjects: additionalObjects
        )

        let task = Task<AnalysisLoadResult, Error> {
            try await analysisCoordinator.run(
                config: config,
                preservedSession: preservedSession
            ) { [self] stage in
                await MainActor.run {
                    analysisProgressFraction = stage.progressFraction
                    statusMessage = stage.statusMessage
                }
            }
        }
        analysisRunTask = task

        do {
            let result = try await task.value
            let mergedResult = postProcess(loadResult: result, sessionOverride: preservedSession)
            apply(loadResult: mergedResult)
            nativeBundleDirectory = mergedResult.exportDirectory
            analysisProgressFraction = 1
            statusMessage = "Analysis complete. The native run coordinator is now driving the research bundle."
            selectedTab = .results
            selectedResultsTab = .insights
            engineState = .ready
        } catch is CancellationError {
            analysisProgressFraction = 0
            engineState = .ready
            statusMessage = "Analysis canceled before the native bundle finished exporting."
        } catch {
            analysisProgressFraction = 0
            engineState = .unavailable
            statusMessage = error.localizedDescription
        }
        analysisRunTask = nil
    }

    func cancelAnalysis() {
        guard let analysisRunTask else { return }
        analysisRunTask.cancel()
        statusMessage = "Canceling native analysis..."
    }

    func apply(session: SessionSnapshot, sessionURL: URL, loadBundle: Bool) {
        experimentLabel = session.metadata?.experimentLabel ?? experimentLabel
        trialID = session.metadata?.trialID ?? trialID
        operatorName = session.metadata?.operatorName ?? operatorName
        notes = session.metadata?.notes ?? notes
        tags = (session.metadata?.tags ?? []).joined(separator: ", ")

        if let start = session.selectedStartFrame { startFrame = start }
        if let end = session.selectedEndFrame { endFrame = end }
        currentFrame = session.reviewState?.lastFrameIndex ?? startFrame

        advancedMode = session.advancedMode ?? advancedMode
        referenceLength = String(session.calibration.referenceLength)
        unitLabel = session.calibration.unitLabel
        calibrationMode = CalibrationProfile.normalizedMode(session.calibration.mode ?? "single_line")
        calibrationOriginXInput = formattedCalibrationInput(session.calibration.originXPx ?? 0)
        calibrationOriginYInput = formattedCalibrationInput(session.calibration.originYPx ?? 0)
        calibrationAxisAngleInput = formattedCalibrationInput(session.calibration.axisAngleDeg ?? 0)
        calibrationInvertX = session.calibration.invertX ?? false
        calibrationInvertY = session.calibration.invertY ?? false
        calibrationHomographyInput = formattedHomographyInput(session.calibration.homography)
        calibrationPresetName = session.calibration.presetName ?? ""
        calibrationPixelDistanceInput = formattedCalibrationInput(session.calibration.pixelDistance)
        smoothingWindow = String(session.analysisConfig.smoothingWindow)
        polyorder = String(session.analysisConfig.smoothingPolyorder)
        applyTrackingConfig(session.trackingConfig)
        debugTracking = session.exportPreferences?.includeDebugTracking ?? debugTracking
        includeOverlay = session.exportPreferences?.includeOverlay ?? includeOverlay
        includePlots = session.exportPreferences?.includePlots ?? includePlots
        reportTemplate = session.exportPreferences?.reportTemplate ?? reportTemplate

        targetBox = BoundingBoxDraft(
            x: String(session.initialBbox.x),
            y: String(session.initialBbox.y),
            width: String(session.initialBbox.width),
            height: String(session.initialBbox.height)
        )

        if let points = session.scalePoints, points.count == 4 {
            scaleLine = ScaleLineDraft(
                x1: String(points[0]),
                y1: String(points[1]),
                x2: String(points[2]),
                y2: String(points[3])
            )
        } else {
            scaleLine = inferredScaleLine(from: session.calibration)
        }

        if let reference = session.referenceBbox {
            referenceBox = BoundingBoxDraft(
                x: String(reference.x),
                y: String(reference.y),
                width: String(reference.width),
                height: String(reference.height)
            )
        } else {
            referenceBox = BoundingBoxDraft()
        }

        manualEvents = (session.eventMarkers ?? []).filter { ($0.origin ?? "derived") == "manual" }.map {
            EventMarkerRecord(
                name: $0.name,
                frameIndex: $0.frameIndex,
                timeSeconds: $0.timeS,
                value: $0.value,
                unitLabel: $0.unitLabel,
                axis: $0.axis ?? "",
                note: $0.note ?? "",
                origin: $0.origin ?? "manual"
            )
        }
        derivedEvents = (session.eventMarkers ?? []).filter { ($0.origin ?? "derived") != "manual" }.map {
            EventMarkerRecord(
                name: $0.name,
                frameIndex: $0.frameIndex,
                timeSeconds: $0.timeS,
                value: $0.value,
                unitLabel: $0.unitLabel,
                axis: $0.axis ?? "",
                note: $0.note ?? "",
                origin: $0.origin ?? "derived"
            )
        }

        selectedWindowStart = session.reviewState?.selectedWindowStart ?? startFrame
        selectedWindowEnd = session.reviewState?.selectedWindowEnd ?? endFrame
        dismissedReviewFrames = Set(session.reviewState?.dismissedReviewFrames ?? [])
        sessionTrackQuality = session.trackQuality

        corrections = (session.corrections ?? []).map {
            CorrectionRecord(
                trackID: $0.trackID ?? "primary",
                frameIndex: $0.frameIndex,
                note: $0.note ?? "manual_correction",
                bbox: BoundingBoxDraft(
                    x: String($0.bbox.x),
                    y: String($0.bbox.y),
                    width: String($0.bbox.width),
                    height: String($0.bbox.height)
                )
            )
        }
        additionalObjects = (session.additionalObjects ?? []).map {
            AdditionalObjectDraft(
                trackID: $0.trackID,
                name: $0.name,
                kind: $0.kind ?? "secondary",
                x: String($0.bbox.x),
                y: String($0.bbox.y),
                width: String($0.bbox.width),
                height: String($0.bbox.height)
            )
        }
        refreshReviewQueue(trackQuality: sessionTrackQuality)

        let bundleDirectory = sessionURL.deletingLastPathComponent()
        let loadedBundle = loadBundle ? (try? engine.loadBundle(from: bundleDirectory)) : nil
        if let loadedBundle {
            apply(loadResult: loadedBundle)
        } else if loadBundle {
            trackBundles = [
                AnalysisTrackBundle(
                    trackID: "primary",
                    trackName: "Primary Object",
                    trackKind: "primary",
                    summary: nil,
                    quality: nil,
                    modules: [],
                    analysisRows: [],
                    reportMarkdown: "",
                    exportDirectory: bundleDirectory
                )
            ]
            activeTrackID = "primary"
            pairwiseMetrics = []
            selectedPairwiseMetricID = nil
            analysisRows = []
            analysisModules = []
            qualityNotes = []
            metricTiles = [
                MetricTile(title: "Avg Confidence", value: "--"),
                MetricTile(title: "Peak Speed", value: "--"),
                MetricTile(title: "Peak Accel", value: "--"),
                MetricTile(title: "Path Length", value: "--"),
            ]
        }
        if FileManager.default.fileExists(atPath: session.videoPath) {
            loadVideo(URL(fileURLWithPath: session.videoPath), resetSelection: false)
        }
        let overlayFlag = includeOverlay ? "" : " --skip-overlay"
        let plotFlag = includePlots ? "" : " --skip-plots"
        let debugFlag = debugTracking ? " --debug-tracking" : ""
        reproduceCommand = "python3 -m tracker_ai.cli analyze --video \(session.videoPath) --output-dir \(bundleDirectory.path)\(overlayFlag)\(plotFlag)\(debugFlag) --report-template \(reportTemplate)"
    }

    private func apply(loadResult: AnalysisLoadResult) {
        let normalizedResult = postProcess(loadResult: loadResult)
        exportDirectory = normalizedResult.exportDirectory
        trackBundles = normalizedResult.trackBundles.isEmpty ? [
            AnalysisTrackBundle(
                trackID: "primary",
                trackName: "Primary Object",
                trackKind: "primary",
                summary: normalizedResult.summary,
                quality: normalizedResult.quality,
                modules: normalizedResult.modules,
                analysisRows: normalizedResult.analysisRows,
                reportMarkdown: normalizedResult.reportMarkdown,
                exportDirectory: normalizedResult.exportDirectory
            )
        ] : normalizedResult.trackBundles
        pairwiseMetrics = normalizedResult.pairwiseMetrics
        if let previousTrackID = trackBundles.first(where: { $0.trackID == activeTrackID })?.trackID {
            activeTrackID = previousTrackID
        } else {
            activeTrackID = trackBundles.first(where: { $0.trackID == "primary" })?.trackID ?? trackBundles.first?.trackID ?? "primary"
        }
        if let selectedPairwiseMetricID,
           pairwiseMetrics.contains(where: { $0.id == selectedPairwiseMetricID }) {
            self.selectedPairwiseMetricID = selectedPairwiseMetricID
        } else {
            self.selectedPairwiseMetricID = pairwiseMetrics.first?.id
        }
        batchAggregate = nil

        if let session = normalizedResult.session {
            apply(
                session: session,
                sessionURL: normalizedResult.exportDirectory.appendingPathComponent("session.json"),
                loadBundle: false
            )
        } else {
            let overlayFlag = includeOverlay ? "" : " --skip-overlay"
            let plotFlag = includePlots ? "" : " --skip-plots"
            let debugFlag = debugTracking ? " --debug-tracking" : ""
            reproduceCommand = "python3 -m tracker_ai.cli analyze --video \(currentVideoURL?.path ?? "") --output-dir \(normalizedResult.exportDirectory.path)\(overlayFlag)\(plotFlag)\(debugFlag) --report-template \(reportTemplate)"
        }
        if let activeTrackBundle {
            hydrateResults(from: activeTrackBundle)
        }
        if let currentVideoURL {
            let rootSessionPath = normalizedResult.exportDirectory.appendingPathComponent("session.json").path
            let fallbackTrackSessionPath = (trackBundles.first(where: { $0.trackID == "primary" }) ?? trackBundles.first)?
                .exportDirectory
                .appendingPathComponent("session.json")
                .path ?? rootSessionPath
            let resolvedSessionPath = FileManager.default.fileExists(atPath: rootSessionPath) ? rootSessionPath : fallbackTrackSessionPath
            addOrActivateWorkspaceClip(videoURL: currentVideoURL, sessionPath: resolvedSessionPath)
        }
    }

    private func addOrActivateWorkspaceClip(videoURL: URL, sessionPath: String) {
        let clip = WorkspaceClip(label: videoURL.deletingPathExtension().lastPathComponent, videoPath: videoURL.path, sessionPath: sessionPath)
        if let index = workspaceClips.firstIndex(where: { $0.videoPath == clip.videoPath }) {
            workspaceClips[index] = clip
        } else {
            workspaceClips.append(clip)
        }
    }

    private func loadSampleInsights() {
        selectedWindowStart = 8
        selectedWindowEnd = 28
        dismissedReviewFrames.removeAll()
        sessionTrackQuality = nil
        let primaryRows = stride(from: 0, through: 40, by: 1).map { frame in
            let time = Double(frame) * 0.033
            return AnalysisRow(
                frameIndex: frame,
                timeSeconds: time,
                xUnits: time * 1.8,
                yUnits: sin(time * 2.2) * 0.4 + 0.6,
                speed: abs(cos(time * 1.6)) * 2.4,
                accelerationMagnitude: abs(sin(time * 2.9)) * 7.1,
                trackerConfidence: 0.88 + (Double(frame % 6) * 0.01),
                scientificConfidence: 0.84 + (Double(frame % 5) * 0.015)
            )
        }
        let companionRows = stride(from: 0, through: 40, by: 1).map { frame in
            let time = Double(frame) * 0.033
            return AnalysisRow(
                frameIndex: frame,
                timeSeconds: time,
                xUnits: time * 1.8 + 0.22,
                yUnits: sin(time * 2.2 + 0.4) * 0.35 + 0.72,
                speed: abs(cos(time * 1.4 + 0.3)) * 2.0,
                accelerationMagnitude: abs(sin(time * 2.2 + 0.6)) * 5.8,
                trackerConfidence: 0.85 + (Double(frame % 5) * 0.012),
                scientificConfidence: 0.81 + (Double(frame % 4) * 0.018)
            )
        }
        trackBundles = [
            AnalysisTrackBundle(
                trackID: "primary",
                trackName: "Primary Object",
                trackKind: "primary",
                summary: SummarySnapshot(
                    frameCount: primaryRows.count,
                    durationSeconds: primaryRows.last?.timeSeconds,
                    startFrame: primaryRows.first?.frameIndex,
                    endFrame: primaryRows.last?.frameIndex,
                    averageConfidence: 0.921,
                    lowConfidenceFrameCount: nil,
                    suspectSpanCount: nil,
                    xRangeUnits: nil,
                    yRangeUnits: nil,
                    peakSpeed: 2.480,
                    meanSpeed: nil,
                    peakAcceleration: 7.140,
                    meanAcceleration: nil,
                    totalPathLength: 0.942,
                    netDisplacement: nil,
                    scientificConfidenceMean: 0.872,
                    qcBadge: "ready",
                    eventCount: nil,
                    unitLabel: "m",
                    reacquisitionCount: nil,
                    lostFrameCount: nil,
                    correctedFrameCount: nil,
                    reviewRecommended: false,
                    peakPositionUncertainty: nil,
                    peakVelocityUncertainty: nil
                ),
                quality: QualitySnapshot(
                    qcBadge: "ready",
                    trackerConfidenceMean: 0.921,
                    scientificConfidenceMean: 0.872,
                    calibrationConfidence: nil,
                    driftSensitivity: nil,
                    lowConfidenceFrames: nil,
                    lostFrameCount: nil,
                    correctedFrameCount: nil,
                    interpolatedBurdenRatio: nil,
                    peakPositionUncertainty: nil,
                    peakVelocityUncertainty: nil,
                    reviewRecommended: false,
                    notes: [
                    "Use the review journal to mark release, apex, and impact frames before publication exports.",
                    "A commercialization-ready native shell is now in place, and the native run coordinator now owns export-time analysis.",
                    ]
                ),
                modules: [
                    AnalyzerSnapshot(analyzerID: "projectile", title: "Projectile Motion", confidence: 0.91, metrics: [
                        AnalyzerMetricSnapshot(key: "launch_angle_deg", value: 42.4, unitLabel: "deg"),
                        AnalyzerMetricSnapshot(key: "gravity_fit", value: -9.8, unitLabel: "m/s²"),
                    ], notes: nil)
                ],
                analysisRows: primaryRows,
                reportMarkdown: "",
                exportDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ),
            AnalysisTrackBundle(
                trackID: "secondary_1",
                trackName: "Companion Cart",
                trackKind: "secondary",
                summary: SummarySnapshot(
                    frameCount: companionRows.count,
                    durationSeconds: companionRows.last?.timeSeconds,
                    startFrame: companionRows.first?.frameIndex,
                    endFrame: companionRows.last?.frameIndex,
                    averageConfidence: 0.894,
                    lowConfidenceFrameCount: nil,
                    suspectSpanCount: nil,
                    xRangeUnits: nil,
                    yRangeUnits: nil,
                    peakSpeed: 2.016,
                    meanSpeed: nil,
                    peakAcceleration: 5.843,
                    meanAcceleration: nil,
                    totalPathLength: 0.812,
                    netDisplacement: nil,
                    scientificConfidenceMean: 0.851,
                    qcBadge: "review",
                    eventCount: nil,
                    unitLabel: "m",
                    reacquisitionCount: nil,
                    lostFrameCount: nil,
                    correctedFrameCount: nil,
                    reviewRecommended: true,
                    peakPositionUncertainty: nil,
                    peakVelocityUncertainty: nil
                ),
                quality: QualitySnapshot(
                    qcBadge: "review",
                    trackerConfidenceMean: 0.894,
                    scientificConfidenceMean: 0.851,
                    calibrationConfidence: nil,
                    driftSensitivity: nil,
                    lowConfidenceFrames: nil,
                    lostFrameCount: nil,
                    correctedFrameCount: nil,
                    interpolatedBurdenRatio: nil,
                    peakPositionUncertainty: nil,
                    peakVelocityUncertainty: nil,
                    reviewRecommended: true,
                    notes: [
                        "Secondary object trajectory is sample data meant to demonstrate pairwise visualization.",
                    ]
                ),
                modules: [
                    AnalyzerSnapshot(analyzerID: "collision_pair", title: "Collision Pair", confidence: 0.67, metrics: [
                        AnalyzerMetricSnapshot(key: "peak_relative_speed", value: 1.14, unitLabel: "m/s"),
                    ], notes: nil)
                ],
                analysisRows: companionRows,
                reportMarkdown: "",
                exportDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ),
        ]
        activeTrackID = "primary"
        pairwiseMetrics = [
            PairwiseMetricSnapshot(
                primaryTrackID: "primary",
                secondaryTrackID: "secondary_1",
                samples: zip(primaryRows, companionRows).map { pair in
                    let primary = pair.0
                    let companion = pair.1
                    let dx = companion.xUnits - primary.xUnits
                    let dy = companion.yUnits - primary.yUnits
                    let leftVX = primary.xVelocity ?? primary.speed
                    let leftVY = primary.yVelocity ?? 0
                    let rightVX = companion.xVelocity ?? companion.speed
                    let rightVY = companion.yVelocity ?? 0
                    return PairwiseMetricSampleSnapshot(
                        frameIndex: primary.frameIndex,
                        timeSeconds: primary.timeSeconds,
                        distanceUnits: sqrt((dx * dx) + (dy * dy)),
                        relativeSpeedUnitsPerSecond: sqrt(pow(rightVX - leftVX, 2) + pow(rightVY - leftVY, 2)),
                        relativeDXUnits: dx,
                        relativeDYUnits: dy
                    )
                }
            )
        ]
        selectedPairwiseMetricID = pairwiseMetrics.first?.id
        reviewQueue = [
            ReviewIssue(title: "Suspect Span", detail: "Confidence dipped during release.", frameIndex: 9, endFrame: 12, severity: "warning"),
            ReviewIssue(title: "Lost Span", detail: "Object briefly left the search region.", frameIndex: 24, endFrame: 26, severity: "critical"),
            ReviewIssue(title: "Event release", detail: "manual", frameIndex: 4, endFrame: 4, severity: "resolved", dismissible: false),
        ]
        if let activeTrackBundle {
            hydrateResults(from: activeTrackBundle)
        }
    }

    private func seekPlayer() {
        guard let player else { return }
        let time = (try? currentVideoSource?.presentationTime(forFrameIndex: currentFrame)) ?? CMTime(
            seconds: currentFrameTimestamp,
            preferredTimescale: 600
        )
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func loadVideo(_ url: URL, resetSelection: Bool = true) {
        currentVideoURL = url
        currentVideoSource = nil
        sourceVideoMetadata = nil
        player = AVPlayer(url: url)
        let loadID = UUID()
        pendingVideoLoadID = loadID
        Task {
            await loadVideoSource(for: url, resetSelection: resetSelection, loadID: loadID)
        }
    }

    private func loadVideoSource(for url: URL, resetSelection: Bool, loadID: UUID) async {
        do {
            let videoSource = try await NativeVideoSource.open(url: url)
            guard pendingVideoLoadID == loadID, currentVideoURL == url else { return }
            currentVideoSource = videoSource
            sourceVideoMetadata = videoSource.metadata
            if videoSource.metadata.width > 0, videoSource.metadata.height > 0 {
                sourceVideoSize = videoSource.metadata.presentationSize
            }
            playbackFPS = videoSource.metadata.fps
            applyVideoFrameBounds(frameCount: videoSource.metadata.frameCount, resetSelection: resetSelection)
        } catch {
            guard pendingVideoLoadID == loadID, currentVideoURL == url else { return }
            statusMessage = "Loaded video, but native metadata parsing was limited: \(error.localizedDescription)"
        }
    }

    private func applyVideoFrameBounds(frameCount: Int, resetSelection: Bool) {
        let lastFrameIndex = max(frameCount - 1, 0)
        if resetSelection {
            startFrame = 0
            endFrame = lastFrameIndex
            currentFrame = 0
            selectedWindowStart = startFrame
            selectedWindowEnd = endFrame
        } else {
            startFrame = min(max(startFrame, 0), lastFrameIndex)
            endFrame = min(max(endFrame, startFrame), lastFrameIndex)
            currentFrame = min(max(currentFrame, startFrame), endFrame)
            if let selectedWindowStart {
                self.selectedWindowStart = min(max(selectedWindowStart, startFrame), endFrame)
            } else {
                self.selectedWindowStart = startFrame
            }
            if let selectedWindowEnd {
                self.selectedWindowEnd = min(max(selectedWindowEnd, startFrame), endFrame)
            } else {
                self.selectedWindowEnd = endFrame
            }
        }
        seekPlayer()
    }

    private func timestampForFrame(_ frameIndex: Int) -> Double {
        if let currentVideoSource, let timestamp = try? currentVideoSource.frameTimestamp(forFrameIndex: frameIndex) {
            return timestamp
        }
        return Double(frameIndex) / max(playbackFPS, 1)
    }

    private var currentTrackReconstruction: NativeTrackReconstruction? {
        guard let activeTrackBundle else { return nil }
        guard let session = currentScientificSessionSnapshot(for: activeTrackBundle) else { return nil }
        return nativeTrackingPipeline.reconstructTrack(bundle: activeTrackBundle, session: session)
    }

    private var currentObservation: NativeTrackingObservation? {
        currentTrackReconstruction?.observationByFrame[currentFrame]
    }

    private var currentAnalysisRow: AnalysisRow? {
        analysisRows.first(where: { $0.frameIndex == currentFrame })
    }

    private func clampSelectedWindowToFrameRange() {
        if let selectedWindowStart {
            self.selectedWindowStart = min(max(selectedWindowStart, startFrame), endFrame)
        } else {
            self.selectedWindowStart = startFrame
        }
        if let selectedWindowEnd {
            self.selectedWindowEnd = min(max(selectedWindowEnd, startFrame), endFrame)
        } else {
            self.selectedWindowEnd = endFrame
        }
    }

    private func nextProblemFrame(after frameIndex: Int) -> Int? {
        let qualifyingObservation = currentTrackReconstruction?.observations
            .sorted { $0.frameIndex < $1.frameIndex }
            .first(where: { observation in
                guard observation.frameIndex > frameIndex else { return false }
                guard !dismissedReviewFrames.contains(observation.frameIndex) else { return false }
                let state = observation.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return observation.lost || observation.confidence < 0.35 || (!state.isEmpty && state != NativeTrackingState.tracking.rawValue)
            })?.frameIndex
        if let qualifyingObservation {
            return qualifyingObservation
        }
        return reviewQueue
            .filter { $0.frameIndex > frameIndex && $0.severity != "resolved" }
            .map(\.frameIndex)
            .min()
    }

    private func nextCorrectionFrame(after frameIndex: Int) -> Int? {
        corrections
            .filter { $0.trackID == activeTrackID && $0.frameIndex > frameIndex }
            .map(\.frameIndex)
            .min()
    }

    private static func boundingBoxDraft(from rect: CGRect) -> BoundingBoxDraft {
        BoundingBoxDraft(
            x: String(format: "%.1f", rect.origin.x),
            y: String(format: "%.1f", rect.origin.y),
            width: String(format: "%.1f", rect.width),
            height: String(format: "%.1f", rect.height)
        )
    }

    private static func scaleLineDraft(from start: CGPoint, to end: CGPoint) -> ScaleLineDraft {
        ScaleLineDraft(
            x1: String(format: "%.1f", start.x),
            y1: String(format: "%.1f", start.y),
            x2: String(format: "%.1f", end.x),
            y2: String(format: "%.1f", end.y)
        )
    }

    private static func formattedCoordinate(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func hydrateResults(from bundle: AnalysisTrackBundle) {
        reportMarkdown = bundle.reportMarkdown
        analysisRows = bundle.analysisRows
        let nativeSlices = resolveNativeScientificSlices(for: bundle)
        summarySnapshot = nativeSlices.summary ?? bundle.summary
        qualitySnapshot = nativeSlices.quality ?? bundle.quality
        analyzerSnapshots = nativeSlices.modules.isEmpty ? bundle.modules : nativeSlices.modules
        sessionTrackQuality = resolvedTrackQualitySnapshot(rows: analysisRows, trackID: bundle.trackID)
        refreshReviewQueue(trackQuality: sessionTrackQuality)

        if analysisRows.count > 1 {
            let delta = analysisRows[1].timeSeconds - analysisRows[0].timeSeconds
            playbackFPS = delta > 0 ? 1.0 / delta : playbackFPS
        }

        if let summary = summarySnapshot {
            metricTiles = [
                MetricTile(title: "Avg Confidence", value: formatted(summary.averageConfidence)),
                MetricTile(title: "Peak Speed", value: "\(formatted(summary.peakSpeed)) \(summary.unitLabel ?? unitLabel)/s"),
                MetricTile(title: "Peak Accel", value: "\(formatted(summary.peakAcceleration)) \(summary.unitLabel ?? unitLabel)/s²"),
                MetricTile(title: "Path Length", value: "\(formatted(summary.totalPathLength)) \(summary.unitLabel ?? unitLabel)"),
            ]
            qcBadge = summary.qcBadge ?? qcBadge
        } else {
            metricTiles = [
                MetricTile(title: "Avg Confidence", value: "--"),
                MetricTile(title: "Peak Speed", value: "--"),
                MetricTile(title: "Peak Accel", value: "--"),
                MetricTile(title: "Path Length", value: "--"),
            ]
        }

        if let quality = qualitySnapshot {
            qualityNotes = quality.notes ?? []
            qcBadge = quality.qcBadge ?? qcBadge
        } else {
            qualityNotes = []
        }

        analysisModules = analyzerSnapshots.map {
            AnalysisModuleSummary(
                title: $0.title,
                confidence: $0.confidence,
                metrics: $0.metrics.map { metric in
                    "\(metric.key)=\(formatted(metric.value)) \(metric.unitLabel)".trimmingCharacters(in: .whitespaces)
                }
            )
        }
    }

    func buildSessionSnapshot(videoURL: URL) throws -> SessionSnapshot {
        try baseSessionSnapshot(
            videoURL: videoURL,
            trackQuality: resolvedTrackQualitySnapshot(rows: analysisRows, trackID: activeTrackID)
        )
    }

    private func baseSessionSnapshot(videoURL: URL, trackQuality: TrackQualitySnapshot?) throws -> SessionSnapshot {
        let initialBox = try bboxSnapshot(from: targetBox, label: "target box")
        let reference = referenceBox.isComplete ? try bboxSnapshot(from: referenceBox, label: "reference box") : nil
        let scalePoints = try scalePointValues()
        let calibration = CalibrationSnapshot(profile: try buildCalibrationProfile(scalePoints: scalePoints))

        return SessionSnapshot(
            videoPath: videoURL.path,
            initialBbox: initialBox,
            calibration: calibration,
            analysisConfig: AnalysisConfigSnapshot(
                smoothingWindow: Int(smoothingWindow) ?? 7,
                smoothingPolyorder: Int(polyorder) ?? 2
            ),
            trackingConfig: resolvedTrackingConfigSnapshot(),
            metadata: ExperimentMetadataSnapshot(
                experimentLabel: experimentLabel,
                trialID: trialID,
                operatorName: operatorName,
                notes: notes,
                tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            ),
            advancedMode: advancedMode,
            selectedStartFrame: startFrame,
            selectedEndFrame: endFrame,
            scalePoints: scalePoints,
            referenceBbox: reference,
            corrections: corrections.map {
                CorrectionSnapshot(
                    trackID: $0.trackID,
                    frameIndex: $0.frameIndex,
                    bbox: BBoxSnapshot(
                        x: Double($0.bbox.x) ?? 0,
                        y: Double($0.bbox.y) ?? 0,
                        width: Double($0.bbox.width) ?? 0,
                        height: Double($0.bbox.height) ?? 0
                    ),
                    note: $0.note
                )
            },
            reviewState: ReviewStateSnapshot(
                lastFrameIndex: currentFrame,
                selectedWindowStart: selectedWindowStart ?? startFrame,
                selectedWindowEnd: selectedWindowEnd ?? endFrame,
                dismissedReviewFrames: Array(dismissedReviewFrames).sorted()
            ),
            eventMarkers: allEvents.map {
                EventMarkerSnapshot(
                    name: $0.name,
                    frameIndex: $0.frameIndex,
                    timeS: $0.timeSeconds,
                    value: $0.value,
                    unitLabel: $0.unitLabel,
                    axis: $0.axis.isEmpty ? nil : $0.axis,
                    note: $0.note.isEmpty ? nil : $0.note,
                    origin: $0.origin
                )
            },
            additionalObjects: additionalObjects.map {
                AdditionalObjectSnapshot(
                    trackID: $0.trackID,
                    name: $0.name,
                    kind: $0.kind,
                    bbox: BBoxSnapshot(
                        x: Double($0.x) ?? 0,
                        y: Double($0.y) ?? 0,
                        width: Double($0.width) ?? 0,
                        height: Double($0.height) ?? 0
                    )
                )
            },
            trackQuality: trackQuality,
            exportPreferences: ExportPreferencesSnapshot(
                includeOverlay: includeOverlay,
                includeDebugTracking: debugTracking,
                includePlots: includePlots,
                reportTemplate: reportTemplate
            )
        )
    }

    private func resolveNativeScientificSlices(for bundle: AnalysisTrackBundle) -> (summary: SummarySnapshot?, quality: QualitySnapshot?, modules: [AnalyzerSnapshot]) {
        guard let session = currentScientificSessionSnapshot(for: bundle) else {
            return (bundle.summary, bundle.quality, bundle.modules)
        }
        let processedRows = nativeScientificProcessor.process(rows: bundle.analysisRows, session: session)

        let quality = nativeScientificReporter.buildQuality(
            session: session,
            rows: processedRows,
            trackID: bundle.trackID
        )
        let nativeModules = nativeScientificReporter.buildAnalyzers(
            session: session,
            rows: processedRows,
            trackID: bundle.trackID,
            pairwiseMetrics: pairwiseMetrics
        )
        let resolvedModules = nativeModules.isEmpty ? bundle.modules : nativeModules
        let classification = nativeScientificReporter.buildClassification(
            session: session,
            rows: processedRows,
            modules: resolvedModules,
            trackID: bundle.trackID
        )
        let summary = nativeScientificReporter.buildSummary(
            session: session,
            rows: processedRows,
            quality: quality,
            eventCount: mergedNativeEvents(for: bundle, session: session, classification: classification).count,
            trackID: bundle.trackID,
            classification: classification
        )
        derivedEvents = mergedNativeEvents(for: bundle, session: session, classification: classification).filter { $0.origin != "manual" }
        return (summary, quality, resolvedModules)
    }

    private func currentScientificSessionSnapshot(for bundle: AnalysisTrackBundle) -> SessionSnapshot? {
        guard let videoURL = currentVideoURL else { return nil }
        guard let session = try? baseSessionSnapshot(videoURL: videoURL, trackQuality: nil) else { return nil }
        return session
    }

    private func resolvedTrackQualitySnapshot(rows: [AnalysisRow], trackID: String) -> TrackQualitySnapshot? {
        let derivedQuality = nativeTrackQualitySnapshot(rows: rows, trackID: trackID)
        guard trackID == "primary" else {
            return derivedQuality ?? sessionTrackQuality
        }
        guard let sessionTrackQuality else { return derivedQuality }
        guard let derivedQuality else { return sessionTrackQuality }
        return mergeTrackQuality(existing: sessionTrackQuality, derived: derivedQuality)
    }

    private func mergedNativeEvents(
        for bundle: AnalysisTrackBundle,
        session: SessionSnapshot,
        classification: ExperimentClassificationSnapshot
    ) -> [EventMarkerRecord] {
        let nativeDerived = nativeScientificReporter.buildDerivedEvents(
            session: session,
            rows: nativeScientificProcessor.process(rows: bundle.analysisRows, session: session),
            classification: classification
        )
        let baseManualEvents = bundle.trackID == "primary" ? manualEvents : []
        return nativeScientificReporter.mergeEventMarkers(baseManualEvents, withDerived: nativeDerived)
    }

    private func postProcess(loadResult: AnalysisLoadResult, sessionOverride: SessionSnapshot? = nil) -> AnalysisLoadResult {
        guard let session = sessionOverride ?? loadResult.session else { return loadResult }

        var normalized = loadResult
        let reproduce = nativeReproduceCommand(for: session, outputDirectory: normalized.exportDirectory)
        let manualEventCount = (session.eventMarkers ?? []).filter { ($0.origin ?? "manual") == "manual" }.count
        let sourceBundles: [AnalysisTrackBundle] = {
            if normalized.trackBundles.isEmpty {
                return [
                    AnalysisTrackBundle(
                        trackID: "primary",
                        trackName: "Primary Object",
                        trackKind: "primary",
                        summary: normalized.summary,
                        quality: normalized.quality,
                        modules: normalized.modules,
                        analysisRows: normalized.analysisRows,
                        reportMarkdown: normalized.reportMarkdown,
                        exportDirectory: normalized.exportDirectory
                    )
                ]
            }
            return normalized.trackBundles
        }()

        let processedBundles = sourceBundles.map { bundle in
            AnalysisTrackBundle(
                trackID: bundle.trackID,
                trackName: bundle.trackName,
                trackKind: bundle.trackKind,
                summary: bundle.summary,
                quality: bundle.quality,
                modules: bundle.modules,
                analysisRows: nativeScientificProcessor.process(rows: bundle.analysisRows, session: session),
                reportMarkdown: bundle.reportMarkdown,
                exportDirectory: bundle.exportDirectory
            )
        }
        let nativeTracks = processedBundles.compactMap { nativeTrackingPipeline.reconstructTrack(bundle: $0, session: session) }
        let analysesByTrackID = Dictionary(uniqueKeysWithValues: processedBundles.map { ($0.trackID, $0.analysisRows) })
        let resolvedPairwiseMetrics: [PairwiseMetricSnapshot]
        if normalized.pairwiseMetrics.isEmpty {
            resolvedPairwiseMetrics = nativeTrackingPipeline.rebuildPairwiseMetrics(
                tracks: nativeTracks,
                analysesByTrackID: analysesByTrackID
            )
        } else {
            resolvedPairwiseMetrics = normalized.pairwiseMetrics
        }

        normalized.trackBundles = processedBundles.map { bundle in
            rebuiltTrackBundle(
                trackID: bundle.trackID,
                trackName: bundle.trackName,
                trackKind: bundle.trackKind,
                processedRows: bundle.analysisRows,
                reportMarkdown: bundle.reportMarkdown,
                exportDirectory: bundle.exportDirectory,
                session: session,
                pairwiseMetrics: resolvedPairwiseMetrics,
                reproduceCommand: reproduce,
                manualEventCount: bundle.trackID == "primary" ? manualEventCount : 0
            )
        }
        normalized.pairwiseMetrics = resolvedPairwiseMetrics

        let primaryBundle = normalized.trackBundles.first(where: { $0.trackID == "primary" }) ?? normalized.trackBundles.first
        normalized.analysisRows = primaryBundle?.analysisRows ?? nativeScientificProcessor.process(rows: normalized.analysisRows, session: session)
        normalized.summary = primaryBundle?.summary ?? normalized.summary
        normalized.quality = primaryBundle?.quality ?? normalized.quality
        normalized.modules = primaryBundle?.modules ?? normalized.modules
        normalized.reportMarkdown = primaryBundle?.reportMarkdown ?? normalized.reportMarkdown
        let reconstructedTrackQuality = mergedPrimaryTrackQuality(
            existing: session.trackQuality,
            nativeTracks: nativeTracks
        )
        normalized.session = sessionByUpdatingTrackQuality(
            session,
            trackQuality: reconstructedTrackQuality
        )
        return normalized
    }

    private func rebuiltTrackBundle(
        trackID: String,
        trackName: String,
        trackKind: String,
        processedRows: [AnalysisRow],
        reportMarkdown: String,
        exportDirectory: URL,
        session: SessionSnapshot,
        pairwiseMetrics: [PairwiseMetricSnapshot],
        reproduceCommand: String,
        manualEventCount: Int
    ) -> AnalysisTrackBundle {
        let quality = nativeScientificReporter.buildQuality(
            session: session,
            rows: processedRows,
            trackID: trackID
        )
        let modules = nativeScientificReporter.buildAnalyzers(
            session: session,
            rows: processedRows,
            trackID: trackID,
            pairwiseMetrics: pairwiseMetrics
        )
        let classification = nativeScientificReporter.buildClassification(
            session: session,
            rows: processedRows,
            modules: modules,
            trackID: trackID
        )
        let derivedEvents = nativeScientificReporter.buildDerivedEvents(
            session: session,
            rows: processedRows,
            classification: classification
        )
        let mergedEvents = nativeScientificReporter.mergeEventMarkers(
            trackID == "primary" ? manualEventRecords(from: session, includeDerived: false) : [],
            withDerived: derivedEvents
        )
        let summary = nativeScientificReporter.buildSummary(
            session: session,
            rows: processedRows,
            quality: quality,
            eventCount: manualEventCount + derivedEvents.count,
            trackID: trackID,
            classification: classification
        )
        let nativeReport = nativeScientificReporter.buildReport(
            session: session,
            rows: processedRows,
            trackID: trackID,
            trackName: trackName,
            summary: summary,
            quality: quality,
            classification: classification,
            modules: modules,
            pairwiseMetrics: pairwiseMetrics,
            eventMarkers: mergedEvents,
            reproduceCommand: reproduceCommand
        )
        return AnalysisTrackBundle(
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind,
            summary: summary,
            quality: quality,
            modules: modules,
            analysisRows: processedRows,
            reportMarkdown: nativeReport.isEmpty ? reportMarkdown : nativeReport,
            exportDirectory: exportDirectory
        )
    }

    private func manualEventRecords(from session: SessionSnapshot, includeDerived: Bool) -> [EventMarkerRecord] {
        (session.eventMarkers ?? []).compactMap { event in
            let origin = event.origin ?? "derived"
            if !includeDerived && origin != "manual" {
                return nil
            }
            return EventMarkerRecord(
                name: event.name,
                frameIndex: event.frameIndex,
                timeSeconds: event.timeS,
                value: event.value,
                unitLabel: event.unitLabel,
                axis: event.axis ?? "",
                note: event.note ?? "",
                origin: origin
            )
        }
    }

    private func nativeReproduceCommand(for session: SessionSnapshot, outputDirectory: URL) -> String {
        let overlayFlag = (session.exportPreferences?.includeOverlay ?? includeOverlay) ? "" : " --skip-overlay"
        let plotFlag = (session.exportPreferences?.includePlots ?? includePlots) ? "" : " --skip-plots"
        let trackingConfig = session.resolvedTrackingConfig
        let debugFlag = (session.exportPreferences?.includeDebugTracking ?? trackingConfig.debugTracking ?? debugTracking) ? " --debug-tracking" : ""
        let robustRecoveryFlag = (trackingConfig.robustRecovery ?? true) ? "" : " --disable-robust-recovery"
        let bidirectionalFlag = (trackingConfig.bidirectionalRefinement ?? true) ? "" : " --disable-bidirectional-refinement"
        let interpolationFlag = (trackingConfig.interpolateShortGaps ?? true) ? "" : " --disable-interpolate-short-gaps"
        let scaleFactors = (trackingConfig.scaleFactors ?? TrackingConfigSnapshot.pythonDefaults.scaleFactors ?? []).map { String($0) }.joined(separator: " ")
        let report = session.exportPreferences?.reportTemplate ?? reportTemplate
        return """
        python3 -m tracker_ai.cli analyze --video \(session.videoPath) --output-dir \(outputDirectory.path)\(overlayFlag)\(plotFlag)\(debugFlag)\(robustRecoveryFlag)\(bidirectionalFlag)\(interpolationFlag) --report-template \(report) --tracking-profile \((trackingConfig.profile ?? .auto).rawValue) --search-margin \(trackingConfig.searchMargin ?? 2.4) --expanded-search-margin \(trackingConfig.expandedSearchMargin ?? 5.5) --scale-factors \(scaleFactors) --detection-threshold \(trackingConfig.detectionThreshold ?? 0.5) --low-confidence-threshold \(trackingConfig.lowConfidenceThreshold ?? 0.36) --reacquire-threshold \(trackingConfig.reacquireThreshold ?? 0.56) --suspect-after-frames \(trackingConfig.suspectAfterFrames ?? 3) --recovery-after-frames \(trackingConfig.recoveryAfterFrames ?? 5) --max-prediction-frames \(trackingConfig.maxPredictionFrames ?? 8) --template-update-rate \(trackingConfig.templateUpdateRate ?? 0.1) --stable-update-threshold \(trackingConfig.stableUpdateThreshold ?? 0.66) --marker-confidence-bias \(trackingConfig.markerConfidenceBias ?? 0.58) --auto-marker-min-ratio \(trackingConfig.autoMarkerMinRatio ?? 0.12) --max-interpolation-gap \(trackingConfig.maxInterpolationGap ?? 3)
        """
    }

    private func sessionByUpdatingTrackQuality(_ session: SessionSnapshot, trackQuality: TrackQualitySnapshot?) -> SessionSnapshot {
        SessionSnapshot(
            videoPath: session.videoPath,
            initialBbox: session.initialBbox,
            calibration: session.calibration,
            analysisConfig: session.analysisConfig,
            trackingConfig: session.trackingConfig,
            metadata: session.metadata,
            selectedStartFrame: session.selectedStartFrame,
            selectedEndFrame: session.selectedEndFrame,
            scalePoints: session.scalePoints,
            referenceBbox: session.referenceBbox,
            corrections: session.corrections,
            reviewState: session.reviewState,
            eventMarkers: session.eventMarkers,
            additionalObjects: session.additionalObjects,
            trackQuality: trackQuality,
            exportPreferences: session.exportPreferences
        )
    }

    private func mergeTrackQuality(existing: TrackQualitySnapshot, derived: TrackQualitySnapshot) -> TrackQualitySnapshot {
        TrackQualitySnapshot(
            lostSpans: mergedTrackSpans(existing.lostSpans, derived.lostSpans),
            suspectSpans: mergedTrackSpans(existing.suspectSpans, derived.suspectSpans),
            correctedSpans: mergedTrackSpans(existing.correctedSpans, derived.correctedSpans),
            reacquisitionCount: max(existing.reacquisitionCount ?? 0, derived.reacquisitionCount ?? 0),
            reviewRecommended: (existing.reviewRecommended ?? false) || (derived.reviewRecommended ?? false)
        )
    }

    private func mergedTrackSpans(_ lhs: [TrackSpanSnapshot]?, _ rhs: [TrackSpanSnapshot]?) -> [TrackSpanSnapshot]? {
        let combined = (lhs ?? []) + (rhs ?? [])
        guard !combined.isEmpty else { return nil }

        var seen = Set<String>()
        return combined
            .filter { span in
                seen.insert("\(span.startFrame)|\(span.endFrame)|\(span.reason)").inserted
            }
            .sorted { left, right in
                if left.startFrame == right.startFrame {
                    if left.endFrame == right.endFrame {
                        return left.reason < right.reason
                    }
                    return left.endFrame < right.endFrame
                }
                return left.startFrame < right.startFrame
            }
    }

    private func nativeTrackQualitySnapshot(rows: [AnalysisRow], trackID: String) -> TrackQualitySnapshot? {
        guard let session = currentSessionSnapshotForTrackQuality(trackID: trackID) else {
            return rows.isEmpty ? nil : nativeScientificReporter.deriveTrackQuality(rows: rows)
        }
        let bundle = AnalysisTrackBundle(
            trackID: trackID,
            trackName: trackDisplayName(for: trackID),
            trackKind: trackBundles.first(where: { $0.trackID == trackID })?.trackKind ?? (trackID == "primary" ? "primary" : "secondary"),
            summary: nil,
            quality: nil,
            modules: [],
            analysisRows: rows,
            reportMarkdown: "",
            exportDirectory: exportDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory())
        )
        return nativeTrackingPipeline.deriveTrackQuality(for: bundle, session: session)
    }

    private func currentSessionSnapshotForTrackQuality(trackID: String) -> SessionSnapshot? {
        if trackBundles.contains(where: { $0.trackID == trackID }), let currentVideoURL {
            return try? baseSessionSnapshot(videoURL: currentVideoURL, trackQuality: nil)
        }
        if trackID == "primary", let currentVideoURL {
            return try? baseSessionSnapshot(videoURL: currentVideoURL, trackQuality: nil)
        }
        return nil
    }

    private func correctedBBoxForTrack(trackID: String, session: SessionSnapshot) -> BBoxSnapshot {
        if trackID == "primary" {
            return session.initialBbox
        }
        if trackID == "reference", let referenceBBox = session.referenceBbox {
            return referenceBBox
        }
        if let objectBBox = session.additionalObjects?.first(where: { $0.trackID == trackID })?.bbox {
            return objectBBox
        }
        return session.initialBbox
    }

    private func mergedPrimaryTrackQuality(
        existing: TrackQualitySnapshot?,
        nativeTracks: [NativeTrackReconstruction]
    ) -> TrackQualitySnapshot? {
        let derivedQuality = nativeTracks.first(where: { $0.trackID == "primary" })?.quality
        guard let existing else { return derivedQuality }
        guard let derivedQuality else { return existing }
        return mergeTrackQuality(existing: existing, derived: derivedQuality)
    }

    private func bboxSnapshot(from draft: BoundingBoxDraft, label: String) throws -> BBoxSnapshot {
        guard
            let x = Double(draft.x),
            let y = Double(draft.y),
            let width = Double(draft.width),
            let height = Double(draft.height)
        else {
            throw NSError(domain: "TrackerAIMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "The \(label) contains invalid numeric values."])
        }
        return BBoxSnapshot(x: x, y: y, width: width, height: height)
    }

    private func scalePointValues() throws -> [Double] {
        guard
            let x1 = Double(scaleLine.x1),
            let y1 = Double(scaleLine.y1),
            let x2 = Double(scaleLine.x2),
            let y2 = Double(scaleLine.y2)
        else {
            throw NSError(domain: "TrackerAIMac", code: 2, userInfo: [NSLocalizedDescriptionKey: "The scale line contains invalid numeric values."])
        }
        return [x1, y1, x2, y2]
    }

    func calibrationProfileForCurrentSetup() throws -> CalibrationProfile {
        try buildCalibrationProfile(scalePoints: scalePointValues())
    }

    private func buildCalibrationProfile(scalePoints: [Double]) throws -> CalibrationProfile {
        let referenceLengthValue = Double(referenceLength) ?? 1.0
        let resolvedUnitLabel = unitLabel.isEmpty ? "m" : unitLabel
        let mode = CalibrationProfile.normalizedMode(calibrationMode)
        let x1 = scalePoints[0]
        let y1 = scalePoints[1]
        let x2 = scalePoints[2]
        let y2 = scalePoints[3]
        let originX = try calibrationNumber(from: calibrationOriginXInput, fieldName: "origin X", defaultValue: 0)
        let originY = try calibrationNumber(from: calibrationOriginYInput, fieldName: "origin Y", defaultValue: 0)
        let axisAngle = try calibrationNumber(from: calibrationAxisAngleInput, fieldName: "axis angle", defaultValue: 0)

        switch mode {
        case "two_axis":
            let derived = try CalibrationProfile.fromAxisPoints(
                originX: x1,
                originY: y1,
                axisX: x2,
                axisY: y2,
                referenceLength: referenceLengthValue,
                unitLabel: resolvedUnitLabel,
                invertX: calibrationInvertX,
                invertY: calibrationInvertY
            )
            return try CalibrationProfile(
                referenceLength: referenceLengthValue,
                unitLabel: resolvedUnitLabel,
                pixelDistance: derived.pixelDistance,
                mode: mode,
                originXPx: originX == 0 && originY == 0 ? derived.originXPx : originX,
                originYPx: originX == 0 && originY == 0 ? derived.originYPx : originY,
                axisAngleDeg: calibrationAxisAngleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? derived.axisAngleDeg : axisAngle,
                invertX: calibrationInvertX,
                invertY: calibrationInvertY,
                presetName: calibrationPresetName
            )
        case "marker_size":
            return try CalibrationProfile.fromMarkerSize(
                markerBBoxWidthPx: try resolvedCalibrationPixelDistance(),
                referenceLength: referenceLengthValue,
                unitLabel: resolvedUnitLabel,
                presetName: calibrationPresetName
            )
        case "homography":
            return try CalibrationProfile.fromHomography(
                homography: try parsedCalibrationHomography(),
                referenceLength: referenceLengthValue,
                unitLabel: resolvedUnitLabel,
                pixelDistance: resolvedCalibrationPixelDistance(),
                originXPx: originX,
                originYPx: originY,
                presetName: calibrationPresetName
            )
        default:
            let derived = try CalibrationProfile.fromPoints(
                x1: x1,
                y1: y1,
                x2: x2,
                y2: y2,
                referenceLength: referenceLengthValue,
                unitLabel: resolvedUnitLabel
            )
            return try CalibrationProfile(
                referenceLength: referenceLengthValue,
                unitLabel: resolvedUnitLabel,
                pixelDistance: derived.pixelDistance,
                mode: "single_line",
                originXPx: originX,
                originYPx: originY,
                axisAngleDeg: axisAngle,
                invertX: calibrationInvertX,
                invertY: calibrationInvertY,
                presetName: calibrationPresetName
            )
        }
    }

    private func resolvedCalibrationPixelDistance() throws -> Double {
        let trimmed = calibrationPixelDistanceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 20
        }
        guard let value = Double(trimmed), value > 0 else {
            throw NSError(
                domain: "TrackerAIMac",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Marker size / pixel distance must be a positive number."]
            )
        }
        return value
    }

    private func calibrationNumber(from rawValue: String, fieldName: String, defaultValue: Double) throws -> Double {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        guard let value = Double(trimmed) else {
            throw NSError(
                domain: "TrackerAIMac",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Calibration \(fieldName) must be numeric."]
            )
        }
        return value
    }

    private func parsedCalibrationHomography() throws -> [Double] {
        if let calibrationValidationMessage {
            throw NSError(
                domain: "TrackerAIMac",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: calibrationValidationMessage]
            )
        }
        return calibrationHomographyInput
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }
    }

    private func inferredScaleLine(from calibration: CalibrationSnapshot) -> ScaleLineDraft {
        let originX = calibration.originXPx ?? 0
        let originY = calibration.originYPx ?? 0
        let angle = (calibration.axisAngleDeg ?? 0) * .pi / 180
        let distance = calibration.pixelDistance
        let endX = originX + (cos(angle) * distance)
        let endY = originY + (sin(angle) * distance)
        return ScaleLineDraft(
            x1: String(originX),
            y1: String(originY),
            x2: String(endX),
            y2: String(endY)
        )
    }

    private func formattedCalibrationInput(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private func formattedHomographyInput(_ values: [Double]?) -> String {
        guard let values, !values.isEmpty else { return "" }
        return values.map(formattedCalibrationInput).joined(separator: " ")
    }

    private func pixelDistance(from line: ScaleLineDraft) -> Double {
        guard
            let x1 = Double(line.x1),
            let y1 = Double(line.y1),
            let x2 = Double(line.x2),
            let y2 = Double(line.y2)
        else {
            return 0
        }
        let dx = x2 - x1
        let dy = y2 - y1
        return sqrt((dx * dx) + (dy * dy))
    }

    private func collectBatchSessions() throws -> [NativeBatchSessionEntry] {
        var entries: [NativeBatchSessionEntry] = []

        for clip in workspaceClips {
            if !clip.sessionPath.isEmpty, FileManager.default.fileExists(atPath: clip.sessionPath) {
                let snapshot = try engine.loadSession(from: URL(fileURLWithPath: clip.sessionPath))
                entries.append(NativeBatchSessionEntry(clip: clip, session: snapshot))
                continue
            }

            if clip.videoPath == currentVideoURL?.path, let currentVideoURL, isTargetReady, isScaleReady {
                let snapshot = try buildSessionSnapshot(videoURL: currentVideoURL)
                entries.append(NativeBatchSessionEntry(clip: clip, session: snapshot))
            }
        }

        if entries.isEmpty, let currentVideoURL, isTargetReady, isScaleReady {
            let fallbackClip = WorkspaceClip(label: currentVideoURL.deletingPathExtension().lastPathComponent, videoPath: currentVideoURL.path)
            entries.append(NativeBatchSessionEntry(clip: fallbackClip, session: try buildSessionSnapshot(videoURL: currentVideoURL)))
        }

        return entries
    }

    func runConfiguration(from session: SessionSnapshot, outputDirectory: URL) throws -> NativeRunConfiguration {
        let metadata = session.metadata
        let scale = session.scalePoints ?? []
        guard scale.count == 4 else {
            throw NSError(domain: "TrackerAIMac", code: 3, userInfo: [NSLocalizedDescriptionKey: "Session \(session.videoPath) is missing calibration scale points."])
        }

        return NativeRunConfiguration(
            videoURL: URL(fileURLWithPath: session.videoPath),
            outputDirectory: outputDirectory,
            targetBox: BoundingBoxDraft(
                x: String(session.initialBbox.x),
                y: String(session.initialBbox.y),
                width: String(session.initialBbox.width),
                height: String(session.initialBbox.height)
            ),
            scaleLine: ScaleLineDraft(
                x1: String(scale[0]),
                y1: String(scale[1]),
                x2: String(scale[2]),
                y2: String(scale[3])
            ),
            referenceBox: session.referenceBbox.map {
                BoundingBoxDraft(
                    x: String($0.x),
                    y: String($0.y),
                    width: String($0.width),
                    height: String($0.height)
                )
            },
            referenceLength: session.calibration.referenceLength,
            unitLabel: session.calibration.unitLabel,
            startFrame: session.selectedStartFrame ?? 0,
            endFrame: session.selectedEndFrame,
            smoothingWindow: session.analysisConfig.smoothingWindow,
            polyorder: session.analysisConfig.smoothingPolyorder,
            trackingConfig: session.resolvedTrackingConfig,
            trackingProfile: session.resolvedTrackingConfig.profile ?? .auto,
            debugTracking: session.exportPreferences?.includeDebugTracking ?? session.resolvedTrackingConfig.debugTracking ?? false,
            includeOverlay: session.exportPreferences?.includeOverlay ?? true,
            includePlots: session.exportPreferences?.includePlots ?? true,
            reportTemplate: session.exportPreferences?.reportTemplate ?? reportTemplate,
            experimentLabel: metadata?.experimentLabel ?? "",
            trialID: metadata?.trialID ?? "",
            operatorName: metadata?.operatorName ?? "",
            notes: metadata?.notes ?? "",
            tags: metadata?.tags ?? [],
            additionalObjects: (session.additionalObjects ?? []).map {
                AdditionalObjectDraft(
                    trackID: $0.trackID,
                    name: $0.name,
                    kind: $0.kind ?? "secondary",
                    x: String($0.bbox.x),
                    y: String($0.bbox.y),
                    width: String($0.bbox.width),
                    height: String($0.bbox.height)
                )
            }
        )
    }

    private func merge(loadResult: AnalysisLoadResult, preserving preservedSession: SessionSnapshot) -> AnalysisLoadResult {
        var merged = loadResult
        if let generatedSession = loadResult.session {
            merged.session = merge(generated: generatedSession, preserved: preservedSession)
        } else {
            merged.session = preservedSession
        }
        return merged
    }

    private func merge(generated: SessionSnapshot, preserved: SessionSnapshot) -> SessionSnapshot {
        let preservedManualEvents = (preserved.eventMarkers ?? []).filter { ($0.origin ?? "manual") == "manual" }
        let generatedDerivedEvents = (generated.eventMarkers ?? []).filter { ($0.origin ?? "derived") != "manual" }
        var mergedEvents: [EventMarkerSnapshot] = []
        var seen = Set<String>()

        for event in preservedManualEvents + generatedDerivedEvents {
            let key = "\(event.name)|\(event.frameIndex)|\(event.origin ?? "derived")"
            if seen.insert(key).inserted {
                mergedEvents.append(event)
            }
        }

        return SessionSnapshot(
            videoPath: generated.videoPath,
            initialBbox: preserved.initialBbox,
            calibration: preserved.calibration,
            analysisConfig: preserved.analysisConfig,
            trackingConfig: preserved.trackingConfig ?? generated.trackingConfig,
            metadata: preserved.metadata ?? generated.metadata,
            advancedMode: preserved.advancedMode ?? generated.advancedMode,
            selectedStartFrame: preserved.selectedStartFrame ?? generated.selectedStartFrame,
            selectedEndFrame: preserved.selectedEndFrame ?? generated.selectedEndFrame,
            scalePoints: preserved.scalePoints ?? generated.scalePoints,
            referenceBbox: preserved.referenceBbox ?? generated.referenceBbox,
            corrections: (preserved.corrections?.isEmpty == false) ? preserved.corrections : generated.corrections,
            reviewState: preserved.reviewState ?? generated.reviewState,
            eventMarkers: mergedEvents,
            additionalObjects: preserved.additionalObjects ?? generated.additionalObjects,
            trackQuality: generated.trackQuality ?? preserved.trackQuality,
            exportPreferences: preserved.exportPreferences ?? generated.exportPreferences
        )
    }

    private func applyTrackingConfig(_ snapshot: TrackingConfigSnapshot?) {
        internalTrackingConfig = (snapshot ?? .pythonDefaults).resolved()
        trackingProfile = internalTrackingConfig.profile ?? .auto
        trackingRobustRecovery = internalTrackingConfig.robustRecovery ?? true
        trackingBidirectionalRefinement = internalTrackingConfig.bidirectionalRefinement ?? true
        debugTracking = internalTrackingConfig.debugTracking ?? false
    }

    private func resolvedTrackingConfigSnapshot() -> TrackingConfigSnapshot {
        var snapshot = internalTrackingConfig.resolved()
        snapshot.profile = trackingProfile
        snapshot.robustRecovery = trackingRobustRecovery
        snapshot.bidirectionalRefinement = trackingBidirectionalRefinement
        snapshot.debugTracking = debugTracking
        return snapshot
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.3f", value)
    }
}
