import SwiftUI

struct ReviewJournalView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            TrackerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionEyebrow(text: "Review Queue")
                    HStack(spacing: 10) {
                        Button("Window Start = Current", action: markWindowStart)
                            .buttonStyle(GhostActionButtonStyle())
                        Button("Window End = Current", action: markWindowEnd)
                            .buttonStyle(GhostActionButtonStyle())
                        Button("Dismiss Current Frame", action: dismissCurrentFrame)
                            .buttonStyle(GhostActionButtonStyle())
                        Button("Restore Dismissed", action: restoreDismissed)
                            .buttonStyle(GhostActionButtonStyle())
                    }
                    Text(windowStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(TrackerTheme.muted)
                    if model.reviewQueue.isEmpty {
                        Text("No imported review spans yet. Running analysis or loading a session will populate suspect and lost segments.")
                            .font(.system(size: 14))
                            .foregroundStyle(TrackerTheme.muted)
                    } else {
                        ForEach(model.reviewQueue) { issue in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.title)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(issueFrameText(issue))
                                        .font(.system(size: 12))
                                        .foregroundStyle(TrackerTheme.muted)
                                    Text(issue.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(TrackerTheme.muted)
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Button("Jump", action: { model.jumpToReviewIssue(issue) })
                                        .buttonStyle(GhostActionButtonStyle())
                                    if issue.dismissible {
                                        Button("Dismiss", action: { model.dismissReviewIssue(issue) })
                                            .buttonStyle(GhostActionButtonStyle())
                                    }
                                    StatusPill(text: issue.severity.capitalized, tone: tone(for: issue.severity))
                                }
                            }
                            .padding(12)
                            .background(TrackerTheme.steel.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Correction Anchors")
                        HStack(spacing: 10) {
                            Button("Draw Correction On Video", action: drawCorrection)
                                .buttonStyle(PrimaryActionButtonStyle())
                            Button("Cancel Drawing", action: cancelDrawing)
                                .buttonStyle(GhostActionButtonStyle())
                        }
                        if model.corrections.isEmpty {
                            Text("No stored correction anchors in the current session.")
                                .font(.system(size: 13))
                                .foregroundStyle(TrackerTheme.muted)
                        } else {
                            ForEach(model.corrections) { correction in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Frame \(correction.frameIndex)")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("\(correction.note) • \(correction.bbox.x), \(correction.bbox.y), \(correction.bbox.width), \(correction.bbox.height)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(TrackerTheme.muted)
                                    }
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Button("Edit", action: { model.startCorrectionDrawing(existing: correction) })
                                            .buttonStyle(GhostActionButtonStyle())
                                        Button("Remove", action: { model.removeCorrection(correction) })
                                            .buttonStyle(GhostActionButtonStyle())
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(TrackerTheme.steel.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }

                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Tracked Companions")
                        if model.additionalObjects.isEmpty {
                            Text("No secondary objects configured.")
                                .font(.system(size: 13))
                                .foregroundStyle(TrackerTheme.muted)
                        } else {
                            ForEach(model.additionalObjects) { object in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(object.name)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("\(object.trackID) • \(object.kind)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(TrackerTheme.muted)
                                    }
                                    Spacer()
                                    Button("Redraw", action: { model.startAdditionalObjectDrawing(existing: object) })
                                        .buttonStyle(GhostActionButtonStyle())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(TrackerTheme.steel.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }
            }

            TrackerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionEyebrow(text: "Manual Event Journal")
                    MacFormRow(label: "Event") { TextField("release", text: $model.manualEventName) }
                    MacFormRow(label: "Value") { TextField("0", text: $model.manualEventValue) }
                    MacFormRow(label: "Unit") { TextField("m/s", text: $model.manualEventUnit) }
                    MacFormRow(label: "Note") { TextField("Operator note", text: $model.manualEventNote) }
                    HStack(spacing: 10) {
                        Button("Mark Current Frame", action: addEvent)
                            .buttonStyle(PrimaryActionButtonStyle())
                        Text("Current frame: \(model.currentFrame)")
                            .font(.system(size: 13))
                            .foregroundStyle(TrackerTheme.muted)
                    }

                    if model.manualEvents.isEmpty {
                        Text("No manual events yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(TrackerTheme.muted)
                    } else {
                        ForEach(model.manualEvents) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(event.name) @ frame \(event.frameIndex)")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(event.note.isEmpty ? "No note" : event.note)
                                        .font(.system(size: 12))
                                        .foregroundStyle(TrackerTheme.muted)
                                }
                                Spacer()
                                Button("Remove", action: { model.removeManualEvent(event) })
                                    .buttonStyle(GhostActionButtonStyle())
                            }
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(model.metricTiles) { tile in
                    MetricTileView(tile: tile)
                }
            }
        }
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
