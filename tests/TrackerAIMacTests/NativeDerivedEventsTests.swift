import Foundation
import XCTest
@testable import TrackerAIMac

final class NativeDerivedEventsTests: XCTestCase {
    func testCanonicalDerivedEventsMatchPythonStyleTiming() {
        let processor = NativeScientificProcessor()
        let rows = makeRows()

        let events = processor.buildDerivedEvents(rows: rows, unitLabel: "m")

        XCTAssertEqual(
            events.map(\.name),
            [
                "peak_speed",
                "vx_zero_crossing",
                "vy_zero_crossing",
                "apex",
                "furthest_x",
                "peak_acceleration",
                "vx_zero_crossing",
            ]
        )
        XCTAssertEqual(events.map(\.frameIndex), [2, 2, 2, 3, 3, 3, 4])
        XCTAssertEqual(events.first(where: { $0.name == "peak_speed" })?.timeSeconds ?? -1, 0.2, accuracy: 1e-9)
        XCTAssertEqual(events.first(where: { $0.name == "peak_acceleration" })?.value ?? -1, 5.0, accuracy: 1e-9)
        XCTAssertEqual(events.first(where: { $0.name == "apex" })?.axis, "y")
    }

    func testManualEventsWinWhenMergingWithMatchingDerivedEvents() {
        let reporter = NativeResearchReporter()
        let manual = [
            EventMarkerRecord(
                name: "apex",
                frameIndex: 3,
                timeSeconds: 0.3,
                value: 5.0,
                unitLabel: "m",
                axis: "y",
                note: "Manual confirmation",
                origin: "manual"
            )
        ]
        let derived = [
            EventMarkerRecord(
                name: "apex",
                frameIndex: 3,
                timeSeconds: 0.3,
                value: 5.0,
                unitLabel: "m",
                axis: "y",
                note: "Maximum vertical position",
                origin: "derived"
            ),
            EventMarkerRecord(
                name: "peak_speed",
                frameIndex: 2,
                timeSeconds: 0.2,
                value: 6.0,
                unitLabel: "m/s",
                axis: "",
                note: "Maximum speed",
                origin: "derived"
            )
        ]

        let merged = reporter.mergeEventMarkers(manual, withDerived: derived)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.name), ["peak_speed", "apex"])
        XCTAssertEqual(merged.last?.origin, "manual")
        XCTAssertEqual(merged.last?.note, "Manual confirmation")
    }

    func testExporterUsesSelectedReviewWindowForWindowSummary() throws {
        let exporter = NativeResearchBundleExporter()
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let session = makeSessionSnapshot(
            selectedStartFrame: 0,
            selectedEndFrame: 5,
            reviewState: ReviewStateSnapshot(
                lastFrameIndex: nil,
                selectedWindowStart: 2,
                selectedWindowEnd: 4,
                dismissedReviewFrames: nil
            )
        )

        _ = try exporter.export(
            NativeResearchBundlePayload(
                session: session,
                trackID: "primary",
                trackName: "Primary Object",
                analysisRows: makeRows(),
                pairwiseMetrics: [],
                eventMarkers: [],
                outputDirectory: outputDirectory,
                reportTemplate: "research",
                trackingProfile: .auto,
                includeOverlay: false,
                includePlots: false,
                debugTracking: false,
                summary: nil,
                quality: nil,
                modules: []
            )
        )

        let data = try Data(contentsOf: outputDirectory.appendingPathComponent("selected_window_summary.json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let summary = try decoder.decode(NativeWindowSummary.self, from: data)

        XCTAssertEqual(summary.startFrame, 2)
        XCTAssertEqual(summary.endFrame, 4)
        XCTAssertEqual(summary.durationSeconds, 0.2, accuracy: 1e-9)
        XCTAssertEqual(summary.displacement, 0.0, accuracy: 1e-9)
        XCTAssertEqual(summary.meanSpeed, (6.0 + 4.0 + 3.0) / 3.0, accuracy: 1e-9)
        XCTAssertEqual(summary.maxAcceleration, 5.0, accuracy: 1e-9)
    }

    private func makeRows() -> [AnalysisRow] {
        [
            makeRow(frameIndex: 0, timeSeconds: 0.0, xUnits: 0.0, yUnits: 0.0, speed: 1.0, accelerationMagnitude: 0.2, xVelocity: -2.0, yVelocity: 2.0),
            makeRow(frameIndex: 1, timeSeconds: 0.1, xUnits: 1.0, yUnits: 2.0, speed: 2.0, accelerationMagnitude: 1.0, xVelocity: -1.0, yVelocity: 1.0),
            makeRow(frameIndex: 2, timeSeconds: 0.2, xUnits: 2.0, yUnits: 4.0, speed: 6.0, accelerationMagnitude: 2.0, xVelocity: 0.5, yVelocity: -0.5),
            makeRow(frameIndex: 3, timeSeconds: 0.3, xUnits: 3.0, yUnits: 5.0, speed: 4.0, accelerationMagnitude: 5.0, xVelocity: 1.0, yVelocity: -1.0),
            makeRow(frameIndex: 4, timeSeconds: 0.4, xUnits: 2.0, yUnits: 4.0, speed: 3.0, accelerationMagnitude: 4.0, xVelocity: -0.5, yVelocity: -1.0),
            makeRow(frameIndex: 5, timeSeconds: 0.5, xUnits: 1.0, yUnits: 1.0, speed: 2.0, accelerationMagnitude: 1.0, xVelocity: -1.0, yVelocity: -2.0),
        ]
    }

    private func makeRow(
        frameIndex: Int,
        timeSeconds: Double,
        xUnits: Double,
        yUnits: Double,
        speed: Double,
        accelerationMagnitude: Double,
        xVelocity: Double,
        yVelocity: Double
    ) -> AnalysisRow {
        AnalysisRow(
            frameIndex: frameIndex,
            timeSeconds: timeSeconds,
            xUnits: xUnits,
            yUnits: yUnits,
            speed: speed,
            accelerationMagnitude: accelerationMagnitude,
            trackerConfidence: 0.9,
            scientificConfidence: 0.88,
            xPixels: xUnits * 10.0,
            yPixels: yUnits * 10.0,
            rawXUnits: xUnits,
            rawYUnits: yUnits,
            xVelocity: xVelocity,
            yVelocity: yVelocity,
            xAcceleration: 0.0,
            yAcceleration: 0.0,
            angleDegrees: 0.0,
            positionUncertainty: 0.01,
            velocityUncertainty: 0.01,
            accelerationUncertainty: 0.01,
            lost: false,
            corrected: false,
            state: "tracking",
            failureReason: ""
        )
    }

    private func makeSessionSnapshot(
        selectedStartFrame: Int?,
        selectedEndFrame: Int?,
        reviewState: ReviewStateSnapshot?
    ) -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/demo.mp4",
            initialBbox: BBoxSnapshot(x: 10, y: 10, width: 8, height: 8),
            calibration: CalibrationSnapshot(
                referenceLength: 1.0,
                unitLabel: "m",
                pixelDistance: 10.0,
                mode: "single_line",
                originXPx: 0,
                originYPx: 0,
                axisAngleDeg: 0,
                invertX: false,
                invertY: false,
                homography: nil,
                presetName: nil
            ),
            analysisConfig: AnalysisConfigSnapshot(smoothingWindow: 5, smoothingPolyorder: 2),
            trackingConfig: TrackingConfigSnapshot.pythonDefaults,
            metadata: nil,
            advancedMode: nil,
            selectedStartFrame: selectedStartFrame,
            selectedEndFrame: selectedEndFrame,
            scalePoints: [0, 0, 10, 0],
            referenceBbox: nil,
            corrections: nil,
            reviewState: reviewState,
            eventMarkers: nil,
            additionalObjects: [],
            trackQuality: nil,
            exportPreferences: nil
        )
    }
}
