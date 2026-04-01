import Foundation
import CoreGraphics
import XCTest
@testable import TrackerAIMac

final class NativeScientificProcessorTests: XCTestCase {
    func testNativeScientificProcessorMatchesPythonFixtures() throws {
        let processor = NativeScientificProcessor()

        for fixture in try loadFixtures() {
            let calibration = try fixture.calibration.makeCalibrationProfile()
            let rows = processor.process(
                observations: fixture.observations.map(\.nativeObservation),
                calibration: calibration,
                config: fixture.config.snapshot
            )

            XCTAssertEqual(rows.count, fixture.expectedRows.count, "Row count mismatch for \(fixture.name)")
            for (row, expected) in zip(rows, fixture.expectedRows) {
                XCTAssertEqual(row.frameIndex, expected.frameIndex, "Frame mismatch for \(fixture.name)")
                XCTAssertEqual(row.timeSeconds, expected.timeSeconds, accuracy: 1e-9, "Time mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.xPixels), expected.xPixels, accuracy: 1e-9, "x_px mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.yPixels), expected.yPixels, accuracy: 1e-9, "y_px mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.rawXUnits), expected.rawXUnits, accuracy: 1e-9, "raw_x mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.rawYUnits), expected.rawYUnits, accuracy: 1e-9, "raw_y mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(row.xUnits, expected.xUnits, accuracy: 1e-9, "x_units mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(row.yUnits, expected.yUnits, accuracy: 1e-9, "y_units mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.xVelocity), expected.xVelocity, accuracy: 1e-9, "vx mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.yVelocity), expected.yVelocity, accuracy: 1e-9, "vy mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.xAcceleration), expected.xAcceleration, accuracy: 1e-9, "ax mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.yAcceleration), expected.yAcceleration, accuracy: 1e-9, "ay mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(row.speed, expected.speed, accuracy: 1e-9, "speed mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(row.accelerationMagnitude, expected.accelerationMagnitude, accuracy: 1e-9, "acceleration mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.angleDegrees), expected.angleDegrees, accuracy: 1e-9, "angle mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(row.trackerConfidence, expected.confidence, accuracy: 1e-9, "confidence mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(row.scientificConfidence, expected.scientificConfidence, accuracy: 1e-9, "scientific confidence mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.positionUncertainty), expected.positionUncertainty, accuracy: 1e-9, "position uncertainty mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.velocityUncertainty), expected.velocityUncertainty, accuracy: 1e-9, "velocity uncertainty mismatch for \(fixture.name) frame \(expected.frameIndex)")
                XCTAssertEqual(try XCTUnwrap(row.accelerationUncertainty), expected.accelerationUncertainty, accuracy: 1e-9, "acceleration uncertainty mismatch for \(fixture.name) frame \(expected.frameIndex)")
            }
        }
    }

    func testNativeMultiObjectRunnerUsesScientificProcessorAsAuthoritativeStage() throws {
        let frames = [
            makeSyntheticFrame(objectRect: CGRect(x: 12, y: 20, width: 8, height: 8)),
            makeSyntheticFrame(objectRect: CGRect(x: 16, y: 22, width: 8, height: 8)),
            makeSyntheticFrame(objectRect: CGRect(x: 21, y: 25, width: 8, height: 8)),
            makeSyntheticFrame(objectRect: CGRect(x: 27, y: 29, width: 8, height: 8)),
            makeSyntheticFrame(objectRect: CGRect(x: 34, y: 34, width: 8, height: 8)),
            makeSyntheticFrame(objectRect: CGRect(x: 42, y: 40, width: 8, height: 8))
        ]
        var config = TrackingConfigSnapshot.pythonDefaults.resolved()
        config.profile = .template
        config.bidirectionalRefinement = false
        config.interpolateShortGaps = false

        var session = makeSessionSnapshot(trackingConfig: config)
        session.analysisConfig = AnalysisConfigSnapshot(smoothingWindow: 2, smoothingPolyorder: 0)
        session.initialBbox = BBoxSnapshot(x: 12, y: 20, width: 8, height: 8)

        let result = try NativeMultiObjectTrackingRunner().run(
            frameImages: frames,
            session: session,
            fps: 24.0
        )

        let track = try XCTUnwrap(result.analysisTracks["primary"])
        let authoritativeRows = try XCTUnwrap(result.analysesByTrackID["primary"])
        let expectedRows = NativeScientificProcessor().process(
            observations: track.observations,
            calibration: try session.calibration.makeCalibrationProfile(),
            config: session.analysisConfig
        )

        XCTAssertEqual(authoritativeRows, expectedRows)
        XCTAssertTrue(authoritativeRows.allSatisfy { $0.rawXUnits != nil && $0.rawYUnits != nil })
        XCTAssertTrue(authoritativeRows.allSatisfy { $0.xVelocity != nil && $0.yVelocity != nil })
        XCTAssertTrue(authoritativeRows.allSatisfy { $0.xAcceleration != nil && $0.yAcceleration != nil })
    }

    private func loadFixtures() throws -> [KinematicAnalysisFixture] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "kinematic_analysis_fixtures", withExtension: "json"))
        return try JSONDecoder().decode([KinematicAnalysisFixture].self, from: Data(contentsOf: url))
    }

    private func makeSyntheticFrame(
        width: Int = 96,
        height: Int = 72,
        objectRect: CGRect
    ) -> CGImage {
        var rgba = Array(repeating: UInt8.zero, count: width * height * 4)
        let x0 = max(0, min(width - 1, Int(objectRect.minX.rounded(.down))))
        let y0 = max(0, min(height - 1, Int(objectRect.minY.rounded(.down))))
        let x1 = max(x0 + 1, min(width, Int(objectRect.maxX.rounded(.up))))
        let y1 = max(y0 + 1, min(height, Int(objectRect.maxY.rounded(.up))))

        for y in y0..<y1 {
            for x in x0..<x1 {
                let base = ((y * width) + x) * 4
                rgba[base] = 32
                rgba[base + 1] = 220
                rgba[base + 2] = 96
                rgba[base + 3] = 255
            }
        }

        let data = Data(rgba)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func makeSessionSnapshot(trackingConfig: TrackingConfigSnapshot) -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/demo.mp4",
            initialBbox: BBoxSnapshot(x: 12, y: 20, width: 8, height: 8),
            calibration: CalibrationSnapshot(
                referenceLength: 1.5,
                unitLabel: "m",
                pixelDistance: 15,
                mode: "single_line",
                originXPx: 5,
                originYPx: 10,
                axisAngleDeg: 0,
                invertX: false,
                invertY: false,
                homography: nil,
                presetName: nil
            ),
            analysisConfig: AnalysisConfigSnapshot(smoothingWindow: 7, smoothingPolyorder: 2),
            trackingConfig: trackingConfig,
            metadata: nil,
            advancedMode: nil,
            selectedStartFrame: 0,
            selectedEndFrame: 5,
            scalePoints: nil,
            referenceBbox: nil,
            corrections: nil,
            reviewState: nil,
            eventMarkers: nil,
            additionalObjects: [],
            trackQuality: nil,
            exportPreferences: nil
        )
    }
}

private struct KinematicAnalysisFixture: Decodable {
    var name: String
    var calibration: CalibrationFixture
    var config: AnalysisConfigFixture
    var observations: [ObservationFixture]
    var expectedRows: [ExpectedAnalysisRow]

    enum CodingKeys: String, CodingKey {
        case name
        case calibration
        case config
        case observations
        case expectedRows = "expected_rows"
    }
}

private struct AnalysisConfigFixture: Decodable {
    var smoothingWindow: Int
    var smoothingPolyorder: Int

    enum CodingKeys: String, CodingKey {
        case smoothingWindow = "smoothing_window"
        case smoothingPolyorder = "smoothing_polyorder"
    }

    var snapshot: AnalysisConfigSnapshot {
        AnalysisConfigSnapshot(
            smoothingWindow: smoothingWindow,
            smoothingPolyorder: smoothingPolyorder
        )
    }
}

private struct CalibrationFixture: Decodable {
    var referenceLength: Double
    var unitLabel: String
    var pixelDistance: Double
    var originXPx: Double?
    var originYPx: Double?
    var axisAngleDeg: Double?
    var invertX: Bool?
    var invertY: Bool?

    enum CodingKeys: String, CodingKey {
        case referenceLength = "reference_length"
        case unitLabel = "unit_label"
        case pixelDistance = "pixel_distance"
        case originXPx = "origin_x_px"
        case originYPx = "origin_y_px"
        case axisAngleDeg = "axis_angle_deg"
        case invertX = "invert_x"
        case invertY = "invert_y"
    }

    func makeCalibrationProfile() throws -> CalibrationProfile {
        try CalibrationProfile(
            referenceLength: referenceLength,
            unitLabel: unitLabel,
            pixelDistance: pixelDistance,
            mode: "single_line",
            originXPx: originXPx ?? 0,
            originYPx: originYPx ?? 0,
            axisAngleDeg: axisAngleDeg ?? 0,
            invertX: invertX ?? false,
            invertY: invertY ?? false,
            presetName: ""
        )
    }
}

private struct ObservationFixture: Decodable {
    var frameIndex: Int
    var timestamp: Double
    var centroidXPx: Double
    var centroidYPx: Double
    var bbox: [Double]
    var confidence: Double
    var lost: Bool
    var corrected: Bool
    var state: String
    var failureReason: String?

    enum CodingKeys: String, CodingKey {
        case frameIndex = "frame_index"
        case timestamp
        case centroidXPx = "centroid_x_px"
        case centroidYPx = "centroid_y_px"
        case bbox
        case confidence
        case lost
        case corrected
        case state
        case failureReason = "failure_reason"
    }

    var nativeObservation: NativeTrackingObservation {
        NativeTrackingObservation(
            frameIndex: frameIndex,
            timeSeconds: timestamp,
            centroidXPixels: centroidXPx,
            centroidYPixels: centroidYPx,
            bbox: BBoxSnapshot(x: bbox[0], y: bbox[1], width: bbox[2], height: bbox[3]),
            confidence: confidence,
            lost: lost,
            corrected: corrected,
            state: state,
            failureReason: failureReason,
            source: lost ? "predicted" : (corrected ? "manual_correction" : "measured"),
            isInferred: lost,
            isInterpolated: false
        )
    }
}

private struct ExpectedAnalysisRow: Decodable {
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
