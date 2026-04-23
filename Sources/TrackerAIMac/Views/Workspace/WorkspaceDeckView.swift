import AVKit
import SwiftUI

struct WorkspaceDeckView: View {
    @Bindable var model: AppModel
    let embeddedInShell: Bool
    @State private var showAdvancedInspectorMetrics = false

    init(model: AppModel, embeddedInShell: Bool = false) {
        self.model = model
        self.embeddedInShell = embeddedInShell
    }

    var body: some View {
        VStack(spacing: TrackerTheme.Spacing.sm) {
            if !embeddedInShell {
                TrackerPanel {
                    HStack(alignment: .top, spacing: TrackerTheme.Spacing.sm + 2) {
                        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.sm - 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    SectionEyebrow(text: "Workspace")
                                    Text(model.currentTrialHeadline)
                                        .trackerText(.appTitle)
                                        .lineLimit(1)
                                }

                                StatusPill(text: clipStateLabel, tone: clipStateTone)
                            }

                            Text(workspaceHeaderSummary)
                                .trackerText(.body, color: TrackerTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            LazyVGrid(columns: trialStatusColumns, alignment: .leading, spacing: 10) {
                                CurrentTrialStatusCard(title: "Preset", value: model.selectedPreset.title)
                                CurrentTrialStatusCard(title: "Frame Range", value: "\(model.startFrame) → \(model.endFrame)")
                                CurrentTrialStatusCard(title: "Active Track", value: model.activeTrackLabel)
                                CurrentTrialStatusCard(title: "Classification", value: trialClassificationLabel)
                                CurrentTrialStatusCard(title: "Review", value: trialReviewStatus, tone: trialReviewTone)
                                CurrentTrialStatusCard(title: "Reference", value: model.referenceMarkerStatus, tone: trialReferenceTone)
                            }

                            HStack(spacing: 8) {
                                StatusPill(text: "Step \(activeWorkflowIndex) of \(WorkflowState.allCases.count)", style: .processing)
                                StatusPill(text: model.workflowState.title, tone: workflowTone)
                                StatusPill(text: workflowReadinessLabel, tone: workflowReadinessTone)
                            }
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 10) {
                            Button(primaryHeaderActionTitle, action: primaryHeaderAction)
                                .buttonStyle(PrimaryActionButtonStyle())

                            HStack(spacing: 8) {
                                Menu {
                                    Button("Open Video", action: openVideo)
                                    Button("Load Session", action: loadSession)
                                    Button("Load Workspace", action: loadWorkspace)
                                    Divider()
                                    Button("Save Session", action: saveSession)
                                        .disabled(!model.canSaveSession)
                                    Button("Save Workspace", action: saveWorkspace)
                                        .disabled(!model.canSaveWorkspace)
                                } label: {
                                    Label("Workspace Actions", systemImage: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()

                                Toggle("Advanced", isOn: $model.advancedMode)
                                    .toggleStyle(.switch)
                                    .fixedSize()
                            }
                            .trackerText(.caption, color: TrackerTheme.muted)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        SectionEyebrow(text: "Workspace Clips")
                        Text("Switch trials without leaving the video workspace.")
                            .trackerText(.body, color: TrackerTheme.muted)
                    }

                    Spacer()

                    if !model.workspaceClips.isEmpty {
                        Menu {
                            ForEach(model.workspaceClips) { clip in
                                Button {
                                    model.activateWorkspaceClip(clip)
                                } label: {
                                    if isActiveClip(clip) {
                                        Label(clip.label, systemImage: "checkmark")
                                    } else {
                                        Text(clip.label)
                                    }
                                }
                            }
                        } label: {
                            Label("\(model.workspaceClips.count) clips", systemImage: "square.stack.3d.forward.dottedline")
                                .trackerText(.caption, color: TrackerTheme.muted)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }

                if model.workspaceClips.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "film.stack")
                            .trackerText(.bodyStrong, color: TrackerTheme.muted)
                        Text("Open a video, session, or workspace to build your trial strip.")
                            .trackerText(.body, color: TrackerTheme.muted)
                    }
                    .padding(.horizontal, TrackerTheme.Spacing.sm - 2)
                    .padding(.vertical, TrackerTheme.Spacing.xs)
                    .background(TrackerTheme.panel.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous)
                            .stroke(TrackerTheme.panelStroke.opacity(0.75), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.workspaceClips) { clip in
                                WorkspaceClipStripButton(
                                    clip: clip,
                                    isActive: isActiveClip(clip),
                                    subtitle: clipSubtitle(for: clip),
                                    badge: clipBadge(for: clip),
                                    action: { model.activateWorkspaceClip(clip) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !embeddedInShell {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionEyebrow(text: "Workflow")
                                Text(model.workflowState.title)
                                    .trackerText(.sectionTitle)
                                Text(currentWorkflowSummary)
                                    .trackerText(.body, color: TrackerTheme.muted)
                            }

                            Spacer()

                            if let nextState = model.nextRecommendedWorkflowState {
                                Button(nextActionTitle(for: nextState), action: { performPrimaryAction(for: nextState) })
                                    .buttonStyle(PrimaryActionButtonStyle())
                            } else {
                                StatusPill(text: "Workflow Ready", style: .complete)
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(WorkflowState.allCases.enumerated()), id: \.element.id) { index, state in
                                WorkflowStepCard(
                                    index: index + 1,
                                    title: state.title,
                                    detail: detailText(for: state),
                                    tone: workflowCardTone(for: state),
                                    action: { openWorkflowState(state) }
                                )
                            }
                        }
                    }
                }

                if !model.completedMilestones.isEmpty {
                    TrackerPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionEyebrow(text: "Milestones")
                                Spacer()
                                Text(model.milestoneBannerSummary)
                                    .trackerText(.caption, color: TrackerTheme.muted)
                            }

                            ForEach(model.completedMilestones) { milestone in
                                CompletionBanner(milestone: milestone)
                            }
                        }
                    }
                }
            }

            TrackerPanel(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionEyebrow(text: embeddedInShell ? "Import Stage" : "Live Video Workspace")
                            Text(embeddedInShell
                                ? "The video stage stays primary while import, clip switching, and truthful empty states remain close at hand."
                                : "Use the video stage for calibration, target placement, and frame-by-frame review.")
                                .trackerText(.body, color: TrackerTheme.muted)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Frame \(model.currentFrame)")
                                .trackerText(.cardTitle)
                            Text(model.currentFrameTimestampText)
                                .trackerText(.caption, color: TrackerTheme.muted)
                        }
                    }
                    .padding(.horizontal, TrackerTheme.Spacing.md)
                    .padding(.top, TrackerTheme.Spacing.md)
                    .padding(.bottom, TrackerTheme.Spacing.sm + 2)

                    VideoWorkspaceView(model: model)
                        .frame(minHeight: 460)
                        .padding(.horizontal, TrackerTheme.Spacing.md)
                        .padding(.bottom, TrackerTheme.Spacing.md)
                }
            }
            .frame(maxHeight: .infinity)

            TrackerPanel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionEyebrow(text: "Workspace Controls")
                            Text("Playback, review, and frame selection are grouped by task.")
                                .trackerText(.body, color: TrackerTheme.muted)
                        }

                        Spacer()

                        Text(model.statusMessage)
                            .trackerText(.caption, color: TrackerTheme.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    LazyVGrid(columns: bottomControlColumns, alignment: .leading, spacing: 12) {
                        WorkspaceControlCard(title: "Playback", detail: "Move through the clip without leaving the canvas.") {
                            HStack(spacing: 8) {
                                Button("Step -1", action: stepBackward)
                                    .buttonStyle(GhostActionButtonStyle())
                                Button("Step +1", action: stepForward)
                                    .buttonStyle(GhostActionButtonStyle())
                            }
                        }

                        WorkspaceControlCard(title: "Frame Metrics", detail: "Live values for the current frame and active track.") {
                            VStack(alignment: .leading, spacing: 8) {
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

                                DisclosureGroup(isExpanded: advancedMetricsExpandedBinding) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        WorkspaceMetricRow(label: "BBox", value: model.currentFrameBBoxText)
                                        WorkspaceMetricRow(label: "Speed", value: model.currentFrameSpeedText)
                                        WorkspaceMetricRow(label: "Accel", value: model.currentFrameAccelerationText)
                                        WorkspaceMetricRow(label: "Reference", value: model.currentFrameReferenceText)
                                        WorkspaceMetricRow(label: "Engine", value: model.engineState.rawValue)
                                    }
                                    .padding(.top, 8)
                                } label: {
                                    HStack {
                                        Text(model.advancedMode ? "Advanced metrics are pinned on" : "Show advanced metrics")
                                            .trackerText(.caption)
                                        Spacer()
                                        Text(model.advancedMode ? "Advanced mode" : "Optional")
                                            .trackerText(.helper, color: TrackerTheme.muted)
                                    }
                                }
                            }
                        }

                        WorkspaceControlCard(title: "Review Jumps", detail: "Move quickly to issues, corrections, and downstream workspaces.") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Button("Next Problem", action: jumpNextProblem)
                                        .buttonStyle(GhostActionButtonStyle())
                                        .disabled(!model.canNavigateToNextReviewIssue)
                                    Button("Next Correction", action: jumpNextCorrection)
                                        .buttonStyle(GhostActionButtonStyle())
                                        .disabled(!model.canNavigateToNextCorrection)
                                }
                                HStack(spacing: 8) {
                                    Button("Overview", action: jumpOverview)
                                        .buttonStyle(GhostActionButtonStyle())
                                    Button("Setup", action: jumpSetup)
                                        .buttonStyle(GhostActionButtonStyle())
                                    Button("Review", action: jumpReview)
                                        .buttonStyle(GhostActionButtonStyle())
                                        .disabled(!model.canJumpToReview)
                                    Button("Results", action: jumpResults)
                                        .buttonStyle(GhostActionButtonStyle())
                                        .disabled(!model.canJumpToResults)
                                }
                            }
                        }

                        WorkspaceControlCard(title: "Range Selection", detail: "Set the analysis window and scrub through the active trial.") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Button("Set Start", action: useCurrentFrameAsStart)
                                        .buttonStyle(GhostActionButtonStyle())
                                        .disabled(!model.canUseFrameRangeControls)
                                    Button("Set End", action: useCurrentFrameAsEnd)
                                        .buttonStyle(GhostActionButtonStyle())
                                        .disabled(!model.canUseFrameRangeControls)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Frame \(model.currentFrame) / \(model.endFrame)")
                                        .trackerText(.cardTitle)
                                    Slider(
                                        value: Binding(
                                            get: { Double(model.currentFrame) },
                                            set: { model.setCurrentFrame(from: $0) }
                                        ),
                                        in: Double(model.startFrame)...model.maxFrame
                                    )
                                    Text("Selected range \(model.startFrame) → \(model.endFrame)")
                                        .trackerText(.caption, color: TrackerTheme.muted)
                                }
                            }
                        }
                    }
                }
            }
        }
        .id(workspaceRenderKey)
    }

    private func openVideo() {
        model.openVideo()
    }

    private func loadSession() {
        model.loadSession()
    }

    private func loadWorkspace() {
        model.loadWorkspace()
    }

    private func saveWorkspace() {
        model.saveWorkspace()
    }

    private func saveSession() {
        model.saveSession()
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

    private var currentWorkflowSummary: String {
        if let nextState = model.nextRecommendedWorkflowState {
            return "\(model.workflowState.helperText) Next recommended action: \(nextActionTitle(for: nextState))."
        }
        return "\(model.workflowState.helperText) All critical workflow steps are available."
    }

    private var workspaceHeaderSummary: String {
        if model.currentVideoURL == nil {
            return "Load a clip or saved session to begin calibration, tracking, review, and export."
        }

        return "\(model.selectionMessage) Frame range \(model.startFrame)-\(model.endFrame). Active track: \(model.activeTrackLabel)."
    }

    private var clipStateLabel: String {
        if let url = model.currentVideoURL {
            return url.lastPathComponent
        }
        return "No clip loaded"
    }

    private var clipStateTone: Color {
        model.currentVideoURL == nil ? TrackerTheme.warning : TrackerTheme.success
    }

    private var trialStatusColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 120, maximum: 220), spacing: 10, alignment: .top), count: 3)
    }

    private var trialClassificationLabel: String {
        guard model.currentVideoURL != nil else { return "Pending import" }
        return model.summarySnapshot?.classification?.title ?? "Pending"
    }

    private var trialReviewStatus: String {
        guard model.currentVideoURL != nil else { return "No active review" }
        if model.reviewQueue.isEmpty {
            return "No open issues"
        }
        return "\(model.reviewQueue.count) item\(model.reviewQueue.count == 1 ? "" : "s")"
    }

    private var trialReviewTone: Color {
        guard model.currentVideoURL != nil else { return TrackerTheme.muted }
        return model.reviewQueue.isEmpty ? TrackerTheme.success : TrackerTheme.warning
    }

    private var trialReferenceTone: Color {
        guard model.currentVideoURL != nil else { return TrackerTheme.muted }
        return model.isReferenceReady ? TrackerTheme.success : TrackerTheme.muted
    }

    private func isActiveClip(_ clip: WorkspaceClip) -> Bool {
        clip.videoPath == model.currentVideoURL?.path
    }

    private func clipSubtitle(for clip: WorkspaceClip) -> String {
        if !clip.sessionPath.isEmpty {
            return "Saved session"
        }
        if clip.videoPath == model.currentVideoURL?.path {
            return "Active clip"
        }
        return "Video only"
    }

    private func clipBadge(for clip: WorkspaceClip) -> String {
        if isActiveClip(clip) {
            return "Active"
        }
        if !clip.sessionPath.isEmpty {
            return "Saved"
        }
        return "Loaded"
    }

    private var activeWorkflowIndex: Int {
        (WorkflowState.allCases.firstIndex(of: model.workflowState) ?? 0) + 1
    }

    private var workflowTone: Color {
        switch model.workflowState {
        case .import:
            return TrackerTheme.warning
        case .calibrate:
            return TrackerTheme.accent
        case .track:
            return TrackerTheme.navy
        case .review:
            return TrackerTheme.success
        case .export:
            return TrackerTheme.critical
        }
    }

    private var workflowReadinessLabel: String {
        if let nextState = model.nextRecommendedWorkflowState {
            return "Next: \(nextState.title)"
        }
        return "Export Ready"
    }

    private var workflowReadinessTone: Color {
        model.nextRecommendedWorkflowState == nil ? TrackerTheme.success : TrackerTheme.muted
    }

    private var workspaceRenderKey: String {
        [
            model.currentVideoURL?.path ?? "no-video",
            String(model.workspaceClips.count),
            String(model.reviewQueue.count),
            String(model.analysisRows.count),
            model.workflowState.id,
            model.statusMessage
        ].joined(separator: "|")
    }

    private var bottomControlColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 220, maximum: .infinity), spacing: 12, alignment: .top), count: 2)
    }

    private var advancedMetricsExpandedBinding: Binding<Bool> {
        Binding(
            get: { model.advancedMode || showAdvancedInspectorMetrics },
            set: { showAdvancedInspectorMetrics = $0 }
        )
    }

    private var primaryHeaderActionTitle: String {
        if let nextState = model.nextRecommendedWorkflowState {
            return nextActionTitle(for: nextState)
        }
        return model.currentVideoURL == nil ? "Open Video" : "Open Export"
    }

    private func primaryHeaderAction() {
        if let nextState = model.nextRecommendedWorkflowState {
            performPrimaryAction(for: nextState)
            return
        }

        if model.currentVideoURL == nil {
            openVideo()
        } else {
            openWorkflowState(.export)
        }
    }

    private func workflowCardTone(for state: WorkflowState) -> WorkflowStepCard.Tone {
        if model.completedWorkflowStates.contains(state) {
            return .completed
        }
        if model.workflowState == state {
            return .current
        }
        if model.nextRecommendedWorkflowState == state {
            return .next
        }
        return .blocked
    }

    private func detailText(for state: WorkflowState) -> String {
        switch workflowCardTone(for: state) {
        case .completed:
            return "Completed. \(state.helperText)"
        case .current:
            return "Current step. \(state.helperText)"
        case .next:
            return "Ready next. \(state.helperText)"
        case .blocked:
            return "Blocked until earlier workflow steps are complete."
        }
    }

    private func nextActionTitle(for state: WorkflowState) -> String {
        switch state {
        case .import:
            return "Open Video"
        case .calibrate:
            return model.currentVideoURL == nil ? "Open Video" : "Open Setup"
        case .track:
            return model.canRunAnalysis ? "Run Analysis" : "Finish Setup"
        case .review:
            return "Open Review"
        case .export:
            return "Open Export"
        }
    }

    private func openWorkflowState(_ state: WorkflowState) {
        guard workflowCardTone(for: state) != .blocked else { return }

        switch state {
        case .import:
            model.selectedTab = .overview
        case .calibrate, .track:
            model.selectedTab = .setup
        case .review:
            model.selectedTab = .review
        case .export:
            model.selectedTab = .results
            model.selectedResultsTab = .reproduce
        }
    }

    private func performPrimaryAction(for state: WorkflowState) {
        switch state {
        case .import:
            openVideo()
        case .calibrate:
            openWorkflowState(.calibrate)
        case .track:
            if model.canRunAnalysis {
                Task { await model.runAnalysis() }
            } else {
                openWorkflowState(.calibrate)
            }
        case .review:
            openWorkflowState(.review)
        case .export:
            openWorkflowState(.export)
        }
    }
}

private struct WorkspaceClipStripButton: View {
    let clip: WorkspaceClip
    let isActive: Bool
    let subtitle: String
    let badge: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clip.label)
                            .trackerText(.cardTitle, color: isActive ? .white : TrackerTheme.ink)
                            .lineLimit(1)

                        Text(subtitle)
                            .trackerText(.helper, color: isActive ? Color.white.opacity(0.76) : TrackerTheme.muted)
                    }

                    Spacer(minLength: 8)

                    Text(badge)
                        .trackerText(.eyebrow, color: isActive ? .white : TrackerTheme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isActive ? Color.white.opacity(0.16) : TrackerTheme.steel.opacity(0.65))
                        .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    Image(systemName: isActive ? "play.fill" : "film")
                        .trackerText(.helper, color: isActive ? Color.white.opacity(0.82) : TrackerTheme.muted)
                    Text(clip.videoPath.split(separator: "/").last.map(String.init) ?? clip.label)
                        .trackerText(.helper, color: isActive ? Color.white.opacity(0.82) : TrackerTheme.muted)
                        .lineLimit(1)
                }
            }
            .frame(width: 220, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(backgroundStyle)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var backgroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [TrackerTheme.navy, Color(red: 0.153, green: 0.314, blue: 0.416)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(TrackerTheme.panel)
    }

    private var borderColor: Color {
        isActive ? TrackerTheme.navy.opacity(0.95) : TrackerTheme.panelStroke.opacity(0.85)
    }
}

private struct VideoWorkspaceView: View {
    @Bindable var model: AppModel
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TrackerTheme.navy.opacity(0.96),
                            Color.black.opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            if let player = model.player {
                GeometryReader { proxy in
                    let videoRect = aspectFitRect(content: model.sourceVideoSize, in: proxy.size)

                    MacVideoPlayerView(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            overlayBadges
                        }
                        .overlay(alignment: .topTrailing) {
                            overlayControls
                        }
                        .overlay(alignment: .bottomTrailing) {
                            stageReadout
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
                        .font(.system(size: 54, weight: .light, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text("No video loaded")
                        .trackerText(.sectionTitle, color: .white)
                    Text("Open a video or activate a workspace clip to populate the video workspace.")
                        .trackerText(.body, color: Color.white.opacity(0.72))
                }
            }
        }
    }

    private var overlayBadges: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusPill(text: model.engineState.rawValue, tone: badgeColor)
            if model.isScaleReady { StatusPill(text: "Calibration Ready", style: .processing) }
            if model.isTargetReady { StatusPill(text: "Target Ready", style: .complete) }
            if model.isReferenceReady { StatusPill(text: "Reference Ready", style: .ready) }
            if !model.additionalObjects.isEmpty { StatusPill(text: "\(model.additionalObjects.count) Additional Object(s)", style: .ready) }
            if model.annotationMode != .idle {
                StatusPill(text: "Drawing \(model.annotationMode.rawValue.capitalized)", style: .warning)
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(18)
    }

    private var badgeColor: Color {
        switch model.engineState {
        case .ready: return TrackerTheme.success
        case .running: return TrackerTheme.warning
        case .unavailable: return TrackerTheme.critical
        }
    }

    private var overlayControls: some View {
        HStack(spacing: 8) {
            stageControlButton(title: "Step -1", action: { model.stepFrame(by: -1) })
            stageControlButton(title: "Step +1", action: { model.stepFrame(by: 1) })
        }
        .padding(18)
    }

    private var stageReadout: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(model.currentFrameTrackName)
                .trackerText(.caption, color: .white)
            Text(model.currentFrameStateText)
                .trackerText(.helper, color: Color.white.opacity(0.76))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(18)
    }

    private func stageControlButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StageControlButtonStyle())
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
                            .trackerText(.eyebrow, color: TrackerTheme.navy)
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

private struct StageControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrackerButtonStyle(variant: .stage).makeBody(configuration: configuration)
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
                .trackerText(.eyebrow, color: TrackerTheme.tertiaryText)
            Spacer()
            Text(value)
                .trackerText(.cardTitle)
        }
    }
}
