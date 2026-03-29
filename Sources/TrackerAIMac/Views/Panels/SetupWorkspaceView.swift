import SwiftUI

struct SetupWorkspaceView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            TrackerPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow(text: "Experiment Setup")
                    MacFormRow(label: "Experiment") { TextField("Projectile Study", text: $model.experimentLabel) }
                    MacFormRow(label: "Trial ID") { TextField("trial-01", text: $model.trialID) }
                    MacFormRow(label: "Operator") { TextField("Operator", text: $model.operatorName) }
                    MacFormRow(label: "Tags") { TextField("comma, separated, tags", text: $model.tags) }
                    MacFormRow(label: "Notes") { TextField("Experimental notes", text: $model.notes) }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow(text: "Calibration")
                        HStack(spacing: 10) {
                            Button("Draw On Video", action: startScaleDrawing)
                                .buttonStyle(PrimaryActionButtonStyle())
                            Button("Clear", action: clearScaleLine)
                                .buttonStyle(GhostActionButtonStyle())
                        }
                        Text("Primary workflow: draw directly in the video workspace. Numeric values remain available for inspection and fine tuning.")
                            .font(.system(size: 13))
                            .foregroundStyle(TrackerTheme.muted)
                        MacFormRow(label: "Reference Length") { TextField("1.0", text: $model.referenceLength) }
                        MacFormRow(label: "Unit") { TextField("m", text: $model.unitLabel) }
                        Text("Scale line")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TrackerTheme.ink)
                        NumericGrid(scale: $model.scaleLine)
                    }
                }

                TrackerPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow(text: "Tracking")
                        HStack(spacing: 10) {
                            Button("Draw Target", action: startTargetDrawing)
                                .buttonStyle(PrimaryActionButtonStyle())
                            Button("Clear", action: clearTargetBox)
                                .buttonStyle(GhostActionButtonStyle())
                        }
                        Text("Draw the target box directly over the object in the video workspace, then use the fields below only if you want to adjust exact numbers.")
                            .font(.system(size: 13))
                            .foregroundStyle(TrackerTheme.muted)
                        MacFormRow(label: "Profile") {
                            Picker("Profile", selection: $model.trackingProfile) {
                                ForEach(TrackingProfileOption.allCases) { profile in
                                    Text(profile.title).tag(profile)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        MacFormRow(label: "Smooth Window") { TextField("7", text: $model.smoothingWindow) }
                        MacFormRow(label: "Polyorder") { TextField("2", text: $model.polyorder) }
                        MacFormRow(label: "Debug Export") {
                            Toggle("Include per-frame debug tracking", isOn: $model.debugTracking)
                                .toggleStyle(.switch)
                        }
                        Text("Target box")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TrackerTheme.ink)
                        NumericGrid(box: $model.targetBox)
                    }
                }
            }

            TrackerPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow(text: "Secondary Objects")
                    Text("Porting parity from the Python app: add extra tracked bodies for collision and multi-object experiments, now with direct-on-video authoring.")
                        .font(.system(size: 13))
                        .foregroundStyle(TrackerTheme.muted)
                    AdditionalObjectGrid(object: $model.additionalObjectDraft)
                    HStack(spacing: 10) {
                        Button("Draw Companion On Video", action: drawSecondaryObject)
                            .buttonStyle(GhostActionButtonStyle())
                        Button(model.editingAdditionalObjectID == nil ? "Save Companion" : "Update Companion", action: addSecondaryObject)
                            .buttonStyle(PrimaryActionButtonStyle())
                        Text("\(model.additionalObjects.count) configured")
                            .font(.system(size: 13))
                            .foregroundStyle(TrackerTheme.muted)
                    }

                    if !model.additionalObjects.isEmpty {
                        ForEach(model.additionalObjects) { object in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(object.name) [\(object.kind)]")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("\(object.trackID) • \(object.x), \(object.y), \(object.width), \(object.height)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(TrackerTheme.muted)
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Button("Redraw", action: { model.startAdditionalObjectDrawing(existing: object) })
                                        .buttonStyle(GhostActionButtonStyle())
                                    Button("Remove", action: { model.removeAdditionalObject(object) })
                                        .buttonStyle(GhostActionButtonStyle())
                                }
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow(text: "Export Profile")
                        Toggle("Include overlay video", isOn: $model.includeOverlay)
                            .toggleStyle(.switch)
                        Toggle("Include plot exports", isOn: $model.includePlots)
                            .toggleStyle(.switch)
                        Picker("Report Template", selection: $model.reportTemplate) {
                            Text("Research").tag("research")
                            Text("Guided").tag("guided")
                            Text("Compact").tag("compact")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                TrackerPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow(text: "Execution")
                        MacFormRow(label: "Start Frame") {
                            Stepper(value: $model.startFrame, in: 0...max(model.endFrame, 1)) {
                                Text("\(model.startFrame)")
                            }
                        }
                        MacFormRow(label: "End Frame") {
                            Stepper(value: $model.endFrame, in: model.startFrame...max(model.startFrame + 1, 100_000)) {
                                Text("\(model.endFrame)")
                            }
                        }
                        HStack(spacing: 10) {
                            Button("Run Native + Python Analysis", action: runAnalysis)
                                .buttonStyle(PrimaryActionButtonStyle())
                                .disabled(!model.canRunAnalysis)
                            Text("This shell uses the existing Python engine today while the native product layer matures.")
                                .font(.system(size: 13))
                                .foregroundStyle(TrackerTheme.muted)
                        }
                    }
                }
            }
        }
    }

    private func addSecondaryObject() {
        model.addAdditionalObject()
    }

    private func drawSecondaryObject() {
        model.startAdditionalObjectDrawing()
    }

    private func startScaleDrawing() {
        model.startScaleDrawing()
    }

    private func clearScaleLine() {
        model.clearScaleLine()
    }

    private func startTargetDrawing() {
        model.startTargetDrawing()
    }

    private func clearTargetBox() {
        model.clearTargetBox()
    }

    private func runAnalysis() {
        Task { await model.runAnalysis() }
    }
}
