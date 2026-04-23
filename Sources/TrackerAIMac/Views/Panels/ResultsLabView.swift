import Charts
import SwiftUI

struct ResultsLabView: View {
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
                                eyebrow: "Results",
                                title: resultsHeaderTitle,
                                detail: resultsHeaderDetail
                            )

                            Spacer(minLength: 0)

                            StatusPill(text: resultsStatusText, tone: resultsStatusTone)
                        }
                    }

                    HStack(spacing: TrackerTheme.Spacing.xs) {
                        ForEach(ResultsSubtab.allCases) { tab in
                            NavChipButton(title: tab.title, selected: model.selectedResultsTab == tab) {
                                model.selectedResultsTab = tab
                            }
                        }
                    }

                    HStack(spacing: TrackerTheme.Spacing.xs) {
                        if model.trackBundles.count > 1 {
                            TrackerControlSurface(width: 260) {
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

                        if !model.pairwiseMetrics.isEmpty {
                            TrackerControlSurface(width: 320) {
                                Picker(
                                    "Pair",
                                    selection: Binding(
                                        get: { model.selectedPairwiseMetricID ?? model.pairwiseMetrics.first?.id ?? "" },
                                        set: { model.selectPairwiseMetric($0) }
                                    )
                                ) {
                                    ForEach(model.pairwiseMetrics) { metric in
                                        Text("\(model.trackDisplayName(for: metric.primaryTrackID)) ↔ \(model.trackDisplayName(for: metric.secondaryTrackID))")
                                            .tag(metric.id)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                }
            }

            if !model.hasActiveAnalysisResults {
                TrackerPanel {
                    InlineEmptyState(
                        eyebrow: "No Results Yet",
                        title: "The active clip does not have loaded analysis results.",
                        detail: model.currentVideoURL == nil
                            ? "Import a clip first, then run analysis or open a saved session to populate graphs, quality metrics, events, and exports."
                            : "This clip is still in setup. Results will appear here only after the active clip has its own analysis run or loaded session.",
                        symbolName: "waveform.path.ecg"
                    )
                }
            } else {
                TrackerPanel {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TrackerTheme.Spacing.xs) {
                        PairwiseMetricTile(title: "Track", value: model.activeTrackLabel)
                        PairwiseMetricTile(title: "Rows", value: "\(model.analysisRows.count)")
                        PairwiseMetricTile(title: "QC", value: model.qcBadge.capitalized)
                        PairwiseMetricTile(title: "Export", value: model.exportDirectory?.lastPathComponent ?? "Pending")
                    }
                }

                switch model.selectedResultsTab {
                case .insights:
                    insightsPanel
                case .graphs:
                    graphsPanel
                case .window:
                    windowPanel
                case .events:
                    eventsPanel
                case .quality:
                    qualityPanel
                case .pairwise:
                    pairwisePanel
                case .table:
                    tablePanel
                case .reproduce:
                    reproducePanel
                }
            }
        }
    }

    private var insightsPanel: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                PanelSectionHeader(
                    eyebrow: "Insights",
                    title: "Analysis modules and classification",
                    detail: "Use this summary to understand what was measured before you inspect charts or exports."
                )

                Text("Viewing \(model.activeTrackLabel)")
                    .trackerText(.bodyStrong, color: TrackerTheme.muted)

                StatusPill(text: model.qcBadge, style: .accent)

                if let classification = model.summarySnapshot?.classification {
                    insightBlock(
                        title: classification.title,
                        subtitle: "Classification confidence \(String(format: "%.2f", classification.confidence))",
                        detailLines: [classification.summary],
                        warm: true
                    )
                }

                ForEach(model.analysisModules) { module in
                    insightBlock(
                        title: module.title,
                        subtitle: "Confidence \(String(format: "%.2f", module.confidence))",
                        detailLines: module.metrics
                    )
                }
            }
        }
    }

    private var graphsPanel: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                PanelSectionHeader(
                    eyebrow: "Graphs",
                    title: "Kinematics",
                    detail: "Speed and scientific confidence stay aligned to the active track and current frame window."
                )

                Chart(model.analysisRows) { row in
                    LineMark(x: .value("Time", row.timeSeconds), y: .value("Speed", row.speed))
                        .foregroundStyle(TrackerTheme.accent)
                    LineMark(x: .value("Time", row.timeSeconds), y: .value("Scientific Confidence", row.scientificConfidence))
                        .foregroundStyle(TrackerTheme.navy)
                }
                .frame(height: 280)
            }
        }
    }

    private var windowPanel: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                PanelSectionHeader(
                    eyebrow: "Window",
                    title: "Window statistics",
                    detail: "Compute regional statistics over the part of the clip you want to discuss or publish."
                )

                HStack(spacing: TrackerTheme.Spacing.xxs) {
                    Button("Window Start = Current", action: setWindowStart)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(!model.canUseReviewTools)
                    Button("Window End = Current", action: setWindowEnd)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(!model.canUseReviewTools)
                    Button("Reset Window", action: resetWindow)
                        .buttonStyle(TertiaryActionButtonStyle())
                        .disabled(!model.canUseReviewTools)
                }

                if let window = model.windowSummary {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TrackerTheme.Spacing.xs) {
                        PairwiseMetricTile(title: "Frame Window", value: "\(window.startFrame) → \(window.endFrame)")
                        PairwiseMetricTile(title: "Duration", value: String(format: "%.3f s", window.durationSeconds))
                        PairwiseMetricTile(title: "Displacement", value: String(format: "%.3f %@", window.displacement, model.unitLabel))
                        PairwiseMetricTile(title: "Mean Speed", value: String(format: "%.3f %@/s", window.meanSpeed, model.unitLabel))
                        PairwiseMetricTile(title: "Max Speed", value: String(format: "%.3f %@/s", window.maxSpeed, model.unitLabel))
                        PairwiseMetricTile(title: "Max Acceleration", value: String(format: "%.3f %@/s²", window.maxAcceleration, model.unitLabel))
                    }
                    Text(model.timelineMarkers.joined(separator: " | "))
                        .trackerText(.monoBody, color: TrackerTheme.muted)
                } else {
                    InlineEmptyState(
                        eyebrow: "Window Too Narrow",
                        title: "Choose a wider frame window to compute regional statistics.",
                        detail: "Set the start and end markers farther apart, then reopen this panel.",
                        symbolName: "timeline.selection"
                    )
                }
            }
        }
    }

    private var eventsPanel: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                PanelSectionHeader(
                    eyebrow: "Events",
                    title: "Event journal",
                    detail: "Manual and derived events stay in one chronological list for the active clip."
                )

                if model.allEvents.isEmpty {
                    InlineEmptyState(
                        eyebrow: "No Events",
                        title: "No events are available for this clip yet.",
                        detail: "Mark study events in Review or load a saved session that already includes event timing.",
                        symbolName: "flag"
                    )
                } else {
                    ForEach(model.allEvents) { event in
                        HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
                            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                                Text("\(event.name) [\(event.origin)]")
                                    .trackerText(.cardTitle)
                                Text("Frame \(event.frameIndex) • \(String(format: "%.3f", event.timeSeconds)) s • \(String(format: "%.3f", event.value)) \(event.unitLabel)")
                                    .trackerText(.caption, color: TrackerTheme.muted)
                            }
                            Spacer()
                        }
                        .padding(TrackerTheme.Spacing.xs)
                        .background(TrackerTheme.steel.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                                .strokeBorder(TrackerTheme.panelStroke.opacity(0.48), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
                    }
                }
            }
        }
    }

    private var qualityPanel: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                PanelSectionHeader(
                    eyebrow: "Quality",
                    title: "Confidence, risk, and drift signals",
                    detail: "These markers help decide whether the run is ready to trust, review, or rerun."
                )

                Text("Viewing \(model.activeTrackLabel)")
                    .trackerText(.bodyStrong, color: TrackerTheme.muted)
                StatusPill(text: model.qcBadge, style: .warning)

                if let quality = model.qualitySnapshot {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TrackerTheme.Spacing.xs) {
                        PairwiseMetricTile(title: "Quality Index", value: String(format: "%.3f", quality.qualityIndex ?? 0))
                        PairwiseMetricTile(title: "Calibration Confidence", value: String(format: "%.3f", quality.calibrationConfidence ?? 0))
                        PairwiseMetricTile(title: "Drift Sensitivity", value: String(format: "%.3f", quality.driftSensitivity ?? 0))
                        PairwiseMetricTile(title: "Interpolation Burden", value: String(format: "%.3f", quality.interpolatedBurdenRatio ?? 0))
                    }
                }

                if model.qualityNotes.isEmpty {
                    Text("No additional quality notes were generated for this run.")
                        .trackerText(.body, color: TrackerTheme.muted)
                } else {
                    ForEach(model.qualityNotes, id: \.self) { note in
                        Text("• \(note)")
                            .trackerText(.body)
                    }
                }

                if let anomalies = model.qualitySnapshot?.anomalies, !anomalies.isEmpty {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxs) {
                        Text("Quality Alerts")
                            .trackerText(.sectionTitle)
                        ForEach(anomalies.prefix(6)) { anomaly in
                            QualityAnomalyRow(anomaly: anomaly)
                        }
                    }
                }

                if let spanScores = model.qualitySnapshot?.spanScores, !spanScores.isEmpty {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxs) {
                        Text("Highest-Risk Spans")
                            .trackerText(.sectionTitle)
                        ForEach(spanScores.sorted(by: { $0.severityScore > $1.severityScore }).prefix(6)) { span in
                            QualitySpanRow(span: span)
                        }
                    }
                }
            }
        }
    }

    private var pairwisePanel: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                PanelSectionHeader(
                    eyebrow: "Pairwise",
                    title: "Relative motion",
                    detail: "Use this panel to validate spacing, contact timing, and near-collision behavior."
                )

                if let metric = model.selectedPairwiseMetric {
                    Text("\(model.trackDisplayName(for: metric.primaryTrackID)) ↔ \(model.trackDisplayName(for: metric.secondaryTrackID))")
                        .trackerText(.sectionTitle)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TrackerTheme.Spacing.xs) {
                        PairwiseMetricTile(title: "Minimum Separation", value: String(format: "%.3f %@", metric.minimumSeparation, model.unitLabel))
                        PairwiseMetricTile(title: "Peak Relative Speed", value: String(format: "%.3f %@/s", metric.peakRelativeSpeed, model.unitLabel))
                        PairwiseMetricTile(title: "Mean Separation", value: String(format: "%.3f %@", metric.meanSeparation, model.unitLabel))
                        PairwiseMetricTile(title: "Collision Frame", value: metric.collisionFrame.map(String.init) ?? "Not Detected")
                    }

                    Chart(metric.samples) { sample in
                        LineMark(x: .value("Time", sample.timeSeconds), y: .value("Distance", sample.distanceUnits))
                            .foregroundStyle(TrackerTheme.accent)
                        LineMark(x: .value("Time", sample.timeSeconds), y: .value("Relative Speed", sample.relativeSpeedUnitsPerSecond))
                            .foregroundStyle(TrackerTheme.navy)
                    }
                    .frame(height: 260)
                } else {
                    InlineEmptyState(
                        eyebrow: "Single Object",
                        title: "Pairwise metrics appear when more than one object is tracked.",
                        detail: "Add companion objects in Setup if the experiment needs separation or interaction analysis.",
                        symbolName: "point.3.filled.connected.trianglepath.dotted"
                    )
                }
            }
        }
    }

    private var tablePanel: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                PanelSectionHeader(
                    eyebrow: "Table",
                    title: "Data table",
                    detail: "Scan raw and derived values without leaving the active clip context."
                )

                HStack(spacing: TrackerTheme.Spacing.xs) {
                    Text("Viewing \(model.activeTrackLabel)")
                        .trackerText(.bodyStrong, color: TrackerTheme.muted)
                    Spacer()
                    TrackerControlSurface(width: 180) {
                        Picker(
                            "Preset",
                            selection: Binding(
                                get: { model.selectedTablePreset },
                                set: { model.setTablePreset($0) }
                            )
                        ) {
                            ForEach(ResultsTablePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                ResultsTableView(model: model)
            }
        }
    }

    private var reproducePanel: some View {
        VStack(spacing: TrackerTheme.Spacing.sm) {
            TrackerPanel {
                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                    PanelSectionHeader(
                        eyebrow: "Export",
                        title: "Export and reproducibility",
                        detail: "Package the active clip results, preserve the audit trail, and reopen the workflow later."
                    )

                    HStack(spacing: TrackerTheme.Spacing.xxs) {
                        Button("Export Results", action: exportNativeResearchPackage)
                            .buttonStyle(PrimaryActionButtonStyle())
                            .disabled(!model.canExportResearchPackage)
                        Button("Run Batch Analysis", action: runWorkspaceBatch)
                            .buttonStyle(SuccessActionButtonStyle())
                            .disabled(!model.canRunWorkspaceBatch)
                    }

                    Text(model.exportGuardrailMessage)
                        .trackerText(.caption, color: TrackerTheme.muted)
                    Text(model.workspaceBatchGuardrailMessage)
                        .trackerText(.caption, color: TrackerTheme.muted)

                    if let exportDirectory = model.exportDirectory {
                        Text("Export directory: \(exportDirectory.path)")
                            .trackerText(.body, color: TrackerTheme.muted)
                    }

                    TextEditor(text: .constant(model.reproduceCommand))
                        .font(TrackerTheme.Typography.monoBody)
                        .frame(minHeight: 160)
                }
            }

            VStack(spacing: TrackerTheme.Spacing.sm) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Profile",
                            title: "Export profile",
                            detail: "These options describe what the current export package will contain."
                        )
                        Text("Overlay: \(model.includeOverlay ? "Included" : "Skipped")")
                            .trackerText(.body)
                        Text("Plots: \(model.includePlots ? "Included" : "Skipped")")
                            .trackerText(.body)
                        Text("Debug Tracking: \(model.debugTracking ? "Included" : "Skipped")")
                            .trackerText(.body)
                        Text("Template: \(model.reportTemplate.capitalized)")
                            .trackerText(.body)
                    }
                }

                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Objects",
                            title: "Tracked objects",
                            detail: "Export packages include the active object set used in the current run."
                        )

                        if model.additionalObjects.isEmpty {
                            Text("Primary object only.")
                                .trackerText(.body, color: TrackerTheme.muted)
                        } else {
                            ForEach(model.additionalObjects) { object in
                                Text("• \(object.name) [\(object.trackID)]")
                                    .trackerText(.body)
                            }
                        }
                    }
                }
            }

            if let aggregate = model.batchAggregate {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Batch",
                            title: "Batch overview",
                            detail: "These aggregate values summarize the most recent workspace batch export."
                        )
                        Text("Trials: \(aggregate.trialCount)")
                            .trackerText(.body)
                        Text("Mean Peak Speed: \(String(format: "%.3f", aggregate.meanPeakSpeed))")
                            .trackerText(.body)
                        Text("Mean Peak Accel: \(String(format: "%.3f", aggregate.meanPeakAcceleration))")
                            .trackerText(.body)
                        Text("Mean Scientific Confidence: \(String(format: "%.3f", aggregate.meanScientificConfidence))")
                            .trackerText(.body)
                        Text("Mean Quality Index: \(String(format: "%.3f", aggregate.meanQualityIndex))")
                            .trackerText(.body)
                        Text("Mean Event Count: \(String(format: "%.2f", aggregate.meanEventCount))")
                            .trackerText(.body)
                        if let bestQualityTrialID = aggregate.bestQualityTrialID {
                            Text("Best Quality Trial: \(bestQualityTrialID)")
                                .trackerText(.cardTitle)
                        }
                    }
                }
            }
        }
    }

    private func insightBlock(title: String, subtitle: String, detailLines: [String], warm: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs + 2) {
            Text(title)
                .trackerText(.sectionTitle)
            Text(subtitle)
                .trackerText(.caption, color: TrackerTheme.muted)
            ForEach(detailLines, id: \.self) { line in
                Text(line.hasPrefix("•") ? line : "• \(line)")
                    .trackerText(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TrackerTheme.Spacing.xs)
        .background((warm ? TrackerTheme.warm : TrackerTheme.steel).opacity(warm ? 0.6 : 0.35))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.48), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }

    private var resultsHeaderTitle: String {
        model.hasActiveAnalysisResults ? "Results for \(model.currentTrialHeadline)" : "Results lab"
    }

    private var resultsHeaderDetail: String {
        if model.hasActiveAnalysisResults {
            return "Graphs, quality, events, and exports are tied to the active clip and selected track."
        }
        if model.currentVideoURL == nil {
            return "Import a clip first. Results remain empty until the workspace has a real active video."
        }
        return "This clip is loaded, but it has not been analyzed yet."
    }

    private var resultsStatusText: String {
        model.hasActiveAnalysisResults ? "Loaded" : "Awaiting run"
    }

    private var resultsStatusTone: Color {
        model.hasActiveAnalysisResults ? TrackerTheme.success : TrackerTheme.warning
    }

    private func exportNativeResearchPackage() {
        model.exportNativeResearchPackage()
    }

    private func runWorkspaceBatch() {
        Task {
            await model.runWorkspaceBatchAnalysis()
        }
    }

    private func setWindowStart() {
        model.setWindowStartToCurrentFrame()
    }

    private func setWindowEnd() {
        model.setWindowEndToCurrentFrame()
    }

    private func resetWindow() {
        model.resetWindowSelection()
    }
}

private struct PairwiseMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs + 2) {
            Text(title.uppercased())
                .trackerText(.eyebrow, color: TrackerTheme.tertiaryText)
            Text(value)
                .trackerText(.sectionTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TrackerTheme.Spacing.sm - 2)
        .background(TrackerTheme.steel.opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.46), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
    }
}

private struct ResultsTableView: View {
    @Bindable var model: AppModel

    var body: some View {
        let columns = model.tableColumns(for: model.selectedTablePreset)
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(columns, id: \.self) { column in
                        Text(column.uppercased())
                            .trackerText(.eyebrow, color: TrackerTheme.tertiaryText)
                            .frame(width: columnWidth(for: column), alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(TrackerTheme.warm)
                    }
                }

                ForEach(Array(model.analysisRows.prefix(250).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.self) { column in
                            Text(model.tableValue(for: row, column: column))
                                .trackerText(.monoBody)
                                .frame(width: columnWidth(for: column), alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(row.frameIndex.isMultiple(of: 2) ? TrackerTheme.steel.opacity(0.20) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
        }
        .frame(minHeight: 320)
    }

    private func columnWidth(for column: String) -> CGFloat {
        switch column {
        case "reason":
            return 220
        case "state", "flags":
            return 100
        default:
            return 96
        }
    }
}

private struct QualityAnomalyRow: View {
    let anomaly: QualityAnomalySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs + 2) {
            HStack {
                Text(anomaly.title)
                    .trackerText(.cardTitle)
                Spacer()
                StatusPill(text: anomaly.severity, style: .warning)
            }
            Text(frameLabel)
                .trackerText(.monoBody, color: TrackerTheme.muted)
            Text(anomaly.summary)
                .trackerText(.caption)
            if let recommendedAction = anomaly.recommendedAction {
                Text(recommendedAction)
                    .trackerText(.caption, color: TrackerTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TrackerTheme.Spacing.xs)
        .background(TrackerTheme.steel.opacity(0.28))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.46), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }

    private var frameLabel: String {
        if let endFrame = anomaly.endFrame, endFrame != anomaly.startFrame {
            return "Frames \(anomaly.startFrame)-\(endFrame) • score \(String(format: "%.3f", anomaly.score))"
        }
        return "Frame \(anomaly.startFrame) • score \(String(format: "%.3f", anomaly.score))"
    }
}

private struct QualitySpanRow: View {
    let span: QualitySpanScoreSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs + 2) {
            HStack {
                Text(span.category.replacingOccurrences(of: "_", with: " ").capitalized)
                    .trackerText(.cardTitle)
                Spacer()
                Text(String(format: "%.3f", span.severityScore))
                    .trackerText(.monoCaption, color: TrackerTheme.warning)
            }
            Text("Frames \(span.startFrame)-\(span.endFrame) • tracker \(String(format: "%.3f", span.averageTrackerConfidence)) • scientific \(String(format: "%.3f", span.scientificConfidenceMean))")
                .trackerText(.monoBody, color: TrackerTheme.muted)
            Text(span.reason)
                .trackerText(.caption)
            if let failure = span.dominantFailureReason {
                Text("Failure mode: \(failure)")
                    .trackerText(.caption, color: TrackerTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TrackerTheme.Spacing.xs)
        .background(TrackerTheme.steel.opacity(0.20))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.46), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }
}
