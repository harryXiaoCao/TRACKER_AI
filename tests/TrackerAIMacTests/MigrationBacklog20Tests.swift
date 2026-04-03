import Foundation
import XCTest
@testable import TrackerAIMac

final class MigrationBacklog20Tests: XCTestCase {
    func testSessionAndWorkspaceSerializationMatchGoldenFixtures() throws {
        let bridge = PythonEngineBridge()
        let directory = makeTemporaryDirectory()

        let sessionURL = directory.appendingPathComponent("session.json")
        try bridge.saveSession(makeGoldenSessionSnapshot(), to: sessionURL)
        let sessionText = try String(contentsOf: sessionURL, encoding: .utf8)
        try assertFixtureTextMatches(
            actual: sessionText,
            fixtureName: "golden_session_snapshot.json",
            canonicalizer: { try self.canonicalJSONText($0) }
        )

        let loadedSession = try bridge.loadSession(from: sessionURL)
        XCTAssertEqual(loadedSession.videoPath, "/tmp/golden-video.mp4")
        XCTAssertEqual(loadedSession.selectedStartFrame, 3)
        XCTAssertEqual(loadedSession.selectedEndFrame, 18)
        XCTAssertEqual(loadedSession.additionalObjects?.map(\.trackID), ["secondary_1"])

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        try bridge.saveWorkspace(makeGoldenWorkspaceSnapshot(), to: workspaceURL)
        let workspaceText = try String(contentsOf: workspaceURL, encoding: .utf8)
        try assertFixtureTextMatches(
            actual: workspaceText,
            fixtureName: "golden_workspace_snapshot.json",
            canonicalizer: { try self.canonicalJSONText($0) }
        )

        let loadedWorkspace = try bridge.loadWorkspace(from: workspaceURL)
        XCTAssertEqual(loadedWorkspace.title, "Golden Workspace")
        XCTAssertEqual(loadedWorkspace.activeVideoPath, "/tmp/golden-video.mp4")
        XCTAssertEqual(loadedWorkspace.items.count, 2)
    }

    func testNativeResearchExportMatchesGoldenArtifacts() throws {
        let directory = makeTemporaryDirectory()
        let exporter = NativeResearchBundleExporter()
        let payload = makeGoldenBundlePayload(outputDirectory: directory)

        _ = try exporter.export(payload)

        let analysisText = try String(
            contentsOf: directory.appendingPathComponent("analysis.csv"),
            encoding: .utf8
        )
        try assertFixtureTextMatches(
            actual: analysisText,
            fixtureName: "golden_native_analysis.csv",
            canonicalizer: { try self.canonicalPlainText($0) }
        )

        let summaryText = try String(
            contentsOf: directory.appendingPathComponent("summary.json"),
            encoding: .utf8
        )
        try assertFixtureTextMatches(
            actual: summaryText,
            fixtureName: "golden_native_summary.json",
            canonicalizer: { try self.canonicalJSONText($0) }
        )

        let reportText = try String(
            contentsOf: directory.appendingPathComponent("report.md"),
            encoding: .utf8
        )
        try assertFixtureTextMatches(
            actual: reportText,
            fixtureName: "golden_native_report.md",
            canonicalizer: { try self.canonicalPlainText($0) }
        )
    }

    func testSwiftSerializationMatchesPythonCompatibilityBridge() throws {
        let bridge = PythonEngineBridge()
        let directory = makeTemporaryDirectory()
        let swiftSessionURL = directory.appendingPathComponent("swift_session.json")
        let pythonSessionURL = directory.appendingPathComponent("python_session.json")
        let pythonNormalizedSessionURL = directory.appendingPathComponent("python_session_normalized.json")
        let swiftWorkspaceURL = directory.appendingPathComponent("swift_workspace.json")
        let pythonWorkspaceURL = directory.appendingPathComponent("python_workspace.json")
        let pythonNormalizedWorkspaceURL = directory.appendingPathComponent("python_workspace_normalized.json")

        try bridge.saveSession(makeGoldenSessionSnapshot(), to: swiftSessionURL)
        try bridge.saveWorkspace(makeGoldenWorkspaceSnapshot(), to: swiftWorkspaceURL)

        try runPythonSerializationComparison(
            sessionOutputURL: pythonSessionURL,
            workspaceOutputURL: pythonWorkspaceURL
        )

        let normalizedSession = try bridge.loadSession(from: pythonSessionURL)
        try bridge.saveSession(normalizedSession, to: pythonNormalizedSessionURL)
        XCTAssertEqual(
            try canonicalJSONText(contentsOf: swiftSessionURL),
            try canonicalJSONText(contentsOf: pythonNormalizedSessionURL)
        )

        let normalizedWorkspace = try bridge.loadWorkspace(from: pythonWorkspaceURL)
        try bridge.saveWorkspace(normalizedWorkspace, to: pythonNormalizedWorkspaceURL)
        XCTAssertEqual(
            try canonicalJSONText(contentsOf: swiftWorkspaceURL),
            try canonicalJSONText(contentsOf: pythonNormalizedWorkspaceURL)
        )
    }

    func testNativeScientificProcessorMatchesLivePythonAnalysis() throws {
        let processor = NativeScientificProcessor()
        let calibration = try CalibrationProfile(
            referenceLength: 2.0,
            unitLabel: "m",
            pixelDistance: 40.0,
            mode: "single_line",
            originXPx: 10.0,
            originYPx: 20.0,
            axisAngleDeg: 0.0,
            invertX: false,
            invertY: false,
            presetName: "golden"
        )
        let config = AnalysisConfigSnapshot(smoothingWindow: 5, smoothingPolyorder: 2)
        let observations = makePythonComparisonObservations()

        let swiftRows = processor.process(
            observations: observations.map(\.nativeObservation),
            calibration: calibration,
            config: config
        )
        let pythonRows = try runPythonAnalysisComparison(
            observations: observations,
            calibration: PythonAnalysisCalibration(
                referenceLength: calibration.referenceLength,
                unitLabel: calibration.unitLabel,
                pixelDistance: calibration.pixelDistance,
                originXPx: calibration.originXPx,
                originYPx: calibration.originYPx
            ),
            config: PythonAnalysisConfig(
                smoothingWindow: config.smoothingWindow,
                smoothingPolyorder: config.smoothingPolyorder
            )
        )

        XCTAssertEqual(swiftRows.count, pythonRows.count)
        for (swift, python) in zip(swiftRows, pythonRows) {
            XCTAssertEqual(swift.frameIndex, python.frameIndex)
            XCTAssertEqual(swift.timeSeconds, python.timeSeconds, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.xPixels), python.xPixels, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.yPixels), python.yPixels, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.rawXUnits), python.rawXUnits, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.rawYUnits), python.rawYUnits, accuracy: 1e-9)
            XCTAssertEqual(swift.xUnits, python.xUnits, accuracy: 1e-9)
            XCTAssertEqual(swift.yUnits, python.yUnits, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.xVelocity), python.xVelocity, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.yVelocity), python.yVelocity, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.xAcceleration), python.xAcceleration, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.yAcceleration), python.yAcceleration, accuracy: 1e-9)
            XCTAssertEqual(swift.speed, python.speed, accuracy: 1e-9)
            XCTAssertEqual(swift.accelerationMagnitude, python.accelerationMagnitude, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.angleDegrees), python.angleDegrees, accuracy: 1e-9)
            XCTAssertEqual(swift.trackerConfidence, python.confidence, accuracy: 1e-9)
            XCTAssertEqual(swift.scientificConfidence, python.scientificConfidence, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.positionUncertainty), python.positionUncertainty, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.velocityUncertainty), python.velocityUncertainty, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(swift.accelerationUncertainty), python.accelerationUncertainty, accuracy: 1e-9)
        }
    }

    private func makeGoldenSessionSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/golden-video.mp4",
            initialBbox: BBoxSnapshot(x: 12, y: 24, width: 28, height: 22),
            calibration: CalibrationSnapshot(
                referenceLength: 2.0,
                unitLabel: "m",
                pixelDistance: 80.0,
                mode: "single_line",
                originXPx: 10.0,
                originYPx: 12.0,
                axisAngleDeg: 0.0,
                invertX: false,
                invertY: true,
                homography: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                presetName: "lab-bench"
            ),
            analysisConfig: AnalysisConfigSnapshot(
                smoothingWindow: 5,
                smoothingPolyorder: 2
            ),
            trackingConfig: TrackingConfigSnapshot(
                profile: .marker,
                robustRecovery: false,
                bidirectionalRefinement: false,
                debugTracking: true,
                searchMargin: 3.25,
                expandedSearchMargin: 7.5,
                scaleFactors: [0.9, 1.0, 1.15],
                detectionThreshold: 0.63,
                lowConfidenceThreshold: 0.41,
                reacquireThreshold: 0.7,
                suspectAfterFrames: 4,
                recoveryAfterFrames: 7,
                maxPredictionFrames: 11,
                templateUpdateRate: 0.14,
                stableUpdateThreshold: 0.72,
                markerConfidenceBias: 0.61,
                autoMarkerMinRatio: 0.19,
                interpolateShortGaps: false,
                maxInterpolationGap: 4
            ),
            metadata: ExperimentMetadataSnapshot(
                experimentLabel: "Golden Fixture Experiment",
                trialID: "trial-golden-01",
                operatorName: "Codex",
                notes: "Fixture-backed migration regression",
                tags: ["golden", "native", "migration"]
            ),
            advancedMode: true,
            selectedStartFrame: 3,
            selectedEndFrame: 18,
            scalePoints: [10, 20, 90, 20],
            referenceBbox: BBoxSnapshot(x: 100, y: 32, width: 18, height: 18),
            corrections: [
                CorrectionSnapshot(
                    trackID: "primary",
                    frameIndex: 11,
                    bbox: BBoxSnapshot(x: 56, y: 31, width: 28, height: 22),
                    note: "manual realignment"
                ),
            ],
            reviewState: ReviewStateSnapshot(
                lastFrameIndex: 13,
                selectedWindowStart: 6,
                selectedWindowEnd: 15,
                dismissedReviewFrames: [8, 14]
            ),
            eventMarkers: [
                EventMarkerSnapshot(
                    name: "manual_release",
                    frameIndex: 4,
                    timeS: 0.2,
                    value: 0.0,
                    unitLabel: "s",
                    axis: "",
                    note: "operator-marked release",
                    origin: "manual"
                ),
            ],
            additionalObjects: [
                AdditionalObjectSnapshot(
                    trackID: "secondary_1",
                    name: "Secondary Marker",
                    kind: "secondary",
                    bbox: BBoxSnapshot(x: 42, y: 40, width: 14, height: 14)
                ),
            ],
            trackQuality: TrackQualitySnapshot(
                lostSpans: [TrackSpanSnapshot(startFrame: 9, endFrame: 10, reason: "lost_tracking")],
                suspectSpans: [TrackSpanSnapshot(startFrame: 7, endFrame: 8, reason: "tracking_recovery")],
                correctedSpans: [TrackSpanSnapshot(startFrame: 11, endFrame: 14, reason: "manual_correction")],
                reacquisitionCount: 1,
                reviewRecommended: true
            ),
            exportPreferences: ExportPreferencesSnapshot(
                includeOverlay: false,
                includeDebugTracking: true,
                includePlots: false,
                reportTemplate: "research"
            )
        )
    }

    private func makeGoldenWorkspaceSnapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            title: "Golden Workspace",
            activeVideoPath: "/tmp/golden-video.mp4",
            items: [
                WorkspaceClip(
                    label: "golden_primary",
                    videoPath: "/tmp/golden-video.mp4",
                    sessionPath: "/tmp/golden-session.json",
                    notes: "Primary session"
                ),
                WorkspaceClip(
                    label: "golden_secondary",
                    videoPath: "/tmp/golden-video-2.mp4",
                    sessionPath: "/tmp/golden-session-2.json",
                    notes: "Secondary session"
                ),
            ]
        )
    }

    private func makeGoldenBundlePayload(outputDirectory: URL) -> NativeResearchBundlePayload {
        let session = makeGoldenSessionSnapshot()
        let analysisRows = [
            AnalysisRow(
                frameIndex: 3,
                timeSeconds: 0.15,
                xUnits: 0.0500,
                yUnits: 0.2250,
                speed: 0.0000,
                accelerationMagnitude: 0.0000,
                trackerConfidence: 0.9500,
                scientificConfidence: 0.9480,
                xPixels: 12.0,
                yPixels: 24.0,
                rawXUnits: 0.0500,
                rawYUnits: 0.2250,
                xVelocity: 0.0000,
                yVelocity: 0.0000,
                xAcceleration: 0.0000,
                yAcceleration: 0.0000,
                angleDegrees: 0.0000,
                positionUncertainty: 0.0040,
                velocityUncertainty: 0.0000,
                accelerationUncertainty: 0.0000,
                lost: false,
                corrected: false,
                state: "tracking",
                failureReason: ""
            ),
            AnalysisRow(
                frameIndex: 4,
                timeSeconds: 0.20,
                xUnits: 0.1750,
                yUnits: 0.2000,
                speed: 2.5495,
                accelerationMagnitude: 0.1803,
                trackerConfidence: 0.9200,
                scientificConfidence: 0.9120,
                xPixels: 17.0,
                yPixels: 25.0,
                rawXUnits: 0.1750,
                rawYUnits: 0.2000,
                xVelocity: 2.5000,
                yVelocity: -0.5000,
                xAcceleration: 0.1500,
                yAcceleration: -0.1000,
                angleDegrees: -11.3099,
                positionUncertainty: 0.0160,
                velocityUncertainty: 0.0550,
                accelerationUncertainty: 0.0200,
                lost: false,
                corrected: false,
                state: "tracking",
                failureReason: ""
            ),
            AnalysisRow(
                frameIndex: 5,
                timeSeconds: 0.25,
                xUnits: 0.3250,
                yUnits: 0.1625,
                speed: 3.9051,
                accelerationMagnitude: 0.5385,
                trackerConfidence: 0.8800,
                scientificConfidence: 0.7600,
                xPixels: 23.0,
                yPixels: 27.0,
                rawXUnits: 0.3250,
                rawYUnits: 0.1625,
                xVelocity: 3.0000,
                yVelocity: -0.7500,
                xAcceleration: 0.4000,
                yAcceleration: -0.3600,
                angleDegrees: -14.0362,
                positionUncertainty: 0.0400,
                velocityUncertainty: 0.1200,
                accelerationUncertainty: 0.0600,
                lost: true,
                corrected: false,
                state: "lost",
                failureReason: "occluded"
            ),
            AnalysisRow(
                frameIndex: 6,
                timeSeconds: 0.30,
                xUnits: 0.4250,
                yUnits: 0.1000,
                speed: 2.9155,
                accelerationMagnitude: 1.1402,
                trackerConfidence: 0.9000,
                scientificConfidence: 0.7700,
                xPixels: 27.0,
                yPixels: 30.0,
                rawXUnits: 0.4250,
                rawYUnits: 0.1000,
                xVelocity: 2.0000,
                yVelocity: -1.2500,
                xAcceleration: -0.8000,
                yAcceleration: -0.9000,
                angleDegrees: -32.0054,
                positionUncertainty: 0.0600,
                velocityUncertainty: 0.2200,
                accelerationUncertainty: 0.0800,
                lost: false,
                corrected: true,
                state: "reacquired",
                failureReason: "manual_correction"
            ),
        ]

        return NativeResearchBundlePayload(
            session: session,
            trackID: "primary",
            trackName: "Primary Marker",
            analysisRows: analysisRows,
            pairwiseMetrics: [
                PairwiseMetricSnapshot(
                    primaryTrackID: "primary",
                    secondaryTrackID: "secondary_1",
                    samples: [
                        PairwiseMetricSampleSnapshot(
                            frameIndex: 4,
                            timeSeconds: 0.20,
                            distanceUnits: 0.42,
                            relativeSpeedUnitsPerSecond: 0.9,
                            relativeDXUnits: 0.32,
                            relativeDYUnits: -0.12,
                            centerOfMassXUnits: 0.21,
                            centerOfMassYUnits: 0.16
                        ),
                        PairwiseMetricSampleSnapshot(
                            frameIndex: 5,
                            timeSeconds: 0.25,
                            distanceUnits: 0.26,
                            relativeSpeedUnitsPerSecond: 1.4,
                            relativeDXUnits: 0.18,
                            relativeDYUnits: -0.08,
                            centerOfMassXUnits: 0.27,
                            centerOfMassYUnits: 0.13
                        ),
                    ]
                ),
            ],
            eventMarkers: [
                EventMarkerRecord(
                    name: "manual_release",
                    frameIndex: 4,
                    timeSeconds: 0.20,
                    value: 0.0,
                    unitLabel: "s",
                    axis: "",
                    note: "operator-marked release",
                    origin: "manual"
                ),
            ],
            outputDirectory: outputDirectory,
            reportTemplate: "research",
            trackingProfile: .marker,
            includeOverlay: false,
            includePlots: false,
            debugTracking: true,
            summary: nil,
            quality: nil,
            modules: []
        )
    }

    private func makePythonComparisonObservations() -> [PythonComparisonObservation] {
        [
            PythonComparisonObservation(
                frameIndex: 0,
                timestamp: 0.00,
                centroidXPx: 18.0,
                centroidYPx: 30.0,
                bbox: [16.0, 28.0, 4.0, 4.0],
                confidence: 0.96,
                lost: false,
                corrected: false
            ),
            PythonComparisonObservation(
                frameIndex: 1,
                timestamp: 0.05,
                centroidXPx: 21.0,
                centroidYPx: 31.0,
                bbox: [19.0, 29.0, 4.0, 4.0],
                confidence: 0.93,
                lost: false,
                corrected: false
            ),
            PythonComparisonObservation(
                frameIndex: 2,
                timestamp: 0.10,
                centroidXPx: 25.0,
                centroidYPx: 33.0,
                bbox: [23.0, 31.0, 4.0, 4.0],
                confidence: 0.88,
                lost: true,
                corrected: false
            ),
            PythonComparisonObservation(
                frameIndex: 3,
                timestamp: 0.15,
                centroidXPx: 30.0,
                centroidYPx: 36.0,
                bbox: [28.0, 34.0, 4.0, 4.0],
                confidence: 0.90,
                lost: false,
                corrected: true
            ),
            PythonComparisonObservation(
                frameIndex: 4,
                timestamp: 0.20,
                centroidXPx: 36.0,
                centroidYPx: 40.0,
                bbox: [34.0, 38.0, 4.0, 4.0],
                confidence: 0.94,
                lost: false,
                corrected: false
            ),
        ]
    }

    private func runPythonSerializationComparison(
        sessionOutputURL: URL,
        workspaceOutputURL: URL
    ) throws {
        let script = """
import sys
from pathlib import Path

from tracker_ai.core.analysis import AnalysisConfig
from tracker_ai.core.calibration import CalibrationProfile
from tracker_ai.core.session import (
    EventMarker,
    ExportPreferences,
    ExperimentMetadata,
    ProjectSession,
    SessionReviewState,
)
from tracker_ai.core.tracking import (
    BBox,
    CorrectionAnchor,
    TrackQualityMetadata,
    TrackSpan,
    TrackedObject,
    TrackingConfig,
    TrackingProfile,
)
from tracker_ai.core.workspace import ResearchWorkspace, WorkspaceItem

session = ProjectSession(
    video_path="/tmp/golden-video.mp4",
    initial_bbox=BBox(12, 24, 28, 22),
    reference_bbox=BBox(100, 32, 18, 18),
    calibration=CalibrationProfile(
        reference_length=2.0,
        unit_label="m",
        pixel_distance=80.0,
        mode="single_line",
        origin_x_px=10.0,
        origin_y_px=12.0,
        axis_angle_deg=0.0,
        invert_x=False,
        invert_y=True,
        homography=(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0),
        preset_name="lab-bench",
    ),
    analysis_config=AnalysisConfig(smoothing_window=5, smoothing_polyorder=2),
    tracking_config=TrackingConfig(
        profile=TrackingProfile.MARKER,
        robust_recovery=False,
        bidirectional_refinement=False,
        debug_tracking=True,
        search_margin=3.25,
        expanded_search_margin=7.5,
        scale_factors=(0.9, 1.0, 1.15),
        detection_threshold=0.63,
        low_confidence_threshold=0.41,
        reacquire_threshold=0.7,
        suspect_after_frames=4,
        recovery_after_frames=7,
        max_prediction_frames=11,
        template_update_rate=0.14,
        stable_update_threshold=0.72,
        marker_confidence_bias=0.61,
        auto_marker_min_ratio=0.19,
        interpolate_short_gaps=False,
        max_interpolation_gap=4,
    ),
    metadata=ExperimentMetadata(
        experiment_label="Golden Fixture Experiment",
        trial_id="trial-golden-01",
        operator_name="Codex",
        notes="Fixture-backed migration regression",
        tags=("golden", "native", "migration"),
    ),
    selected_start_frame=3,
    selected_end_frame=18,
    scale_points=(10.0, 20.0, 90.0, 20.0),
    corrections=[
        CorrectionAnchor(
            frame_index=11,
            bbox=BBox(56, 31, 28, 22),
            note="manual realignment",
            track_id="primary",
        )
    ],
    track_quality=TrackQualityMetadata(
        lost_spans=[TrackSpan(start_frame=9, end_frame=10, reason="lost_tracking")],
        suspect_spans=[TrackSpan(start_frame=7, end_frame=8, reason="tracking_recovery")],
        corrected_spans=[TrackSpan(start_frame=11, end_frame=14, reason="manual_correction")],
        reacquisition_count=1,
        review_recommended=True,
    ),
    advanced_mode=True,
    review_state=SessionReviewState(
        last_frame_index=13,
        selected_window_start=6,
        selected_window_end=15,
        dismissed_review_frames=(8, 14),
    ),
    event_markers=(
        EventMarker(
            name="manual_release",
            frame_index=4,
            time_s=0.2,
            value=0.0,
            unit_label="s",
            note="operator-marked release",
            origin="manual",
        ),
    ),
    export_preferences=ExportPreferences(
        include_overlay=False,
        include_debug_tracking=True,
        include_plots=False,
        report_template="research",
    ),
    additional_objects=(
        TrackedObject(
            track_id="secondary_1",
            name="Secondary Marker",
            bbox=BBox(42, 40, 14, 14),
            kind="secondary",
        ),
    ),
)
session.save(Path(sys.argv[1]))

workspace = ResearchWorkspace(
    title="Golden Workspace",
    active_video_path="/tmp/golden-video.mp4",
    items=(
        WorkspaceItem(
            label="golden_primary",
            video_path="/tmp/golden-video.mp4",
            session_path="/tmp/golden-session.json",
            notes="Primary session",
        ),
        WorkspaceItem(
            label="golden_secondary",
            video_path="/tmp/golden-video-2.mp4",
            session_path="/tmp/golden-session-2.json",
            notes="Secondary session",
        ),
    ),
)
workspace.save(Path(sys.argv[2]))
"""

        try runPython(script: script, arguments: [
            sessionOutputURL.path,
            workspaceOutputURL.path,
        ])
    }

    private func runPythonAnalysisComparison(
        observations: [PythonComparisonObservation],
        calibration: PythonAnalysisCalibration,
        config: PythonAnalysisConfig
    ) throws -> [PythonAnalysisRow] {
        let directory = makeTemporaryDirectory()
        let inputURL = directory.appendingPathComponent("analysis-input.json")
        let outputURL = directory.appendingPathComponent("analysis-output.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(
            PythonAnalysisInput(
                observations: observations,
                calibration: calibration,
                config: config
            )
        ).write(to: inputURL)

        let script = """
import json
import sys
from pathlib import Path

from tracker_ai.core.analysis import AnalysisConfig, analyze_track
from tracker_ai.core.calibration import CalibrationProfile
from tracker_ai.core.tracking import BBox, TrackResult, TrackingObservation

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
calibration = CalibrationProfile(
    reference_length=payload["calibration"]["reference_length"],
    unit_label=payload["calibration"]["unit_label"],
    pixel_distance=payload["calibration"]["pixel_distance"],
    mode="single_line",
    origin_x_px=payload["calibration"]["origin_x_px"],
    origin_y_px=payload["calibration"]["origin_y_px"],
    axis_angle_deg=0.0,
    invert_x=False,
    invert_y=False,
)
config = AnalysisConfig(
    smoothing_window=payload["config"]["smoothing_window"],
    smoothing_polyorder=payload["config"]["smoothing_polyorder"],
)
observations = []
for item in payload["observations"]:
    bbox = BBox(*item["bbox"])
    observations.append(
        TrackingObservation(
            frame_index=item["frame_index"],
            timestamp=item["timestamp"],
            centroid_x_px=item["centroid_x_px"],
            centroid_y_px=item["centroid_y_px"],
            bbox=bbox,
            confidence=item["confidence"],
            lost=item["lost"],
            corrected=item["corrected"],
        )
    )

track = TrackResult(
    observations=observations,
    tracker_name="python-comparison",
    average_confidence=sum(item["confidence"] for item in payload["observations"]) / len(payload["observations"]),
    start_frame=observations[0].frame_index,
    end_frame=observations[-1].frame_index,
    initial_bbox=observations[0].bbox,
)
analysis = analyze_track(track, calibration, config)
rows = analysis.to_rows()
Path(sys.argv[2]).write_text(json.dumps(rows, indent=2), encoding="utf-8")
"""

        try runPython(script: script, arguments: [
            inputURL.path,
            outputURL.path,
        ])

        let data = try Data(contentsOf: outputURL)
        return try JSONDecoder().decode([PythonAnalysisRow].self, from: data)
    }

    private func runPython(script: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script] + arguments
        process.currentDirectoryURL = repositoryRoot

        var environment = ProcessInfo.processInfo.environment
        let sourceRoot = repositoryRoot.appendingPathComponent("src").path
        if let existing = environment["PYTHONPATH"], !existing.isEmpty {
            environment["PYTHONPATH"] = "\(sourceRoot):\(existing)"
        } else {
            environment["PYTHONPATH"] = sourceRoot
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus == 127 {
                throw XCTSkip("python3 is unavailable for cross-language comparison tests.")
            }
            XCTFail("Python comparison command failed: \(errorOutput)")
            return
        }
    }

    private func assertFixtureTextMatches(
        actual: String,
        fixtureName: String,
        canonicalizer: (String) throws -> String
    ) throws {
        let normalized = try canonicalizer(actual)
        let fixtureURL = fixturesRoot.appendingPathComponent(fixtureName)

        if shouldUpdateFixtures {
            try FileManager.default.createDirectory(
                at: fixturesRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try normalized.write(to: fixtureURL, atomically: true, encoding: .utf8)
            return
        }

        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            XCTFail("Missing fixture at \(fixtureURL.path)\n\nActual output:\n\(normalized)")
            return
        }

        let expected = try canonicalizer(String(contentsOf: fixtureURL, encoding: .utf8))
        XCTAssertEqual(normalized, expected, "Fixture mismatch for \(fixtureName)")
    }

    private func canonicalJSONText(_ text: String) throws -> String {
        let data = Data(text.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: normalized, as: UTF8.self)
    }

    private func canonicalJSONText(contentsOf url: URL) throws -> String {
        try canonicalJSONText(String(contentsOf: url, encoding: .utf8))
    }

    private func canonicalPlainText(_ text: String) throws -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private var shouldUpdateFixtures: Bool {
        ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1"
    }

    private var fixturesRoot: URL {
        repositoryRoot
            .appendingPathComponent("tests")
            .appendingPathComponent("TrackerAIMacTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("MigrationBacklog20")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct PythonComparisonObservation: Codable {
    var frameIndex: Int
    var timestamp: Double
    var centroidXPx: Double
    var centroidYPx: Double
    var bbox: [Double]
    var confidence: Double
    var lost: Bool
    var corrected: Bool

    enum CodingKeys: String, CodingKey {
        case frameIndex = "frame_index"
        case timestamp
        case centroidXPx = "centroid_x_px"
        case centroidYPx = "centroid_y_px"
        case bbox
        case confidence
        case lost
        case corrected
    }

    var nativeObservation: NativeTrackingObservation {
        NativeTrackingObservation(
            frameIndex: frameIndex,
            timeSeconds: timestamp,
            centroidXPixels: centroidXPx,
            centroidYPixels: centroidYPx,
            bbox: BBoxSnapshot(
                x: bbox[0],
                y: bbox[1],
                width: bbox[2],
                height: bbox[3]
            ),
            confidence: confidence,
            lost: lost,
            corrected: corrected,
            state: lost ? "lost" : (corrected ? "reacquired" : "tracking"),
            failureReason: lost ? "occluded" : nil,
            source: corrected ? "manual_correction" : "measured",
            isInferred: lost,
            isInterpolated: false
        )
    }
}

private struct PythonAnalysisCalibration: Codable {
    var referenceLength: Double
    var unitLabel: String
    var pixelDistance: Double
    var originXPx: Double
    var originYPx: Double

    enum CodingKeys: String, CodingKey {
        case referenceLength = "reference_length"
        case unitLabel = "unit_label"
        case pixelDistance = "pixel_distance"
        case originXPx = "origin_x_px"
        case originYPx = "origin_y_px"
    }
}

private struct PythonAnalysisConfig: Codable {
    var smoothingWindow: Int
    var smoothingPolyorder: Int

    enum CodingKeys: String, CodingKey {
        case smoothingWindow = "smoothing_window"
        case smoothingPolyorder = "smoothing_polyorder"
    }
}

private struct PythonAnalysisInput: Codable {
    var observations: [PythonComparisonObservation]
    var calibration: PythonAnalysisCalibration
    var config: PythonAnalysisConfig
}

private struct PythonAnalysisRow: Decodable {
    var frameIndex: Int
    var timeSeconds: Double
    var xPixels: Double
    var yPixels: Double
    var rawXUnits: Double
    var rawYUnits: Double
    var xUnits: Double
    var yUnits: Double
    var xVelocity: Double
    var yVelocity: Double
    var xAcceleration: Double
    var yAcceleration: Double
    var speed: Double
    var accelerationMagnitude: Double
    var angleDegrees: Double
    var confidence: Double
    var scientificConfidence: Double
    var positionUncertainty: Double
    var velocityUncertainty: Double
    var accelerationUncertainty: Double

    enum CodingKeys: String, CodingKey {
        case frameIndex = "frame_index"
        case timeSeconds = "time_s"
        case xPixels = "x_px"
        case yPixels = "y_px"
        case rawXUnits = "raw_x_units"
        case rawYUnits = "raw_y_units"
        case xUnits = "x_units"
        case yUnits = "y_units"
        case xVelocity = "vx"
        case yVelocity = "vy"
        case xAcceleration = "ax"
        case yAcceleration = "ay"
        case speed
        case accelerationMagnitude = "acceleration_magnitude"
        case angleDegrees = "angle_deg"
        case confidence
        case scientificConfidence = "scientific_confidence"
        case positionUncertainty = "position_uncertainty"
        case velocityUncertainty = "velocity_uncertainty"
        case accelerationUncertainty = "acceleration_uncertainty"
    }
}
