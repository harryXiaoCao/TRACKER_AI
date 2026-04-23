import SwiftUI

struct ReviewJournalView: View {
    @Bindable var model: AppModel
    let showsHeader: Bool

    init(model: AppModel, showsHeader: Bool = true) {
        self.model = model
        self.showsHeader = showsHeader
    }

    var body: some View {
        VStack(spacing: TrackerTheme.Spacing.sm) {
            TrackerPanel {
                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                    if showsHeader {
                        HStack(alignment: .top, spacing: TrackerTheme.Spacing.sm) {
                            PanelSectionHeader(
                                eyebrow: "Review",
                                title: reviewHeaderTitle,
                                detail: model.reviewGuardrailMessage
                            )

                            Spacer(minLength: 0)

                            StatusPill(text: reviewStatusText, tone: reviewStatusTone)
                        }
                    }

                    if model.trackBundles.count > 1 {
                        TrackerControlSurface(width: 320) {
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
                    }

                    HStack(spacing: TrackerTheme.Spacing.xxs) {
                        Button("Next Problem", action: jumpNextProblem)
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(!model.canNavigateToNextReviewIssue)
                        Button("Next Correction", action: jumpNextCorrection)
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(!model.canNavigateToNextCorrection)
                        Button("Window Start = Current", action: markWindowStart)
                            .buttonStyle(TertiaryActionButtonStyle())
                            .disabled(!model.canUseReviewTools)
                        Button("Window End = Current", action: markWindowEnd)
                            .buttonStyle(TertiaryActionButtonStyle())
                            .disabled(!model.canUseReviewTools)
                        Button("Full Window", action: resetWindow)
                            .buttonStyle(TertiaryActionButtonStyle())
                            .disabled(!model.canUseReviewTools)
                    }

                    Text(windowStatus)
                        .trackerText(.caption, color: TrackerTheme.muted)
                }
            }

            if !model.hasActiveAnalysisResults {
                TrackerPanel {
                    InlineEmptyState(
                        eyebrow: "Analysis Required",
                        title: "Review tools unlock after the active clip has results.",
                        detail: model.currentVideoURL == nil
                            ? "Import a clip first, then complete setup and run analysis."
                            : "This clip has no loaded analysis yet, so corrections and flagged spans stay hidden until the current clip is processed.",
                        symbolName: "checklist"
                    )
                }
            } else {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Queue",
                            title: "Flagged spans and review actions",
                            detail: "Use this list to jump directly to low-confidence, lost, or manually marked frames."
                        )

                        HStack(spacing: TrackerTheme.Spacing.xxs) {
                            Button("Dismiss Current Frame", action: dismissCurrentFrame)
                                .buttonStyle(TertiaryActionButtonStyle())
                                .disabled(!model.canUseReviewTools)
                            Button("Restore Dismissed", action: restoreDismissed)
                                .buttonStyle(TertiaryActionButtonStyle())
                                .disabled(!model.canUseReviewTools)
                        }

                        if model.reviewQueue.isEmpty {
                            InlineEmptyState(
                                eyebrow: "No Flags",
                                title: "The active clip has no queued review issues.",
                                detail: "Manual events, corrections, and quality alerts will appear here when the current analysis needs attention.",
                                symbolName: "checkmark.shield"
                            )
                        } else {
                            ForEach(model.reviewQueue) { issue in
                                reviewIssueRow(issue)
                            }
                        }
                    }
                }
            }

            VStack(spacing: TrackerTheme.Spacing.sm) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Corrections",
                            title: "Correction anchors",
                            detail: "Apply and replay manual anchors when the active track needs a verified position."
                        )

                        HStack(spacing: TrackerTheme.Spacing.xxs) {
                            Button("Draw Correction On Video", action: drawCorrection)
                                .buttonStyle(PrimaryActionButtonStyle())
                                .disabled(!model.canDrawCorrection)
                            Button("Replay Current Track", action: replayCurrentCorrection)
                                .buttonStyle(SecondaryActionButtonStyle())
                                .disabled(!model.canReplayCorrections)
                            Button("Cancel Drawing", action: cancelDrawing)
                                .buttonStyle(DestructiveActionButtonStyle())
                        }

                        if model.corrections.isEmpty {
                            InlineEmptyState(
                                eyebrow: "No Anchors",
                                title: "No correction anchors are stored for this session.",
                                detail: "Draw a correction only when the current track needs a manual intervention.",
                                symbolName: "scope"
                            )
                        } else {
                            ForEach(model.corrections) { correction in
                                correctionRow(correction)
                            }
                        }
                    }
                }

                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Objects",
                            title: "Additional tracked objects",
                            detail: "These saved objects support pairwise analysis, collision studies, and relative motion review."
                        )

                        if model.additionalObjects.isEmpty {
                            InlineEmptyState(
                                eyebrow: "Primary Only",
                                title: "This session is currently tracking one main object.",
                                detail: "Add companion objects in Setup when the experiment needs spacing or interaction measurements.",
                                symbolName: "circle.grid.2x2"
                            )
                        } else {
                            ForEach(model.additionalObjects) { object in
                                additionalObjectRow(object)
                            }
                        }
                    }
                }
            }

            TrackerPanel {
                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                    PanelSectionHeader(
                        eyebrow: "Event Journal",
                        title: "Manual review events",
                        detail: "Mark release, impact, or any study-specific moment at the current frame."
                    )

                    MacFormRow(label: "Event", helper: "Short label") {
                        TrackerTextField(placeholder: "release", text: $model.manualEventName)
                    }
                    MacFormRow(label: "Value", helper: "Numeric") {
                        TrackerTextField(placeholder: "0", text: $model.manualEventValue)
                    }
                    MacFormRow(label: "Unit", helper: "Shown in results") {
                        TrackerTextField(placeholder: "m/s", text: $model.manualEventUnit)
                    }
                    MacFormRow(label: "Note", helper: "Optional context") {
                        TrackerTextField(placeholder: "Operator note", text: $model.manualEventNote)
                    }

                    HStack(spacing: TrackerTheme.Spacing.xxs) {
                        Button("Mark Current Frame", action: addEvent)
                            .buttonStyle(SuccessActionButtonStyle())
                            .disabled(model.currentVideoURL == nil)
                        Text("Current frame: \(model.currentFrame)")
                            .trackerText(.body, color: TrackerTheme.muted)
                    }

                    if model.manualEvents.isEmpty {
                        Text("No manual events have been added for the active clip yet.")
                            .trackerText(.body, color: TrackerTheme.muted)
                    } else {
                        ForEach(model.manualEvents) { event in
                            HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
                                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                                    Text("\(event.name) @ frame \(event.frameIndex)")
                                        .trackerText(.cardTitle)
                                    Text(event.note.isEmpty ? "No note" : event.note)
                                        .trackerText(.caption, color: TrackerTheme.muted)
                                }
                                Spacer()
                                Button("Remove", action: { model.removeManualEvent(event) })
                                    .buttonStyle(DestructiveActionButtonStyle())
                            }
                        }
                    }
                }
            }

            if model.hasActiveAnalysisResults {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TrackerTheme.Spacing.xs) {
                    ForEach(model.metricTiles) { tile in
                        MetricTileView(tile: tile)
                    }
                }
            }
        }
    }

    private var reviewHeaderTitle: String {
        model.hasActiveAnalysisResults ? "Reviewing \(model.activeTrackLabel)" : "Review journal"
    }

    private var reviewStatusText: String {
        model.hasActiveAnalysisResults ? "\(model.reviewQueue.count) queued" : "Locked"
    }

    private var reviewStatusTone: Color {
        model.hasActiveAnalysisResults ? TrackerTheme.accent : TrackerTheme.muted
    }

    private func reviewIssueRow(_ issue: ReviewIssue) -> some View {
        HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                Text(issue.title)
                    .trackerText(.cardTitle)
                Text(issueFrameText(issue))
                    .trackerText(.caption, color: TrackerTheme.muted)
                Text(issue.detail)
                    .trackerText(.caption, color: TrackerTheme.muted)
            }

            Spacer()

            HStack(spacing: TrackerTheme.Spacing.xxs) {
                Button("Jump", action: { model.jumpToReviewIssue(issue) })
                    .buttonStyle(SecondaryActionButtonStyle())
                if issue.dismissible {
                    Button("Dismiss", action: { model.dismissReviewIssue(issue) })
                        .buttonStyle(DestructiveActionButtonStyle())
                }
                StatusPill(text: issue.severity.capitalized, tone: tone(for: issue.severity))
            }
        }
        .padding(TrackerTheme.Spacing.xs)
        .background(TrackerTheme.steel.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }

    private func correctionRow(_ correction: CorrectionRecord) -> some View {
        HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                Text("Frame \(correction.frameIndex)")
                    .trackerText(.cardTitle)
                Text("\(model.trackDisplayName(for: correction.trackID)) • \(correction.note)")
                    .trackerText(.caption, color: TrackerTheme.muted)
                Text("\(correction.bbox.x), \(correction.bbox.y), \(correction.bbox.width), \(correction.bbox.height)")
                    .trackerText(.monoBody, color: TrackerTheme.muted)
            }

            Spacer()

            HStack(spacing: TrackerTheme.Spacing.xxs) {
                Button("Replay", action: { replay(correction) })
                    .buttonStyle(SecondaryActionButtonStyle())
                Button("Edit", action: { model.startCorrectionDrawing(existing: correction) })
                    .buttonStyle(TertiaryActionButtonStyle())
                Button("Remove", action: { model.removeCorrection(correction) })
                    .buttonStyle(DestructiveActionButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TrackerTheme.Spacing.xs)
        .background(TrackerTheme.steel.opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }

    private func additionalObjectRow(_ object: AdditionalObjectDraft) -> some View {
        HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                Text(object.name)
                    .trackerText(.cardTitle)
                Text("\(object.trackID) • \(object.kind)")
                    .trackerText(.caption, color: TrackerTheme.muted)
            }
            Spacer()
            Button("Redraw", action: { model.startAdditionalObjectDrawing(existing: object) })
                .buttonStyle(SecondaryActionButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TrackerTheme.Spacing.xs)
        .background(TrackerTheme.steel.opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }

    private func addEvent() {
        model.addManualEvent()
    }

    private func drawCorrection() {
        model.startCorrectionDrawing()
    }

    private func cancelDrawing() {
        model.cancelAnnotation()
    }

    private func replayCurrentCorrection() {
        Task {
            await model.applyCorrectionReplay()
        }
    }

    private func replay(_ correction: CorrectionRecord) {
        Task {
            await model.applyCorrectionReplay(for: correction)
        }
    }

    private func markWindowStart() {
        model.setWindowStartToCurrentFrame()
    }

    private func markWindowEnd() {
        model.setWindowEndToCurrentFrame()
    }

    private func dismissCurrentFrame() {
        model.dismissCurrentFrameFromReview()
    }

    private func restoreDismissed() {
        model.restoreDismissedReviews()
    }

    private func resetWindow() {
        model.resetWindowSelection()
    }

    private func jumpNextProblem() {
        model.jumpToNextProblemFrame()
    }

    private func jumpNextCorrection() {
        model.jumpToNextCorrectionFrame()
    }

    private func issueFrameText(_ issue: ReviewIssue) -> String {
        if let endFrame = issue.endFrame, endFrame != issue.frameIndex {
            return "Frames \(issue.frameIndex) → \(endFrame)"
        }
        return "Frame \(issue.frameIndex)"
    }

    private var windowStatus: String {
        let start = model.selectedWindowStart ?? model.startFrame
        let end = model.selectedWindowEnd ?? model.endFrame
        return "Review window: \(start) → \(end) • dismissed: \(model.dismissedReviewFrames.count)"
    }

    private func tone(for severity: String) -> Color {
        switch severity {
        case "critical": return TrackerTheme.critical
        case "warning": return TrackerTheme.warning
        default: return TrackerTheme.success
        }
    }
}
