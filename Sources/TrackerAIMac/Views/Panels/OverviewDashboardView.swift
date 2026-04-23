import SwiftUI

struct OverviewDashboardView: View {
    @Bindable var model: AppModel
    let showsHero: Bool

    init(model: AppModel, showsHero: Bool = true) {
        self.model = model
        self.showsHero = showsHero
    }

    var body: some View {
        VStack(spacing: TrackerTheme.Spacing.sm) {
            if showsHero {
                HeroPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.sm - 2) {
                        HStack(alignment: .top, spacing: TrackerTheme.Spacing.sm) {
                            PanelSectionHeader(
                                eyebrow: "Overview",
                                title: overviewTitle,
                                detail: model.activeClipReadinessSummary,
                                titleColor: .white,
                                detailColor: Color.white.opacity(0.82)
                            )

                            Spacer(minLength: 0)

                            StatusPill(text: overviewStatusText, style: .inverse)
                        }

                        LazyVGrid(columns: overviewStatusColumns, alignment: .leading, spacing: 10) {
                            CurrentTrialStatusCard(title: "Preset", value: model.selectedPreset.title, tone: TrackerTheme.ink)
                            CurrentTrialStatusCard(title: "Frame Range", value: overviewFrameRange, tone: TrackerTheme.ink)
                            CurrentTrialStatusCard(title: "Workflow", value: model.workflowState.title, tone: TrackerTheme.ink)
                            CurrentTrialStatusCard(title: "Results", value: overviewResultStatus, tone: TrackerTheme.ink)
                        }
                    }
                }
            }

            if model.currentVideoURL == nil {
                TrackerPanel {
                    InlineEmptyState(
                        eyebrow: "Import First",
                        title: "The overview stays quiet until a real clip is active.",
                        detail: "Open a video to unlock calibration, tracking, review, quality summaries, and export guidance without showing stale results from another session.",
                        symbolName: "film.stack",
                        actionTitle: "Open Video",
                        action: { model.openVideo() }
                    )
                }
            } else {
                VStack(spacing: TrackerTheme.Spacing.sm) {
                    TrackerPanel {
                        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                            PanelSectionHeader(
                                eyebrow: "Readiness Board",
                                title: "Current clip status",
                                detail: "Each row reflects only the active clip in the workspace."
                            )
                            ReadinessRow(title: "Video import", complete: model.currentVideoURL != nil)
                            ReadinessRow(title: "Frame range", complete: model.hasValidFrameRange)
                            ReadinessRow(title: "Calibration", complete: model.isScaleReady)
                            ReadinessRow(title: "Target box", complete: model.isTargetReady)
                            ReadinessRow(title: "Analysis results", complete: model.hasActiveAnalysisResults)
                            ReadinessRow(title: "Review journal", complete: !model.manualEvents.isEmpty || !model.reviewQueue.isEmpty)
                            ReadinessRow(title: "Export ready", complete: model.canExportResearchPackage)
                        }
                    }

                    TrackerPanel {
                        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                            PanelSectionHeader(
                                eyebrow: "Study Guidance",
                                title: model.selectedPreset.reviewFocus,
                                detail: model.selectedPreset.setupTip
                            )

                            if model.hasActiveAnalysisResults {
                                if let classification = model.summarySnapshot?.classification {
                                    Text("Motion classification: \(classification.title) (\(String(format: "%.2f", classification.confidence)))")
                                        .trackerText(.cardTitle)
                                }

                                if model.qualityNotes.isEmpty {
                                    Text("Run notes, quality warnings, and summary guidance will appear here after analysis.")
                                        .trackerText(.body, color: TrackerTheme.muted)
                                } else {
                                    ForEach(model.qualityNotes, id: \.self) { note in
                                        Text("• \(note)")
                                            .trackerText(.body)
                                    }
                                }
                            } else {
                                Text("This clip has not been analyzed yet. Complete calibration and target setup, then run analysis to populate scientific summaries.")
                                    .trackerText(.body, color: TrackerTheme.muted)
                            }
                        }
                    }
                }
            }

            VStack(spacing: TrackerTheme.Spacing.sm) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Presets",
                            title: "Experiment defaults",
                            detail: "Apply a preset when you want tracking and reporting defaults tuned for a specific study style."
                        )

                        TrackerControlSurface(width: 320) {
                            Picker("Preset", selection: $model.selectedPresetID) {
                                ForEach(model.presets) { preset in
                                    Text(preset.title).tag(preset.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Text(model.selectedPreset.description)
                            .trackerText(.body, color: TrackerTheme.muted)

                        Button("Apply Preset", action: applyPreset)
                            .buttonStyle(PrimaryActionButtonStyle())
                    }
                }

                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Trust Markers",
                            title: trustMarkerTitle,
                            detail: trustMarkerDetail
                        )

                        if let aggregate = model.batchAggregate {
                            Text("Batch mean quality index: \(String(format: "%.3f", aggregate.meanQualityIndex))")
                                .trackerText(.cardTitle)
                            Text("Classification spread: \(aggregate.classifications.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " • "))")
                                .trackerText(.caption, color: TrackerTheme.muted)
                        } else {
                            ReadinessRow(title: "Saved session available", complete: model.canSaveWorkspace || !model.workspaceClips.isEmpty)
                            ReadinessRow(title: "Quality signals loaded", complete: model.hasTrackQualitySignals)
                            ReadinessRow(title: "Export destination set", complete: model.exportDirectory != nil)
                            if model.canRunWorkspaceBatch {
                                Button("Run Batch Analysis") {
                                    Task {
                                        await model.runWorkspaceBatchAnalysis()
                                    }
                                }
                                .buttonStyle(SuccessActionButtonStyle())
                            }
                            Text(model.workspaceBatchGuardrailMessage)
                                .trackerText(.caption, color: TrackerTheme.muted)
                        }
                    }
                }
            }
        }
    }

    private func applyPreset() {
        model.applyPreset(model.selectedPreset)
    }

    private var overviewStatusColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 120, maximum: 220), spacing: 10, alignment: .top), count: 2)
    }

    private var overviewTitle: String {
        model.currentVideoURL == nil ? "Experiment overview" : model.currentTrialHeadline
    }

    private var overviewFrameRange: String {
        model.currentVideoURL == nil ? "No clip loaded" : "\(model.startFrame) → \(model.endFrame)"
    }

    private var overviewResultStatus: String {
        model.hasActiveAnalysisResults ? "Loaded" : "Pending"
    }

    private var overviewStatusText: String {
        model.currentVideoURL == nil ? "Awaiting import" : model.workflowState.title
    }

    private var trustMarkerTitle: String {
        if model.hasActiveAnalysisResults {
            return "Active clip results are ready for review and export."
        }
        if model.currentVideoURL != nil {
            return "The active clip is still in setup."
        }
        return "No clip is active in the workspace."
    }

    private var trustMarkerDetail: String {
        if model.hasActiveAnalysisResults {
            return "Review, quality, and export surfaces now reflect the same active clip."
        }
        if model.currentVideoURL != nil {
            return "No results will be shown here until this clip has its own analysis run or loaded session."
        }
        return "Import a clip to start collecting readiness, quality, and export markers."
    }
}
