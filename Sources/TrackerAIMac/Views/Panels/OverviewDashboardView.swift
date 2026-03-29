import SwiftUI

struct OverviewDashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            HeroPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Research Mission Control")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("This native shell follows the Figma redesign direction and keeps setup, review, and commercialization planning in one place.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.86))
                    Text(model.currentTrialContext)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.86))
                }
            }

            HStack(alignment: .top, spacing: 16) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Experiment Presets")
                        Picker("Preset", selection: $model.selectedPresetID) {
                            ForEach(model.presets) { preset in
                                Text(preset.title).tag(preset.id)
                            }
                        }
                        .pickerStyle(.menu)
                        Text(model.selectedPreset.description)
                            .font(.system(size: 14))
                            .foregroundStyle(TrackerTheme.muted)
                        Button("Apply Preset", action: applyPreset)
                            .buttonStyle(PrimaryActionButtonStyle())
                    }
                }

                TrackerPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Readiness Board")
                        ReadinessRow(title: "Video Import", complete: model.currentVideoURL != nil)
                        ReadinessRow(title: "Frame Range", complete: model.endFrame >= model.startFrame)
                        ReadinessRow(title: "Calibration", complete: model.isScaleReady)
                        ReadinessRow(title: "Target Box", complete: model.isTargetReady)
                        ReadinessRow(title: "Reference Marker (Optional)", complete: model.isReferenceReady)
                        ReadinessRow(title: "Analysis", complete: !model.analysisRows.isEmpty)
                        ReadinessRow(title: "Event Journal", complete: !model.manualEvents.isEmpty)
                        ReadinessRow(title: "Derived Events", complete: !model.derivedEvents.isEmpty)
                        ReadinessRow(title: "Secondary Objects", complete: !model.additionalObjects.isEmpty)
                        Button("Run Workspace Batch") {
                            Task {
                                await model.runWorkspaceBatchAnalysis()
                            }
                        }
                        .buttonStyle(GhostActionButtonStyle())
                    }
                }
            }

            TrackerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionEyebrow(text: "Protocol Notes")
                    Text(model.selectedPreset.reviewFocus)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TrackerTheme.ink)
                    Text(model.selectedPreset.setupTip)
                        .font(.system(size: 14))
                        .foregroundStyle(TrackerTheme.muted)
                    if let classification = model.summarySnapshot?.classification {
                        Text("Native classifier: \(classification.title) (\(String(format: "%.2f", classification.confidence)))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TrackerTheme.ink)
                    }
                    ForEach(model.qualityNotes, id: \.self) { note in
                        Text("• \(note)")
                            .font(.system(size: 13))
                            .foregroundStyle(TrackerTheme.ink)
                    }
                    if let aggregate = model.batchAggregate {
                        Divider()
                        Text("Batch mean quality index: \(String(format: "%.3f", aggregate.meanQualityIndex))")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Classification spread: \(aggregate.classifications.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " • "))")
                            .font(.system(size: 12))
                            .foregroundStyle(TrackerTheme.muted)
                    }
                }
            }
        }
    }

    private func applyPreset() {
        model.applyPreset(model.selectedPreset)
    }
}
