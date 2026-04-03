import Foundation
import XCTest
@testable import TrackerAIMac

final class SetupReviewParityTests: XCTestCase {
    @MainActor
    func testRangeHelpersCaptureCurrentFrameAndClampWindow() {
        let model = configuredModel()
        model.startFrame = 0
        model.endFrame = 80
        model.selectedWindowStart = 0
        model.selectedWindowEnd = 80
        model.currentFrame = 24

        model.setStartFrameToCurrentFrame()

        XCTAssertEqual(model.startFrame, 24)
        XCTAssertEqual(model.endFrame, 80)
        XCTAssertEqual(model.selectedWindowStart, 24)
        XCTAssertEqual(model.selectedWindowEnd, 80)

        model.currentFrame = 12
        model.setEndFrameToCurrentFrame()

        XCTAssertEqual(model.startFrame, 12)
        XCTAssertEqual(model.endFrame, 12)
        XCTAssertEqual(model.selectedWindowStart, 12)
        XCTAssertEqual(model.selectedWindowEnd, 12)
    }

    @MainActor
    func testNextProblemNavigationFindsLaterLowConfidenceFrame() {
        let model = configuredModel()
        model.trackBundles = [
            AnalysisTrackBundle(
                trackID: "primary",
                trackName: "Primary Object",
                trackKind: "primary",
                summary: nil,
                quality: nil,
                modules: [],
                analysisRows: [
                    makeRow(frame: 0, speed: 0.8, acceleration: 0.2, tracker: 0.92, scientific: 0.91),
                    makeRow(frame: 1, speed: 0.9, acceleration: 0.3, tracker: 0.88, scientific: 0.86),
                    makeRow(frame: 3, speed: 1.4, acceleration: 0.7, tracker: 0.24, scientific: 0.35, state: "suspect", reason: "confidence_drop"),
                ],
                reportMarkdown: "",
                exportDirectory: URL(fileURLWithPath: "/tmp/primary")
            )
        ]
        model.activateAnalysisTrack("primary")
        model.currentFrame = 1

        model.jumpToNextProblemFrame()

        XCTAssertEqual(model.currentFrame, 3)
        XCTAssertEqual(model.currentFrameStateText, "Suspect")
        XCTAssertEqual(model.currentFrameConfidenceText, "0.240")
        XCTAssertTrue(model.statusMessage.contains("Jumped to review frame 3"))
    }

    @MainActor
    func testTrackActivationRefreshesFrameContextAndNextCorrectionUsesActiveTrack() {
        let model = configuredModel()
        model.trackBundles = [
            AnalysisTrackBundle(
                trackID: "primary",
                trackName: "Primary Object",
                trackKind: "primary",
                summary: nil,
                quality: nil,
                modules: [],
                analysisRows: [
                    makeRow(frame: 2, speed: 1.1, acceleration: 0.4, tracker: 0.81, scientific: 0.79),
                ],
                reportMarkdown: "",
                exportDirectory: URL(fileURLWithPath: "/tmp/primary")
            ),
            AnalysisTrackBundle(
                trackID: "secondary_1",
                trackName: "Secondary Object 1",
                trackKind: "secondary",
                summary: nil,
                quality: nil,
                modules: [],
                analysisRows: [
                    makeRow(frame: 2, speed: 2.2, acceleration: 0.9, tracker: 0.74, scientific: 0.72, state: "reacquired"),
                ],
                reportMarkdown: "",
                exportDirectory: URL(fileURLWithPath: "/tmp/secondary")
            ),
        ]
        model.corrections = [
            CorrectionRecord(trackID: "primary", frameIndex: 4, note: "manual_correction", bbox: BoundingBoxDraft(x: "1", y: "1", width: "5", height: "5")),
            CorrectionRecord(trackID: "secondary_1", frameIndex: 6, note: "manual_correction", bbox: BoundingBoxDraft(x: "2", y: "2", width: "6", height: "6")),
        ]
        model.activateAnalysisTrack("secondary_1")
        model.currentFrame = 2

        XCTAssertEqual(model.currentFrameTrackName, "Secondary Object 1")
        XCTAssertEqual(model.currentFrameStateText, "Reacquired")
        XCTAssertEqual(model.currentFrameSpeedText, "2.200 m/s")
        XCTAssertEqual(model.currentFrameAccelerationText, "0.900 m/s²")

        model.jumpToNextCorrectionFrame()

        XCTAssertEqual(model.currentFrame, 6)
        XCTAssertTrue(model.statusMessage.contains("Jumped to correction frame 6"))
    }

    @MainActor
    private func configuredModel() -> AppModel {
        let model = AppModel()
        model.currentVideoURL = URL(fileURLWithPath: "/tmp/setup-review-parity.mp4")
        model.referenceLength = "1.0"
        model.unitLabel = "m"
        model.targetBox = BoundingBoxDraft(x: "10", y: "12", width: "30", height: "18")
        model.scaleLine = ScaleLineDraft(x1: "0", y1: "0", x2: "100", y2: "0")
        return model
    }

    private func makeRow(
        frame: Int,
        speed: Double,
        acceleration: Double,
        tracker: Double,
        scientific: Double,
        state: String = "tracking",
        reason: String = ""
    ) -> AnalysisRow {
        AnalysisRow(
            frameIndex: frame,
            timeSeconds: Double(frame) / 30.0,
            xUnits: Double(frame) * 0.1,
            yUnits: Double(frame) * 0.2,
            speed: speed,
            accelerationMagnitude: acceleration,
            trackerConfidence: tracker,
            scientificConfidence: scientific,
            xPixels: Double(10 + frame),
            yPixels: Double(20 + frame),
            rawXUnits: Double(frame) * 0.1,
            rawYUnits: Double(frame) * 0.2,
            xVelocity: speed * 0.5,
            yVelocity: speed * 0.4,
            xAcceleration: acceleration * 0.5,
            yAcceleration: acceleration * 0.4,
            angleDegrees: 12,
            positionUncertainty: 0.02,
            velocityUncertainty: 0.03,
            accelerationUncertainty: 0.04,
            lost: false,
            corrected: false,
            state: state,
            failureReason: reason
        )
    }
}
