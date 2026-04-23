import SwiftUI

struct SetupWorkspaceView: View {
    @Bindable var model: AppModel
    let showsHeroHeader: Bool

    @State private var expandedSections: Set<SetupInspectorSection> = [
        .experimentDetails,
        .calibration,
        .trackingTarget,
        .analysisRange
    ]
    @State private var showAdvancedCalibration = false

    init(model: AppModel, showsHeroHeader: Bool = true) {
        self.model = model
        self.showsHeroHeader = showsHeroHeader
    }

    var body: some View {
        VStack(spacing: TrackerTheme.Spacing.sm - 2) {
            TrackerPanel {
                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                    if showsHeroHeader {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                                SectionEyebrow(text: "Guided Setup")
                                Text("Prepare the clip in a clear scientific sequence.")
                                    .trackerText(.sectionTitle)
                                Text("Finish the required steps first, then expand optional and advanced controls only when the experiment calls for them.")
                                    .trackerText(.body, color: TrackerTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 16)

                            VStack(alignment: .trailing, spacing: 8) {
                                StatusPill(text: model.workflowState.title, tone: workflowTone)
                                Text(model.analysisGuardrailMessage)
                                    .trackerText(.caption, color: TrackerTheme.muted)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 220, alignment: .trailing)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        GuidedSetupSummaryBadge(title: "Required Ready", value: "\(requiredSectionCount)/4")
                        GuidedSetupSummaryBadge(title: "Optional Objects", value: "\(model.additionalObjects.count)")
                        GuidedSetupSummaryBadge(title: "Range", value: "\(selectedFrameCount) frames")
                        GuidedSetupSummaryBadge(title: "Export", value: exportSummaryShort)
                    }
                }
            }

            if model.currentVideoURL == nil {
                ImportFirstSetupEmptyState(
                    presetTitle: model.selectedPreset.title,
                    setupTip: model.selectedPreset.setupTip,
                    openVideo: openVideo
                )
            } else {
                GuidedInspectorSection(
                    title: "Experiment Details",
                    helper: "Name the trial before deeper setup so exports and saved sessions stay auditable.",
                    status: experimentStatusText,
                    tone: experimentStatusTone,
                    isExpanded: sectionBinding(.experimentDetails)
                ) {
                    InspectorFieldGroup(
                        title: "Required Fields",
                        detail: "These label the experiment and are used in saved sessions and exports."
                    ) {
                        MacFormRow(
                            label: "Experiment",
                            helper: "Required for exports",
                            validation: experimentValidation
                        ) {
                            TrackerTextField(
                                placeholder: "Projectile Study",
                                text: $model.experimentLabel,
                                fieldTone: fieldTone(for: experimentValidation)
                            )
                                .help("Customer-facing experiment name shown in exports and workspace summaries.")
                        }

                        MacFormRow(
                            label: "Trial ID",
                            helper: "Stable lab identifier",
                            validation: trialIDValidation
                        ) {
                            TrackerTextField(
                                placeholder: "trial-01",
                                text: $model.trialID,
                                fieldTone: fieldTone(for: trialIDValidation)
                            )
                                .help("Stable identifier for the current capture or run.")
                        }
                    }

                    InspectorFieldGroup(
                        title: "Optional Fields",
                        detail: "Use these when a lab wants operator context or searchable notes."
                    ) {
                        MacFormRow(label: "Operator", helper: "Optional") {
                            TrackerTextField(placeholder: "Operator", text: $model.operatorName)
                                .help("Capture who prepared or reviewed the run.")
                        }

                        MacFormRow(label: "Tags", helper: "Comma separated") {
                            TrackerTextField(placeholder: "comma, separated, tags", text: $model.tags)
                                .help("Short tags help later filtering across a workspace.")
                        }

                        MacFormRow(label: "Notes", helper: "Optional context") {
                            TrackerTextField(
                                placeholder: "Experimental notes",
                                text: $model.notes,
                                axis: .vertical,
                                lineLimit: 3,
                                width: 360
                            )
                                .help("Short notes about apparatus, context, or anomalies.")
                        }
                    }

                    InspectorFieldGroup(
                        title: "Advanced Fields",
                        detail: "Preset selection changes tracking defaults without affecting the raw clip."
                    ) {
                        MacFormRow(label: "Preset") {
                            TrackerControlSurface(width: 300) {
                                Picker("Preset", selection: $model.selectedPresetID) {
                                    ForEach(model.presets) { preset in
                                        Text(preset.title).tag(preset.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .onChange(of: model.selectedPresetID) { _, newValue in
                                if let preset = model.presets.first(where: { $0.id == newValue }) {
                                    model.applyPreset(preset)
                                }
                            }
                            .help("Starting point for tracking defaults, review focus, and report template.")
                        }

                        Text(model.selectedPreset.setupTip)
                            .trackerText(.caption, color: TrackerTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    InspectorFieldGroup(
                        title: "Destructive Actions",
                        detail: "Use sparingly when you want to strip experiment metadata and start over."
                    ) {
                        Button("Clear Experiment Details", action: clearExperimentDetails)
                            .buttonStyle(DestructiveActionButtonStyle())
                            .help("Remove the current experiment metadata but keep calibration and tracking setup.")
                    }
                }

                GuidedInspectorSection(
                    title: "Calibration",
                    helper: "Guide users through scale drawing first, then confirm scientific units before analysis.",
                    status: calibrationStatusText,
                    tone: calibrationStatusTone,
                    isExpanded: sectionBinding(.calibration)
                ) {
                    InspectorFieldGroup(
                        title: "Required Fields",
                        detail: "These three actions complete the core calibration path."
                    ) {
                        SetupSequenceRow(
                            number: 1,
                            title: "Click Draw Scale",
                            detail: drawScaleDetail,
                            tone: scaleDrawingTone
                        ) {
                            Button("Draw Scale", action: startScaleDrawing)
                                .buttonStyle(PrimaryActionButtonStyle())
                                .help("Activate scale-line drawing in the video workspace.")
                        }

                        SetupSequenceRow(
                            number: 2,
                            title: "Draw On Video",
                            detail: scaleLineDetail,
                            tone: model.isScaleReady ? .complete : .waiting
                        ) {
                            NumericGrid(scale: $model.scaleLine)
                        }

                        SetupSequenceRow(
                            number: 3,
                            title: "Confirm Length And Unit",
                            detail: calibrationFieldsDetail,
                            tone: hasCalibrationFields ? .complete : .waiting
                        ) {
                            MacFormRow(
                                label: "Reference Length",
                                helper: "Positive number",
                                validation: referenceLengthValidation
                            ) {
                                TrackerTextField(
                                    placeholder: "1.0",
                                    text: $model.referenceLength,
                                    fieldTone: fieldTone(for: referenceLengthValidation)
                                )
                                    .help("Real-world length that matches the line drawn on video.")
                            }

                            MacFormRow(
                                label: "Unit",
                                helper: "Used in exports",
                                validation: unitValidation
                            ) {
                                TrackerTextField(
                                    placeholder: "m",
                                    text: $model.unitLabel,
                                    fieldTone: fieldTone(for: unitValidation)
                                )
                                    .help("Displayed in tables, graphs, and exported reports.")
                            }
                        }

                        SetupSequenceRow(
                            number: 4,
                            title: "Success Status",
                            detail: calibrationSuccessDetail,
                            tone: calibrationSuccessTone
                        ) {
                            StatusPill(text: calibrationSuccessBadge, tone: calibrationSuccessColor)
                        }
                    }

                    InspectorFieldGroup(
                        title: "Optional Fields",
                        detail: "Reference markers help when the camera or apparatus may drift."
                    ) {
                        HStack(spacing: 10) {
                            Button("Draw Reference Marker", action: startReferenceDrawing)
                                .buttonStyle(GhostActionButtonStyle())
                                .help("Mark a stable object so the run can compensate for apparatus or camera motion.")
                            StatusPill(text: model.referenceMarkerStatus, style: model.isReferenceReady ? .complete : .neutral)
                        }

                        NumericGrid(box: $model.referenceBox)
                    }

                    InspectorFieldGroup(
                        title: "Advanced Fields",
                        detail: "Keep expert tuning separate from the default calibration path."
                    ) {
                        DisclosureGroup(isExpanded: $showAdvancedCalibration) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Advanced calibration stays available here even when the global Advanced toggle is off.")
                                    .trackerText(.caption, color: TrackerTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                AdvancedCalibrationEditor(model: model)
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Text("Show Advanced Calibration")
                                    .trackerText(.cardTitle)
                                Spacer()
                                Text(showAdvancedCalibration ? "Expanded" : "Hidden")
                                    .trackerText(.caption, color: TrackerTheme.muted)
                            }
                        }
                    }

                    InspectorFieldGroup(
                        title: "Destructive Actions",
                        detail: "Clear only the scientific geometry you want to redraw."
                    ) {
                        HStack(spacing: 10) {
                            Button("Clear Scale", action: clearScaleLine)
                                .buttonStyle(DestructiveActionButtonStyle())
                            Button("Clear Reference Marker", action: clearReferenceBox)
                                .buttonStyle(DestructiveActionButtonStyle())
                        }
                    }
                }

                GuidedInspectorSection(
                    title: "Tracking Target",
                    helper: "Confirm the target box and tracking profile before launching a full analysis run.",
                    status: trackingStatusText,
                    tone: trackingStatusTone,
                    isExpanded: sectionBinding(.trackingTarget)
                ) {
                InspectorFieldGroup(
                    title: "Required Fields",
                    detail: "This guided sequence mirrors the way new users think: draw, confirm, validate."
                ) {
                    SetupSequenceRow(
                        number: 1,
                        title: "Draw Target",
                        detail: targetDrawDetail,
                        tone: targetDrawTone
                    ) {
                        Button("Draw Target", action: startTargetDrawing)
                            .buttonStyle(PrimaryActionButtonStyle())
                            .help("Activate target-box drawing on the video stage.")
                    }

                    SetupSequenceRow(
                        number: 2,
                        title: "Confirm Profile",
                        detail: targetProfileDetail,
                        tone: model.isTargetReady ? .complete : .waiting
                    ) {
                        MacFormRow(label: "Profile") {
                            TrackerControlSurface(width: 320) {
                                Picker("Profile", selection: $model.trackingProfile) {
                                    ForEach(TrackingProfileOption.allCases) { profile in
                                        Text(profile.title).tag(profile)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .help("Choose the tracking strategy that best matches the target appearance.")
                        }
                    }

                    SetupSequenceRow(
                        number: 3,
                        title: "Run Quick Preview Validation",
                        detail: model.targetPreviewMessage,
                        tone: targetPreviewTone
                    ) {
                        HStack(spacing: 10) {
                            Button("Validate Preview", action: runTargetPreviewValidation)
                                .buttonStyle(PrimaryActionButtonStyle())
                                .disabled(model.currentVideoURL == nil)
                            StatusPill(text: model.targetPreviewStatusTitle, tone: targetPreviewColor)
                        }
                    }
                }

                InspectorFieldGroup(
                    title: "Optional Fields",
                    detail: "Use these for smoothing and recovery tuning when the default pass needs refinement."
                ) {
                    MacFormRow(label: "Smooth Window", helper: "Numeric") {
                        TrackerTextField(placeholder: "7", text: $model.smoothingWindow)
                            .help("Larger windows smooth more aggressively and may soften sharp events.")
                    }

                    MacFormRow(label: "Polyorder", helper: "Numeric") {
                        TrackerTextField(placeholder: "2", text: $model.polyorder)
                            .help("Polynomial order for the smoothing profile.")
                    }

                    MacFormRow(label: "Recovery") {
                        TrackerControlSurface(width: 300) {
                            Toggle("Use robust recovery", isOn: $model.trackingRobustRecovery)
                                .toggleStyle(.switch)
                        }
                            .help("Try recovering the target after short losses or occlusions.")
                    }

                    MacFormRow(label: "Refinement") {
                        TrackerControlSurface(width: 300) {
                            Toggle("Run bidirectional refinement", isOn: $model.trackingBidirectionalRefinement)
                                .toggleStyle(.switch)
                        }
                            .help("Refine tracks by reconciling forward and backward passes.")
                    }
                }

                InspectorFieldGroup(
                    title: "Advanced Fields",
                    detail: "Keep expert diagnostics separate from the default target path."
                ) {
                    MacFormRow(label: "Debug Export") {
                        TrackerControlSurface(width: 300) {
                            Toggle("Include per-frame debug tracking", isOn: $model.debugTracking)
                                .toggleStyle(.switch)
                        }
                            .help("Export additional tracking diagnostics for deeper inspection.")
                    }

                    Text(model.internalTrackingControlsSummary)
                        .trackerText(.caption, color: TrackerTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    NumericGrid(box: $model.targetBox)
                }

                InspectorFieldGroup(
                    title: "Destructive Actions",
                    detail: "Clear the target when you need to redraw from scratch."
                ) {
                    Button("Clear Target", action: clearTargetBox)
                        .buttonStyle(DestructiveActionButtonStyle())
                }
            }

                RunAnalysisLaunchCard(
                    model: model,
                    readinessItems: readinessItems,
                    estimatedOutput: estimatedOutputText,
                    postRunActionsText: postRunActionsText,
                    selectedFrameCount: selectedFrameCount,
                    estimatedDurationText: estimatedDurationText,
                    runAnalysis: runAnalysis,
                    cancelAnalysis: cancelAnalysis
                )

                GuidedInspectorSection(
                title: "Additional Objects",
                helper: "Use additional objects only when the experiment benefits from multi-object or pairwise analysis.",
                status: secondaryObjectsStatusText,
                tone: secondaryObjectsTone,
                isExpanded: sectionBinding(.secondaryObjects)
            ) {
                InspectorFieldGroup(
                    title: "Required Fields",
                    detail: "No required fields. Leave this collapsed for single-object experiments."
                ) {
                    ReadinessRow(title: "Primary analysis works without additional objects", complete: true)
                }

                InspectorFieldGroup(
                    title: "Optional Fields",
                    detail: "Add one or more extra tracked bodies for collisions, spacing, or relative motion."
                ) {
                    AdditionalObjectGrid(object: $model.additionalObjectDraft)

                    HStack(spacing: 10) {
                        Button("Draw Object On Video", action: drawSecondaryObject)
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(!model.canManageCompanions)
                        Button(model.editingAdditionalObjectID == nil ? "Save Object" : "Update Object", action: addSecondaryObject)
                            .buttonStyle(SuccessActionButtonStyle())
                            .disabled(!model.canManageCompanions)
                        StatusPill(text: "\(model.additionalObjects.count) saved", style: model.additionalObjects.isEmpty ? .neutral : .complete)
                    }
                }

                InspectorFieldGroup(
                    title: "Advanced Fields",
                    detail: "Keep identifiers consistent so exported pairwise metrics remain interpretable."
                ) {
                    Text("Use stable track IDs and descriptive names for additional objects. Saved objects flow into pairwise metrics and exported reports.")
                        .trackerText(.caption, color: TrackerTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                InspectorFieldGroup(
                    title: "Destructive Actions",
                    detail: "Remove only the additional-object data you no longer want in the session."
                ) {
                    Button("Clear Draft Object", action: clearAdditionalObjectDraft)
                        .buttonStyle(DestructiveActionButtonStyle())

                    if model.additionalObjects.isEmpty {
                        Text("No saved additional objects yet.")
                            .trackerText(.caption, color: TrackerTheme.muted)
                    } else {
                        ForEach(model.additionalObjects) { object in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(object.name) [\(object.kind)]")
                                        .trackerText(.cardTitle)
                                    Text("\(object.trackID) • \(object.x), \(object.y), \(object.width), \(object.height)")
                                        .trackerText(.caption, color: TrackerTheme.muted)
                                }

                                Spacer(minLength: 0)

                                HStack(spacing: 8) {
                                    Button("Redraw", action: { model.startAdditionalObjectDrawing(existing: object) })
                                        .buttonStyle(SecondaryActionButtonStyle())
                                    Button("Remove", action: { model.removeAdditionalObject(object) })
                                        .buttonStyle(DestructiveActionButtonStyle())
                                }
                            }
                        }
                    }
                }
            }

                GuidedInspectorSection(
                title: "Analysis Range",
                helper: "Trim the run to the useful frames so results export faster and stay focused on the experiment window.",
                status: analysisRangeStatusText,
                tone: analysisRangeTone,
                isExpanded: sectionBinding(.analysisRange)
            ) {
                InspectorFieldGroup(
                    title: "Required Fields",
                    detail: "These bounds define what analysis will process."
                ) {
                    MacFormRow(label: "Start Frame", validation: startFrameValidation) {
                        HStack(spacing: 10) {
                            TrackerControlSurface(tone: fieldTone(for: startFrameValidation), width: 170) {
                                Stepper(value: $model.startFrame, in: 0...max(model.endFrame, 1)) {
                                    Text("\(model.startFrame)")
                                }
                            }
                            .disabled(!model.canUseFrameRangeControls)

                            Button("Use Current", action: useCurrentFrameAsStart)
                                .buttonStyle(TertiaryActionButtonStyle())
                                .disabled(!model.canUseFrameRangeControls)
                        }
                    }

                    MacFormRow(label: "End Frame", validation: endFrameValidation) {
                        HStack(spacing: 10) {
                            TrackerControlSurface(tone: fieldTone(for: endFrameValidation), width: 170) {
                                Stepper(value: $model.endFrame, in: model.startFrame...max(model.startFrame + 1, 100_000)) {
                                    Text("\(model.endFrame)")
                                }
                            }
                            .disabled(!model.canUseFrameRangeControls)

                            Button("Use Current", action: useCurrentFrameAsEnd)
                                .buttonStyle(TertiaryActionButtonStyle())
                                .disabled(!model.canUseFrameRangeControls)
                        }
                    }
                }

                InspectorFieldGroup(
                    title: "Optional Fields",
                    detail: "Quick summaries help the operator confirm the intended analysis window."
                ) {
                    ReadinessRow(title: "Clip loaded", complete: model.currentVideoURL != nil)
                    ReadinessRow(title: "Frame range valid", complete: model.endFrame >= model.startFrame)
                    ReadinessRow(title: "Current selection covers \(selectedFrameCount) frames", complete: model.currentVideoURL != nil)
                }

                InspectorFieldGroup(
                    title: "Advanced Fields",
                    detail: "Use this readout to estimate runtime and data volume before launching analysis."
                ) {
                    Text("Approximate duration: \(estimatedDurationText)")
                        .trackerText(.caption)
                    Text("The launch card below estimates what will be exported from this frame window.")
                        .trackerText(.caption, color: TrackerTheme.muted)
                }

                InspectorFieldGroup(
                    title: "Destructive Actions",
                    detail: "Reset the run window back to the full clip bounds."
                ) {
                    Button("Use Full Clip", action: resetAnalysisRange)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(model.currentVideoURL == nil)
                }
            }

                GuidedInspectorSection(
                title: "Export Preferences",
                helper: "Configure outputs here, separate from calibration and target setup, so launch decisions stay clearer.",
                status: exportStatusText,
                tone: exportStatusTone,
                isExpanded: sectionBinding(.exportPreferences)
            ) {
                InspectorFieldGroup(
                    title: "Required Fields",
                    detail: "Choose the report profile so results open with the right level of detail."
                ) {
                    MacFormRow(label: "Report Template") {
                        TrackerControlSurface(width: 320) {
                            Picker("Report Template", selection: $model.reportTemplate) {
                                Text("Research").tag("research")
                                Text("Guided").tag("guided")
                                Text("Compact").tag("compact")
                            }
                            .pickerStyle(.segmented)
                        }
                        .help("Controls report density and presentation style in exported results.")
                    }
                }

                InspectorFieldGroup(
                    title: "Optional Fields",
                    detail: "Add media and plot outputs when they help instruction, review, or publication."
                ) {
                    TrackerControlSurface(width: 320) {
                        Toggle("Include overlay video", isOn: $model.includeOverlay)
                            .toggleStyle(.switch)
                    }
                        .help("Export a visual overlay of the tracked result.")
                    TrackerControlSurface(width: 320) {
                        Toggle("Include plot exports", isOn: $model.includePlots)
                            .toggleStyle(.switch)
                    }
                        .help("Include graph images alongside the CSV and report package.")
                }

                InspectorFieldGroup(
                    title: "Advanced Fields",
                    detail: "Use the estimate below to understand what the export will contain."
                ) {
                    Text(estimatedOutputText)
                        .trackerText(.caption, color: TrackerTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                InspectorFieldGroup(
                    title: "Destructive Actions",
                    detail: "Reset export preferences to the product defaults."
                ) {
                    Button("Reset Export Preferences", action: resetExportPreferences)
                        .buttonStyle(DestructiveActionButtonStyle())
                }
            }

            }
        }
    }

    private var workflowTone: Color {
        switch model.workflowState {
        case .import: return TrackerTheme.muted
        case .calibrate: return TrackerTheme.warning
        case .track: return TrackerTheme.navy
        case .review: return TrackerTheme.accent
        case .export: return TrackerTheme.success
        }
    }

    private var requiredSectionCount: Int {
        [
            hasExperimentDetails,
            isCalibrationReady,
            model.isTargetReady,
            model.currentVideoURL != nil
        ].filter { $0 }.count
    }

    private var hasExperimentDetails: Bool {
        !model.experimentLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trialID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var experimentValidation: TrackerValidationMessage? {
        if model.experimentLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TrackerValidationMessage(text: "Add an experiment name for exports and saved sessions.", tone: .warning)
        }
        return TrackerValidationMessage(text: "Experiment name is ready for exported workspace artifacts.", tone: .success)
    }

    private var trialIDValidation: TrackerValidationMessage? {
        if model.trialID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TrackerValidationMessage(text: "Trial ID is required for reproducible lab records.", tone: .warning)
        }
        return TrackerValidationMessage(text: "Trial identifier will be preserved in reports and CSV exports.", tone: .success)
    }

    private var hasCalibrationFields: Bool {
        !model.referenceLength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.unitLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var referenceLengthValidation: TrackerValidationMessage? {
        let trimmed = model.referenceLength.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TrackerValidationMessage(text: "Enter the real-world length that matches the scale line.", tone: .warning)
        }
        guard let value = Double(trimmed), value > 0 else {
            return TrackerValidationMessage(text: "Reference length must be a positive number.", tone: .error)
        }
        return TrackerValidationMessage(text: "Scale conversion is ready to calculate physical units.", tone: .success)
    }

    private var unitValidation: TrackerValidationMessage? {
        if model.unitLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TrackerValidationMessage(text: "Add a scientific unit so tables and graphs are readable.", tone: .warning)
        }
        return TrackerValidationMessage(text: "Unit label is ready for graphs, CSV, and reports.", tone: .success)
    }

    private var isCalibrationReady: Bool {
        model.isScaleReady && hasCalibrationFields && model.calibrationValidationMessage == nil
    }

    private var selectedFrameCount: Int {
        guard model.hasValidFrameRange else { return 0 }
        return max(model.endFrame - model.startFrame + 1, 0)
    }

    private var startFrameValidation: TrackerValidationMessage? {
        if model.currentVideoURL == nil {
            return TrackerValidationMessage(text: "Load a clip before setting the analysis window.", tone: .neutral)
        }
        return TrackerValidationMessage(text: "Start frame anchors the analysis window.", tone: .success)
    }

    private var endFrameValidation: TrackerValidationMessage? {
        if model.currentVideoURL == nil {
            return TrackerValidationMessage(text: "Load a clip before setting the analysis window.", tone: .neutral)
        }
        if model.endFrame < model.startFrame {
            return TrackerValidationMessage(text: "End frame must be greater than or equal to start frame.", tone: .error)
        }
        return TrackerValidationMessage(text: "Current selection spans \(selectedFrameCount) frame(s).", tone: .success)
    }

    private var estimatedDurationText: String {
        guard model.hasValidFrameRange else { return "Awaiting clip" }
        let seconds = Double(selectedFrameCount) / max(model.playbackFPS, 1)
        return String(format: "%.2f s", seconds)
    }

    private var exportSummaryShort: String {
        let template = model.reportTemplate.capitalized
        if model.includeOverlay && model.includePlots {
            return "\(template) + media"
        }
        if model.includeOverlay || model.includePlots {
            return "\(template) + extras"
        }
        return template
    }

    private var estimatedOutputText: String {
        guard model.currentVideoURL != nil else {
            return "Import a clip to estimate CSV rows, report output, and media exports."
        }
        let trackCount = max(model.additionalObjects.count + 1, 1)
        var outputs = ["CSV table", "\(trackCount) tracked object set", "\(selectedFrameCount) analyzed frames", "\(model.reportTemplate.capitalized) report"]
        if model.includePlots {
            outputs.append("plot exports")
        }
        if model.includeOverlay {
            outputs.append("overlay video")
        }
        return outputs.joined(separator: " • ")
    }

    private var readinessItems: [LaunchReadinessItem] {
        [
            LaunchReadinessItem(title: "Clip loaded", detail: "A video is active in the workspace.", complete: model.currentVideoURL != nil),
            LaunchReadinessItem(title: "Calibration ready", detail: "Scale line, length, and unit are confirmed.", complete: isCalibrationReady),
            LaunchReadinessItem(title: "Target ready", detail: "Primary tracking box is saved on the clip.", complete: model.isTargetReady),
            LaunchReadinessItem(title: "Range selected", detail: model.hasValidFrameRange ? "\(selectedFrameCount) frames will be analyzed." : "Choose a valid frame range for the active clip.", complete: model.hasValidFrameRange)
        ]
    }

    private var postRunActionsText: String {
        if model.engineState == .running {
            return "Stay on this card to monitor progress or cancel the current run."
        }
        if model.hasActiveAnalysisResults {
            return "Open Review to inspect quality, then move to Results or export your outputs."
        }
        return "When the run finishes, review quality notes, inspect graphs, and export the CSV package."
    }

    private var experimentStatusText: String {
        hasExperimentDetails ? "Ready for saved sessions and exports" : "Add experiment name and trial ID"
    }

    private var experimentStatusTone: Color {
        hasExperimentDetails ? TrackerTheme.success : TrackerTheme.warning
    }

    private var drawScaleDetail: String {
        if model.annotationMode == .scale {
            return "Drawing is active in the video workspace."
        }
        return "Activate scale drawing on the video canvas."
    }

    private var scaleDrawingTone: SetupStepTone {
        model.annotationMode == .scale ? .active : .waiting
    }

    private var scaleLineDetail: String {
        model.isScaleReady ? "Scale geometry saved on the clip." : "Draw the reference line directly on the video."
    }

    private var calibrationFieldsDetail: String {
        hasCalibrationFields ? "Length and unit are confirmed." : "Fill in the real-world length and unit."
    }

    private var calibrationSuccessBadge: String {
        isCalibrationReady ? "Calibrated" : "Waiting"
    }

    private var calibrationSuccessDetail: String {
        if let message = model.calibrationValidationMessage {
            return message
        }
        return isCalibrationReady
            ? "The clip is ready for tracking in \(model.unitLabel)."
            : "Complete the scale line and scientific unit before analysis."
    }

    private var calibrationSuccessTone: SetupStepTone {
        if model.calibrationValidationMessage != nil {
            return .warning
        }
        return isCalibrationReady ? .complete : .waiting
    }

    private var calibrationSuccessColor: Color {
        if model.calibrationValidationMessage != nil {
            return TrackerTheme.warning
        }
        return isCalibrationReady ? TrackerTheme.success : TrackerTheme.muted
    }

    private var calibrationStatusText: String {
        isCalibrationReady ? "Scale and units confirmed" : "Draw the scale and confirm units"
    }

    private var calibrationStatusTone: Color {
        isCalibrationReady ? TrackerTheme.success : TrackerTheme.warning
    }

    private func fieldTone(for validation: TrackerValidationMessage?) -> TrackerFieldTone {
        switch validation?.tone {
        case .success:
            return .success
        case .warning:
            return .warning
        case .error:
            return .error
        case .neutral, .none:
            return .normal
        }
    }

    private var targetDrawDetail: String {
        if model.annotationMode == .target {
            return "Drawing is active in the video workspace."
        }
        return model.isTargetReady ? "Target geometry is captured." : "Draw the primary object directly on the clip."
    }

    private var targetDrawTone: SetupStepTone {
        if model.annotationMode == .target {
            return .active
        }
        return model.isTargetReady ? .complete : .waiting
    }

    private var targetProfileDetail: String {
        model.isTargetReady ? "\(model.trackingProfile.title) profile selected." : "Select a profile after drawing the target."
    }

    private var targetPreviewTone: SetupStepTone {
        switch model.targetPreviewStatus {
        case .idle: return .waiting
        case .passed: return .complete
        case .warning: return .warning
        case .failed: return .warning
        }
    }

    private var targetPreviewColor: Color {
        switch model.targetPreviewStatus {
        case .idle: return TrackerTheme.muted
        case .passed: return TrackerTheme.success
        case .warning: return TrackerTheme.warning
        case .failed: return TrackerTheme.critical
        }
    }

    private var trackingStatusText: String {
        if model.targetPreviewStatus == .passed {
            return "Target validated and ready to run"
        }
        if model.isTargetReady {
            return "Target saved, preview check recommended"
        }
        return "Draw the primary target on the clip"
    }

    private var trackingStatusTone: Color {
        if model.targetPreviewStatus == .passed {
            return TrackerTheme.success
        }
        return model.isTargetReady ? TrackerTheme.warning : TrackerTheme.warning
    }

    private var secondaryObjectsStatusText: String {
        model.additionalObjects.isEmpty ? "Optional for single-object studies" : "\(model.additionalObjects.count) additional object(s) configured"
    }

    private var secondaryObjectsTone: Color {
        model.additionalObjects.isEmpty ? TrackerTheme.muted : TrackerTheme.success
    }

    private var analysisRangeStatusText: String {
        model.currentVideoURL == nil ? "Load a clip to define the range" : (model.hasValidFrameRange ? "\(selectedFrameCount) frames selected" : "Choose a valid frame range")
    }

    private var analysisRangeTone: Color {
        model.currentVideoURL == nil ? TrackerTheme.warning : (model.hasValidFrameRange ? TrackerTheme.success : TrackerTheme.warning)
    }

    private var exportStatusText: String {
        "\(model.reportTemplate.capitalized) profile with \(model.includePlots ? "plots" : "no plots") and \(model.includeOverlay ? "overlay" : "no overlay")"
    }

    private var exportStatusTone: Color {
        TrackerTheme.navy
    }

    private func sectionBinding(_ section: SetupInspectorSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }

    private func clearExperimentDetails() {
        model.experimentLabel = ""
        model.trialID = ""
        model.operatorName = ""
        model.tags = ""
        model.notes = ""
        model.statusMessage = "Cleared experiment details."
    }

    private func clearAdditionalObjectDraft() {
        model.additionalObjectDraft = AdditionalObjectDraft()
        model.editingAdditionalObjectID = nil
        model.statusMessage = "Cleared the additional-object draft."
    }

    private func resetAnalysisRange() {
        let lastFrame = max((model.sourceVideoMetadata?.frameCount ?? (model.endFrame + 1)) - 1, 0)
        model.startFrame = 0
        model.endFrame = lastFrame
        model.currentFrame = min(max(model.currentFrame, model.startFrame), model.endFrame)
        model.selectedWindowStart = model.startFrame
        model.selectedWindowEnd = model.endFrame
        model.statusMessage = "Reset analysis range to the full clip."
        model.selectionMessage = "The full clip is selected for analysis."
    }

    private func resetExportPreferences() {
        model.includeOverlay = true
        model.includePlots = true
        model.reportTemplate = "research"
        model.statusMessage = "Reset export preferences to the default research profile."
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

    private func startReferenceDrawing() {
        model.startReferenceDrawing()
    }

    private func runTargetPreviewValidation() {
        model.runTargetPreviewValidation()
    }

    private func clearTargetBox() {
        model.clearTargetBox()
    }

    private func clearReferenceBox() {
        model.clearReferenceBox()
    }

    private func runAnalysis() {
        Task { await model.runAnalysis() }
    }

    private func openVideo() {
        model.openVideo()
    }

    private func cancelAnalysis() {
        model.cancelAnalysis()
    }

    private func useCurrentFrameAsStart() {
        model.setStartFrameToCurrentFrame()
    }

    private func useCurrentFrameAsEnd() {
        model.setEndFrameToCurrentFrame()
    }
}

private enum SetupInspectorSection: CaseIterable, Hashable {
    case experimentDetails
    case calibration
    case trackingTarget
    case secondaryObjects
    case analysisRange
    case exportPreferences
}

private enum SetupStepTone {
    case waiting
    case active
    case complete
    case warning

    var color: Color {
        switch self {
        case .waiting: return TrackerTheme.panelStroke
        case .active: return TrackerTheme.navy
        case .complete: return TrackerTheme.success
        case .warning: return TrackerTheme.warning
        }
    }

    var label: String {
        switch self {
        case .waiting: return "Waiting"
        case .active: return "Active"
        case .complete: return "Complete"
        case .warning: return "Review"
        }
    }
}

private struct LaunchReadinessItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let complete: Bool
}

private struct GuidedSetupSummaryBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .trackerText(.monoCaption, color: TrackerTheme.tertiaryText)
            Text(value)
                .trackerText(.cardTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TrackerTheme.Spacing.xs)
        .padding(.vertical, TrackerTheme.Spacing.xxs + 2)
        .background(Color.white.opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .stroke(TrackerTheme.panelStroke.opacity(0.75), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }
}

private struct ImportFirstSetupEmptyState: View {
    let presetTitle: String
    let setupTip: String
    let openVideo: () -> Void

    var body: some View {
        HeroPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.sm) {
                SectionEyebrow(text: "Import First")
                Text("Load a clip before calibration, tracking, review, and export.")
                    .trackerText(.metric, color: .white)
                Text("Tracker AI works best as a guided sequence. Start with a video, then the setup inspector will unlock the scientific controls in order.")
                    .trackerText(.body, color: Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: TrackerTheme.Spacing.xs) {
                    Button("Open Video", action: openVideo)
                        .buttonStyle(PrimaryActionButtonStyle())
                    StatusPill(text: "Preset \(presetTitle)", style: .inverse)
                }

                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxs) {
                    Text("What unlocks next")
                        .trackerText(.cardTitle, color: .white)
                    Text("1. Draw the calibration scale\n2. Confirm the target\n3. Set the frame range\n4. Run analysis and review results")
                        .trackerText(.body, color: Color.white.opacity(0.8))
                    Text(setupTip)
                        .trackerText(.caption, color: Color.white.opacity(0.72))
                }
            }
        }
    }
}

private struct GuidedInspectorSection<Content: View>: View {
    let title: String
    let helper: String
    let status: String
    let tone: Color
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        TrackerPanel {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.sm - 2) {
                    Divider()
                        .padding(.top, 4)
                    content
                }
                .padding(.top, 6)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .trackerText(.sectionTitle)
                        Text(helper)
                            .trackerText(.body, color: TrackerTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    StatusPill(text: status, tone: tone)
                }
            }
        }
    }
}

private struct InspectorFieldGroup<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxs + 2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .trackerText(.eyebrow)
                Text(detail)
                    .trackerText(.caption, color: TrackerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxs + 2) {
                content
            }
            .padding(TrackerTheme.Spacing.sm - 2)
            .background(Color.white.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous)
                    .stroke(TrackerTheme.panelStroke.opacity(0.7), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
        }
    }
}

private struct SetupSequenceRow<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    let tone: SetupStepTone
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text("\(number)")
                    .trackerText(.caption, color: tone.color)
                    .frame(width: 28, height: 28)
                    .background(tone.color.opacity(0.12))
                    .clipShape(Circle())
                Rectangle()
                    .fill(tone.color.opacity(0.18))
                    .frame(width: 2)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(title)
                        .trackerText(.cardTitle)
                    Spacer(minLength: 8)
                    StatusPill(text: tone.label, tone: tone.color)
                }

                Text(detail)
                    .trackerText(.caption, color: TrackerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                content
            }
        }
    }
}

private struct RunAnalysisLaunchCard: View {
    @Bindable var model: AppModel
    let readinessItems: [LaunchReadinessItem]
    let estimatedOutput: String
    let postRunActionsText: String
    let selectedFrameCount: Int
    let estimatedDurationText: String
    let runAnalysis: () -> Void
    let cancelAnalysis: () -> Void

    var body: some View {
        HeroPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrow(text: "Run Analysis")
                        Text("Launch analysis from one dedicated control surface.")
                            .trackerText(.metric, color: .white)
                        Text("Readiness, output estimates, progress, cancellation, and next actions all live here so the setup inspector stays focused.")
                            .trackerText(.body, color: Color.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    StatusPill(text: model.engineState.rawValue, style: .inverse)
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Readiness Summary")
                            .trackerText(.cardTitle, color: .white)
                        ForEach(readinessItems) { item in
                            LaunchReadinessRow(item: item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Estimated Output")
                            .trackerText(.cardTitle, color: .white)
                        Text(estimatedOutput)
                            .trackerText(.body, color: Color.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Approx. \(selectedFrameCount) frames • \(estimatedDurationText)")
                            .trackerText(.caption, color: Color.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Progress State")
                        .trackerText(.cardTitle, color: .white)
                    Text(model.statusMessage)
                        .trackerText(.body, color: Color.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: model.engineState == .running ? model.analysisProgressFraction : (model.hasAnalysisResults ? 1 : 0))
                        .progressViewStyle(.linear)
                        .tint(.white)
                }

                HStack(spacing: 10) {
                    Button("Run Analysis", action: runAnalysis)
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(!model.canRunAnalysis || model.engineState == .running)
                    Button("Cancel Run", action: cancelAnalysis)
                        .buttonStyle(DestructiveActionButtonStyle())
                        .disabled(!model.canCancelAnalysis)
                    Spacer(minLength: 0)
                    Text(model.analysisGuardrailMessage)
                        .trackerText(.caption, color: Color.white.opacity(0.75))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 260, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Post-Run Next Actions")
                        .trackerText(.cardTitle, color: .white)
                    Text(postRunActionsText)
                        .trackerText(.body, color: Color.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button("Open Review") {
                            model.selectedTab = .review
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(!model.canJumpToReview)

                        Button("Open Results") {
                            model.selectedTab = .results
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(!model.canJumpToResults)

                        Button("Export Results") {
                            model.exportNativeResearchPackage()
                        }
                        .buttonStyle(SuccessActionButtonStyle())
                        .disabled(!model.canExportResearchPackage)
                    }
                }
            }
        }
    }
}

private struct LaunchReadinessRow: View {
    let item: LaunchReadinessItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.complete ? Color.white : Color.white.opacity(0.32))
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .trackerText(.cardTitle, color: .white)
                Text(item.detail)
                    .trackerText(.caption, color: Color.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(item.complete ? "Ready" : "Waiting")
                .trackerText(.eyebrow, color: Color.white.opacity(item.complete ? 0.95 : 0.68))
        }
    }
}

private struct AdvancedCalibrationEditor: View {
    @Bindable var model: AppModel

    private let calibrationModes = [
        ("Single line", "single_line"),
        ("Axis aligned", "two_axis"),
        ("Marker size", "marker_size"),
        ("Homography preset", "homography"),
    ]

    private var mode: String {
        CalibrationProfile.normalizedMode(model.calibrationMode)
    }

    private var pixelDistanceLabel: String {
        mode == "marker_size" ? "Marker Size px" : "Pixel Distance px"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacFormRow(label: "Mode") {
                TrackerControlSurface(width: 300) {
                    Picker("Calibration Mode", selection: $model.calibrationMode) {
                        ForEach(calibrationModes, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if mode == "single_line" || mode == "two_axis" || mode == "homography" {
                MacFormRow(label: "Origin X") {
                    TrackerTextField(placeholder: "0", text: $model.calibrationOriginXInput)
                }
                MacFormRow(label: "Origin Y") {
                    TrackerTextField(placeholder: "0", text: $model.calibrationOriginYInput)
                }
            }

            if mode == "single_line" || mode == "two_axis" {
                MacFormRow(label: "Axis Angle") {
                    TrackerTextField(placeholder: "0", text: $model.calibrationAxisAngleInput)
                }
                MacFormRow(label: "Invert Axes") {
                    TrackerControlSurface(width: 320) {
                        HStack(spacing: 12) {
                            Toggle("Invert X", isOn: $model.calibrationInvertX)
                                .toggleStyle(.switch)
                            Toggle("Invert Y", isOn: $model.calibrationInvertY)
                                .toggleStyle(.switch)
                        }
                    }
                }
            }

            if mode == "marker_size" || mode == "homography" {
                MacFormRow(label: pixelDistanceLabel) {
                    TrackerTextField(placeholder: "20", text: $model.calibrationPixelDistanceInput)
                }
            }

            MacFormRow(label: "Preset Name") {
                TrackerTextField(placeholder: "checkerboard", text: $model.calibrationPresetName)
            }

            if mode == "homography" {
                MacFormRow(
                    label: "Homography",
                    validation: model.calibrationValidationMessage.map {
                        TrackerValidationMessage(text: $0, tone: .warning)
                    }
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        TrackerTextField(
                            placeholder: "1 0 0 0 1 0 0 0 1",
                            text: $model.calibrationHomographyInput,
                            axis: .vertical,
                            lineLimit: 3,
                            fieldTone: model.calibrationValidationMessage == nil ? .normal : .warning,
                            width: 360
                        )
                        Text("Enter 9 numbers in row-major order. Spaces or commas are both accepted.")
                            .trackerText(.caption, color: TrackerTheme.muted)
                    }
                }
            }
        }
    }
}
