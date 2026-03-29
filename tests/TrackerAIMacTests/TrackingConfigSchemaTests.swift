import Foundation
import XCTest
@testable import TrackerAIMac

final class TrackingConfigSchemaTests: XCTestCase {
    func testPythonCompatibleTrackingConfigRoundTripsFullSchema() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        let inputURL = temporaryDirectory.appendingPathComponent("python_session.json")
        let outputURL = temporaryDirectory.appendingPathComponent("swift_session.json")
        let payload = """
        {
          "video_path": "/tmp/video.mp4",
          "initial_bbox": { "x": 1, "y": 2, "width": 3, "height": 4 },
          "calibration": {
            "reference_length": 2.5,
            "unit_label": "m",
            "pixel_distance": 50
          },
          "analysis_config": {
            "smoothing_window": 7,
            "smoothing_polyorder": 2
          },
          "scale_points": [0, 0, 50, 0],
          "tracking_config": {
            "profile": "marker",
            "robust_recovery": false,
            "bidirectional_refinement": false,
            "debug_tracking": true,
            "search_margin": 3.1,
            "expanded_search_margin": 7.4,
            "scale_factors": [0.85, 1.0, 1.2],
            "detection_threshold": 0.61,
            "low_confidence_threshold": 0.42,
            "reacquire_threshold": 0.68,
            "suspect_after_frames": 4,
            "recovery_after_frames": 7,
            "max_prediction_frames": 10,
            "template_update_rate": 0.14,
            "stable_update_threshold": 0.73,
            "marker_confidence_bias": 0.62,
            "auto_marker_min_ratio": 0.18,
            "interpolate_short_gaps": false,
            "max_interpolation_gap": 5
          }
        }
        """
        try payload.write(to: inputURL, atomically: true, encoding: .utf8)

        let bridge = PythonEngineBridge()
        let session = try bridge.loadSession(from: inputURL)
        let config = session.resolvedTrackingConfig

        XCTAssertEqual(config.profile, .marker)
        XCTAssertEqual(config.robustRecovery ?? true, false)
        XCTAssertEqual(config.bidirectionalRefinement ?? true, false)
        XCTAssertEqual(config.debugTracking ?? false, true)
        XCTAssertEqual(config.searchMargin ?? -1, 3.1, accuracy: 1e-12)
        XCTAssertEqual(config.expandedSearchMargin ?? -1, 7.4, accuracy: 1e-12)
        XCTAssertEqual(config.scaleFactors ?? [], [0.85, 1.0, 1.2])
        XCTAssertEqual(config.detectionThreshold ?? -1, 0.61, accuracy: 1e-12)
        XCTAssertEqual(config.lowConfidenceThreshold ?? -1, 0.42, accuracy: 1e-12)
        XCTAssertEqual(config.reacquireThreshold ?? -1, 0.68, accuracy: 1e-12)
        XCTAssertEqual(config.suspectAfterFrames ?? -1, 4)
        XCTAssertEqual(config.recoveryAfterFrames ?? -1, 7)
        XCTAssertEqual(config.maxPredictionFrames ?? -1, 10)
        XCTAssertEqual(config.templateUpdateRate ?? -1, 0.14, accuracy: 1e-12)
        XCTAssertEqual(config.stableUpdateThreshold ?? -1, 0.73, accuracy: 1e-12)
        XCTAssertEqual(config.markerConfidenceBias ?? -1, 0.62, accuracy: 1e-12)
        XCTAssertEqual(config.autoMarkerMinRatio ?? -1, 0.18, accuracy: 1e-12)
        XCTAssertEqual(config.interpolateShortGaps ?? true, false)
        XCTAssertEqual(config.maxInterpolationGap ?? -1, 5)

        try bridge.saveSession(session, to: outputURL)
        let data = try Data(contentsOf: outputURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let trackingConfig = try XCTUnwrap(json["tracking_config"] as? [String: Any])

        XCTAssertEqual(trackingConfig["search_margin"] as? Double, 3.1)
        XCTAssertEqual(trackingConfig["expanded_search_margin"] as? Double, 7.4)
        XCTAssertEqual(trackingConfig["scale_factors"] as? [Double], [0.85, 1.0, 1.2])
        XCTAssertEqual(trackingConfig["detection_threshold"] as? Double, 0.61)
        XCTAssertEqual(trackingConfig["low_confidence_threshold"] as? Double, 0.42)
        XCTAssertEqual(trackingConfig["reacquire_threshold"] as? Double, 0.68)
        XCTAssertEqual(trackingConfig["suspect_after_frames"] as? Int, 4)
        XCTAssertEqual(trackingConfig["recovery_after_frames"] as? Int, 7)
        XCTAssertEqual(trackingConfig["max_prediction_frames"] as? Int, 10)
        XCTAssertEqual(trackingConfig["template_update_rate"] as? Double, 0.14)
        XCTAssertEqual(trackingConfig["stable_update_threshold"] as? Double, 0.73)
        XCTAssertEqual(trackingConfig["marker_confidence_bias"] as? Double, 0.62)
        XCTAssertEqual(trackingConfig["auto_marker_min_ratio"] as? Double, 0.18)
        XCTAssertEqual(trackingConfig["interpolate_short_gaps"] as? Bool, false)
        XCTAssertEqual(trackingConfig["max_interpolation_gap"] as? Int, 5)
    }

    @MainActor
    func testAppModelPersistsUserFacingAndInternalTrackingConfigFields() throws {
        let model = AppModel()
        let sessionURL = URL(fileURLWithPath: "/tmp/tracking-config-session.json")
        let outputDirectory = makeTemporaryDirectory()
        let expectedTrackingConfig = TrackingConfigSnapshot(
            profile: .marker,
            robustRecovery: false,
            bidirectionalRefinement: false,
            debugTracking: true,
            searchMargin: 3.1,
            expandedSearchMargin: 7.4,
            scaleFactors: [0.85, 1.0, 1.2],
            detectionThreshold: 0.61,
            lowConfidenceThreshold: 0.42,
            reacquireThreshold: 0.68,
            suspectAfterFrames: 4,
            recoveryAfterFrames: 7,
            maxPredictionFrames: 10,
            templateUpdateRate: 0.14,
            stableUpdateThreshold: 0.73,
            markerConfidenceBias: 0.62,
            autoMarkerMinRatio: 0.18,
            interpolateShortGaps: false,
            maxInterpolationGap: 5
        ).resolved()

        model.apply(session: makeSession(trackingConfig: expectedTrackingConfig), sessionURL: sessionURL, loadBundle: false)

        XCTAssertEqual(model.trackingProfile, .marker)
        XCTAssertEqual(model.trackingRobustRecovery, false)
        XCTAssertEqual(model.trackingBidirectionalRefinement, false)
        XCTAssertEqual(model.debugTracking, true)

        let rebuiltSession = try model.buildSessionSnapshot(videoURL: URL(fileURLWithPath: "/tmp/tracking-config-source.mp4"))
        XCTAssertEqual(rebuiltSession.resolvedTrackingConfig, expectedTrackingConfig)

        let configuration = try model.runConfiguration(from: rebuiltSession, outputDirectory: outputDirectory)
        XCTAssertEqual(configuration.trackingConfig, expectedTrackingConfig)
        XCTAssertEqual(configuration.trackingProfile, .marker)
        XCTAssertEqual(configuration.debugTracking, true)
    }

    private func makeSession(trackingConfig: TrackingConfigSnapshot) -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/tracking-config-source.mp4",
            initialBbox: BBoxSnapshot(x: 4, y: 5, width: 20, height: 22),
            calibration: CalibrationSnapshot(
                referenceLength: 1.0,
                unitLabel: "m",
                pixelDistance: 50,
                mode: "single_line",
                originXPx: nil,
                originYPx: nil,
                axisAngleDeg: nil,
                invertX: nil,
                invertY: nil,
                homography: nil,
                presetName: nil
            ),
            analysisConfig: AnalysisConfigSnapshot(
                smoothingWindow: 5,
                smoothingPolyorder: 2
            ),
            trackingConfig: trackingConfig,
            metadata: nil,
            advancedMode: true,
            selectedStartFrame: 3,
            selectedEndFrame: 12,
            scalePoints: [0, 0, 50, 0],
            referenceBbox: nil,
            corrections: nil,
            reviewState: nil,
            eventMarkers: nil,
            additionalObjects: nil,
            trackQuality: nil,
            exportPreferences: nil
        )
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
}
