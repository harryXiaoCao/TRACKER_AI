import Charts
import SwiftUI

struct ResultsLabView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            TrackerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionEyebrow(text: "Results")
                    Text("Move between insights, graphs, quality, pairwise metrics, events, and reproducibility without losing trial context.")
                        .font(.system(size: 14))
                        .foregroundStyle(TrackerTheme.muted)
                    HStack(spacing: 10) {
                        ForEach(ResultsSubtab.allCases) { tab in
                            NavChipButton(title: tab.title, selected: model.selectedResultsTab == tab) {
                                model.selectedResultsTab = tab
                            }
                        }
                        if model.trackBundles.count > 1 || !model.pairwiseMetrics.isEmpty {
                            HStack(spacing: 12) {
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
                                    .frame(maxWidth: 260, alignment: .leading)
                                }

                                if !model.pairwiseMetrics.isEmpty {
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
                                    .frame(maxWidth: 320, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }

            switch model.selectedResultsTab {
            case .insights:
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Analysis Modules")
                        Text("Viewing \(model.activeTrackLabel)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TrackerTheme.muted)
                        StatusPill(text: model.qcBadge, tone: TrackerTheme.accent)
                        if let classification = model.summarySnapshot?.classification {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(classification.title)
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Native classification confidence \(String(format: "%.2f", classification.confidence))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(TrackerTheme.muted)
                                Text(classification.summary)
                                    .font(.system(size: 13))
                                    .foregroundStyle(TrackerTheme.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(TrackerTheme.warm.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        ForEach(model.analysisModules) { module in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(module.title)
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Confidence \(String(format: "%.2f", module.confidence))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(TrackerTheme.muted)
                                ForEach(module.metrics, id: \.self) { metric in
                                    Text("• \(metric)")
                                        .font(.system(size: 13))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(TrackerTheme.steel.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }

            case .graphs:
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Kinematics")
                        Text("Viewing \(model.activeTrackLabel)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TrackerTheme.muted)
                        if model.analysisRows.isEmpty {
                            Text("Run analysis or load an export bundle to populate charts.")
                                .font(.system(size: 14))
                                .foregroundStyle(TrackerTheme.muted)
                        } else {
                            Chart(model.analysisRows) { row in
                                LineMark(x: .value("Time", row.timeSeconds), y: .value("Speed", row.speed))
                                    .foregroundStyle(TrackerTheme.accent)
                                LineMark(x: .value("Time", row.timeSeconds), y: .value("Scientific Confidence", row.scientificConfidence))
                                    .foregroundStyle(TrackerTheme.navy)
                            }
                            .frame(height: 260)
                        }
                    }
                }

            case .window:
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Window Statistics")
                        Text("Viewing \(model.activeTrackLabel)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TrackerTheme.muted)
                        HStack(spacing: 10) {
                            Button("Window Start = Current", action: setWindowStart)
                                .buttonStyle(GhostActionButtonStyle())
                            Button("Window End = Current", action: setWindowEnd)
                                .buttonStyle(GhostActionButtonStyle())
                            Button("Reset Window", action: resetWindow)
                                .buttonStyle(GhostActionButtonStyle())
                        }
                        if let window = model.windowSummary {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                PairwiseMetricTile(title: "Frame Window", value: "\(window.startFrame) → \(window.endFrame)")
                                PairwiseMetricTile(title: "Duration", value: String(format: "%.3f s", window.durationSeconds))
                                PairwiseMetricTile(title: "Displacement", value: String(format: "%.3f %@", window.displacement, model.unitLabel))
                                PairwiseMetricTile(title: "Mean Speed", value: String(format: "%.3f %@/s", window.meanSpeed, model.unitLabel))
                                PairwiseMetricTile(title: "Max Speed", value: String(format: "%.3f %@/s", window.maxSpeed, model.unitLabel))
                                PairwiseMetricTile(title: "Max Acceleration", value: String(format: "%.3f %@/s²", window.maxAcceleration, model.unitLabel))
                            }
                            Text(model.timelineMarkers.joined(separator: " | "))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(TrackerTheme.muted)
                        } else {
                            Text("Choose a wider frame window to compute regional statistics.")
                                .font(.system(size: 14))
                                .foregroundStyle(TrackerTheme.muted)
                        }
                    }
                }

            case .events:
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Event Journal")
                        if model.allEvents.isEmpty {
                            Text("No events available yet.")
                                .font(.system(size: 14))
                                .foregroundStyle(TrackerTheme.muted)
                        } else {
                            ForEach(model.allEvents) { event in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(event.name) [\(event.origin)]")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Frame \(event.frameIndex) • \(String(format: "%.3f", event.timeSeconds)) s • \(String(format: "%.3f", event.value)) \(event.unitLabel)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(TrackerTheme.muted)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(TrackerTheme.steel.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }

            case .quality:
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Quality Notes")
                        Text("Viewing \(model.activeTrackLabel)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TrackerTheme.muted)
                        StatusPill(text: model.qcBadge, tone: TrackerTheme.warning)
                        if let quality = model.qualitySnapshot {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                PairwiseMetricTile(title: "Quality Index", value: String(format: "%.3f", quality.qualityIndex ?? 0))
                                PairwiseMetricTile(title: "Calibration Confidence", value: String(format: "%.3f", quality.calibrationConfidence ?? 0))
                                PairwiseMetricTile(title: "Drift Sensitivity", value: String(format: "%.3f", quality.driftSensitivity ?? 0))
                                PairwiseMetricTile(title: "Interpolation Burden", value: String(format: "%.3f", quality.interpolatedBurdenRatio ?? 0))
                            }
                        }
                        ForEach(model.qualityNotes, id: \.self) { note in
                            Text("• \(note)")
                                .font(.system(size: 13))
                                .foregroundStyle(TrackerTheme.ink)
                        }
                        if let anomalies = model.qualitySnapshot?.anomalies, !anomalies.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Native QC Anomaly Register")
                                    .font(.system(size: 14, weight: .semibold))
                                ForEach(anomalies.prefix(6)) { anomaly in
                                    QualityAnomalyRow(anomaly: anomaly)
                                }
                            }
                        }
                        if let spanScores = model.qualitySnapshot?.spanScores, !spanScores.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Span Severity Ledger")
                                    .font(.system(size: 14, weight: .semibold))
                                ForEach(spanScores.sorted(by: { $0.severityScore > $1.severityScore }).prefix(6)) { span in
                                    QualitySpanRow(span: span)
                                }
                            }
                        }
                    }
                }

            case .pairwise:
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Pairwise Analysis")
                        if let metric = model.selectedPairwiseMetric {
                            Text("\(model.trackDisplayName(for: metric.primaryTrackID)) ↔ \(model.trackDisplayName(for: metric.secondaryTrackID))")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(TrackerTheme.ink)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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

                            Text("Distance and relative-speed traces let you validate contact timing, separation minima, and near-collision behavior directly in the native shell.")
                                .font(.system(size: 13))
                                .foregroundStyle(TrackerTheme.muted)
                        } else {
                            Text("Pairwise metrics will appear when multiple objects are tracked.")
                                .font(.system(size: 14))
                                .foregroundStyle(TrackerTheme.muted)
                        }
                    }
                }

            case .table:
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Inspection Table")
                        HStack(spacing: 12) {
                            Text("Viewing \(model.activeTrackLabel)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TrackerTheme.muted)
                            Spacer()
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
                            .frame(width: 180)
                        }
                        ResultsTableView(model: model)
                    }
                }

            case .reproduce:
                VStack(spacing: 16) {
                    TrackerPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionEyebrow(text: "Reproducibility")
                            HStack(spacing: 10) {
                                Button("Export Native Research Package", action: exportNativeResearchPackage)
                                    .buttonStyle(PrimaryActionButtonStyle())
                                Button("Run Workspace Batch", action: runWorkspaceBatch)
                                    .buttonStyle(GhostActionButtonStyle())
                            }
                            if let exportDirectory = model.exportDirectory {
                                Text("Export directory: \(exportDirectory.path)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(TrackerTheme.muted)
                            }
                            TextEditor(text: .constant(model.reproduceCommand))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .frame(minHeight: 160)
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        TrackerPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionEyebrow(text: "Export Profile")
                                Text("Overlay: \(model.includeOverlay ? "Included" : "Skipped")")
                                Text("Plots: \(model.includePlots ? "Included" : "Skipped")")
                                Text("Debug Tracking: \(model.debugTracking ? "Included" : "Skipped")")
                                Text("Template: \(model.reportTemplate.capitalized)")
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(TrackerTheme.ink)
                        }

                        TrackerPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionEyebrow(text: "Tracked Objects")
                                if model.additionalObjects.isEmpty {
                                    Text("Primary object only.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(TrackerTheme.muted)
                                } else {
                                    ForEach(model.additionalObjects) { object in
                                        Text("• \(object.name) [\(object.trackID)]")
                                            .font(.system(size: 13))
                                            .foregroundStyle(TrackerTheme.ink)
                                    }
                                }
                            }
                        }
                    }

                    if let aggregate = model.batchAggregate {
                        TrackerPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionEyebrow(text: "Batch Overview")
                                Text("Trials: \(aggregate.trialCount)")
                                Text("Mean Peak Speed: \(String(format: "%.3f", aggregate.meanPeakSpeed))")
                                Text("Mean Peak Accel: \(String(format: "%.3f", aggregate.meanPeakAcceleration))")
                                Text("Mean Scientific Confidence: \(String(format: "%.3f", aggregate.meanScientificConfidence))")
                                Text("Mean Quality Index: \(String(format: "%.3f", aggregate.meanQualityIndex))")
                                Text("Mean Event Count: \(String(format: "%.2f", aggregate.meanEventCount))")
                                if !aggregate.qcBadges.isEmpty {
                                    Text(aggregate.qcBadges.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " • "))
                                        .font(.system(size: 12))
                                        .foregroundStyle(TrackerTheme.muted)
                                }
                                if !aggregate.classifications.isEmpty {
                                    Text(aggregate.classifications.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " • "))
                                        .font(.system(size: 12))
                                        .foregroundStyle(TrackerTheme.muted)
                                }
                                if let bestQualityTrialID = aggregate.bestQualityTrialID {
                                    Text("Best Quality Trial: \(bestQualityTrialID)")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(TrackerTheme.ink)
                        }
                    }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TrackerTheme.muted)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TrackerTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(TrackerTheme.steel.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TrackerTheme.muted)
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
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(TrackerTheme.ink)
                                .frame(width: columnWidth(for: column), alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(row.frameIndex.isMultiple(of: 2) ? TrackerTheme.steel.opacity(0.20) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(anomaly.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                StatusPill(text: anomaly.severity, tone: TrackerTheme.warning)
            }
            Text(frameLabel)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(TrackerTheme.muted)
            Text(anomaly.summary)
                .font(.system(size: 12))
                .foregroundStyle(TrackerTheme.ink)
            if let recommendedAction = anomaly.recommendedAction {
                Text(recommendedAction)
                    .font(.system(size: 12))
                    .foregroundStyle(TrackerTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TrackerTheme.steel.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(span.category.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(String(format: "%.3f", span.severityScore))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(TrackerTheme.warning)
            }
            Text("Frames \(span.startFrame)-\(span.endFrame) • tracker \(String(format: "%.3f", span.averageTrackerConfidence)) • scientific \(String(format: "%.3f", span.scientificConfidenceMean))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(TrackerTheme.muted)
            Text(span.reason)
                .font(.system(size: 12))
                .foregroundStyle(TrackerTheme.ink)
            if let failure = span.dominantFailureReason {
                Text("Failure mode: \(failure)")
                    .font(.system(size: 12))
                    .foregroundStyle(TrackerTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TrackerTheme.steel.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
