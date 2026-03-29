import Foundation
import XCTest
@testable import TrackerAIMac

final class CalibrationProfileTests: XCTestCase {
    func testSingleLineCalibrationFromPointsMatchesUnitsPerPixel() throws {
        let calibration = try CalibrationProfile.fromPoints(
            x1: 0,
            y1: 0,
            x2: 100,
            y2: 0,
            referenceLength: 2,
            unitLabel: "m"
        )

        XCTAssertEqual(calibration.mode, "single_line")
        XCTAssertEqual(calibration.unitsPerPixel, 0.02, accuracy: 1e-12)
        XCTAssertEqual(calibration.pixelsToUnits(50), 1.0, accuracy: 1e-12)

        let transformed = calibration.transformPoint(xPx: 50, yPx: 25)
        XCTAssertEqual(transformed.0, 1.0, accuracy: 1e-6)
        XCTAssertEqual(transformed.1, 0.5, accuracy: 1e-6)
    }

    func testTwoAxisCalibrationMatchesPythonRotationBehavior() throws {
        let calibration = try CalibrationProfile.fromAxisPoints(
            originX: 10,
            originY: 10,
            axisX: 10,
            axisY: 110,
            referenceLength: 2,
            unitLabel: "m"
        )

        let transformed = calibration.transformPoint(xPx: 10, yPx: 60)
        XCTAssertEqual(transformed.0, 1.0, accuracy: 1e-6)
        XCTAssertEqual(transformed.1, 0.0, accuracy: 1e-6)
    }

    func testMarkerSizeCalibrationTransformsWithDirectScaling() throws {
        let calibration = try CalibrationProfile.fromMarkerSize(
            markerBBoxWidthPx: 20,
            referenceLength: 2,
            unitLabel: "cm",
            presetName: "aruco_20"
        )

        let transformed = calibration.transformPoint(xPx: 5, yPx: 10)
        XCTAssertEqual(calibration.mode, "marker_size")
        XCTAssertEqual(calibration.presetName, "aruco_20")
        XCTAssertEqual(transformed.0, 0.5, accuracy: 1e-6)
        XCTAssertEqual(transformed.1, 1.0, accuracy: 1e-6)
    }

    func testHomographyAppliesBeforeOriginAndScaling() throws {
        let calibration = try CalibrationProfile.fromHomography(
            homography: [
                1, 0, 5,
                0, 1, -3,
                0, 0, 1,
            ],
            referenceLength: 10,
            unitLabel: "cm",
            pixelDistance: 20,
            originXPx: 2,
            originYPx: 1,
            presetName: "board"
        )

        let transformed = calibration.transformPoint(xPx: 2, yPx: 6)
        XCTAssertEqual(transformed.0, 2.5, accuracy: 1e-6)
        XCTAssertEqual(transformed.1, 1.0, accuracy: 1e-6)
    }

    func testTransformPointAppliesOriginRotationAndAxisInversion() throws {
        let calibration = try CalibrationProfile(
            referenceLength: 2,
            unitLabel: "m",
            pixelDistance: 100,
            mode: "single_line",
            originXPx: 10,
            originYPx: 20,
            axisAngleDeg: 90,
            invertX: true
        )

        let transformed = calibration.transformPoint(xPx: 10, yPx: 70)
        XCTAssertEqual(transformed.0, -1.0, accuracy: 1e-6)
        XCTAssertEqual(transformed.1, 0.0, accuracy: 1e-6)
    }

    func testHomographyUsesPythonStyleNearZeroDenominatorGuard() throws {
        let calibration = try CalibrationProfile.fromHomography(
            homography: [
                1, 0, 0,
                0, 1, 0,
                0, 0, 0,
            ],
            referenceLength: 1,
            unitLabel: "m",
            pixelDistance: 1
        )

        let transformed = calibration.transformPoint(xPx: 3, yPx: 4)
        XCTAssertEqual(transformed.0, 3_000_000, accuracy: 0.5)
        XCTAssertEqual(transformed.1, 4_000_000, accuracy: 0.5)
    }

    func testCalibrationSnapshotRoundTripsPythonCompatibleFields() throws {
        let temporaryDirectory = makeTemporaryDirectory()
        let inputURL = temporaryDirectory.appendingPathComponent("python_session.json")
        let outputURL = temporaryDirectory.appendingPathComponent("swift_session.json")
        let payload = """
        {
          "video_path": "/tmp/video.mp4",
          "initial_bbox": { "x": 1, "y": 2, "width": 3, "height": 4 },
          "advanced_mode": true,
          "calibration": {
            "reference_length": 2.5,
            "unit_label": "m",
            "pixel_distance": 50,
            "mode": "homography",
            "origin_x_px": 12,
            "origin_y_px": 18,
            "axis_angle_deg": 15,
            "invert_x": true,
            "invert_y": false,
            "homography": [1, 0, 2, 0, 1, 3, 0, 0, 1],
            "preset_name": "checkerboard"
          },
          "analysis_config": {
            "smoothing_window": 7,
            "smoothing_polyorder": 2
          }
        }
        """
        try payload.write(to: inputURL, atomically: true, encoding: .utf8)

        let bridge = PythonEngineBridge()
        let session = try bridge.loadSession(from: inputURL)
        XCTAssertEqual(session.advancedMode, true)
        XCTAssertEqual(session.calibration.mode, "homography")
        XCTAssertEqual(session.calibration.originXPx, 12)
        XCTAssertEqual(session.calibration.originYPx, 18)
        XCTAssertEqual(session.calibration.axisAngleDeg, 15)
        XCTAssertEqual(session.calibration.invertX, true)
        XCTAssertEqual(session.calibration.invertY, false)
        XCTAssertEqual(session.calibration.homography ?? [], [1, 0, 2, 0, 1, 3, 0, 0, 1])
        XCTAssertEqual(session.calibration.presetName, "checkerboard")

        try bridge.saveSession(session, to: outputURL)
        let data = try Data(contentsOf: outputURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let calibration = try XCTUnwrap(json["calibration"] as? [String: Any])

        XCTAssertEqual(json["advanced_mode"] as? Bool, true)
        XCTAssertEqual(calibration["origin_x_px"] as? Double, 12)
        XCTAssertEqual(calibration["origin_y_px"] as? Double, 18)
        XCTAssertEqual(calibration["axis_angle_deg"] as? Double, 15)
        XCTAssertEqual(calibration["invert_x"] as? Bool, true)
        XCTAssertEqual(calibration["invert_y"] as? Bool, false)
        XCTAssertEqual(calibration["preset_name"] as? String, "checkerboard")
        XCTAssertEqual(calibration["mode"] as? String, "homography")
        XCTAssertEqual(calibration["homography"] as? [Double], [1, 0, 2, 0, 1, 3, 0, 0, 1])
    }

    func testLineModeNormalizesToSingleLine() throws {
        let snapshot = CalibrationSnapshot(
            referenceLength: 1,
            unitLabel: "m",
            pixelDistance: 10,
            mode: "line",
            originXPx: 4,
            originYPx: 6,
            axisAngleDeg: nil,
            invertX: nil,
            invertY: nil,
            homography: nil,
            presetName: nil
        )

        let profile = try snapshot.makeCalibrationProfile()
        XCTAssertEqual(profile.mode, "single_line")
        XCTAssertEqual(profile.originXPx, 4)
        XCTAssertEqual(profile.originYPx, 6)
    }

    func testInvalidHomographyLengthThrows() {
        XCTAssertThrowsError(
            try CalibrationProfile.fromHomography(
                homography: [1, 0, 0],
                referenceLength: 1,
                unitLabel: "m",
                pixelDistance: 10
            )
        )
    }

    @MainActor
    func testAppModelBuildsHomographyCalibrationFromAdvancedControls() throws {
        let model = AppModel()
        model.referenceLength = "2"
        model.unitLabel = "m"
        model.scaleLine = ScaleLineDraft(x1: "10", y1: "20", x2: "110", y2: "20")
        model.calibrationMode = "homography"
        model.calibrationOriginXInput = "12"
        model.calibrationOriginYInput = "18"
        model.calibrationPixelDistanceInput = "40"
        model.calibrationPresetName = "board"
        model.calibrationHomographyInput = "1 0 5 0 1 -3 0 0 1"

        let profile = try model.calibrationProfileForCurrentSetup()

        XCTAssertEqual(profile.mode, "homography")
        XCTAssertEqual(profile.originXPx, 12, accuracy: 1e-12)
        XCTAssertEqual(profile.originYPx, 18, accuracy: 1e-12)
        XCTAssertEqual(profile.pixelDistance, 40, accuracy: 1e-12)
        XCTAssertEqual(profile.presetName, "board")
        XCTAssertEqual(profile.homography ?? [], [1, 0, 5, 0, 1, -3, 0, 0, 1])
    }

    @MainActor
    func testAppModelFlagsMalformedHomographyInline() {
        let model = AppModel()
        model.calibrationMode = "homography"
        model.calibrationHomographyInput = "1 0 0 0"

        XCTAssertEqual(model.calibrationValidationMessage, "Homography mode requires exactly 9 numeric values.")
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
