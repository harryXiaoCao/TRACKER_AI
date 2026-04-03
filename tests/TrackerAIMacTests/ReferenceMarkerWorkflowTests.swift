import CoreGraphics
import Foundation
import XCTest
@testable import TrackerAIMac

final class ReferenceMarkerWorkflowTests: XCTestCase {
    @MainActor
    func testReferenceMarkerWorkflowDrawsAndClearsReferenceBox() {
        let model = AppModel()

        model.startReferenceDrawing()
        XCTAssertEqual(model.annotationMode, .reference)
        XCTAssertEqual(model.referenceMarkerStatus, "Drawing")

        model.applyDrawnReferenceBox(CGRect(x: 12, y: 18, width: 26, height: 32))

        XCTAssertEqual(model.annotationMode, .idle)
        XCTAssertTrue(model.isReferenceReady)
        XCTAssertEqual(model.referenceBox.x, "12.0")
        XCTAssertEqual(model.referenceBox.y, "18.0")
        XCTAssertEqual(model.referenceBox.width, "26.0")
        XCTAssertEqual(model.referenceBox.height, "32.0")
        XCTAssertEqual(model.referenceMarkerStatus, "Ready")

        model.clearReferenceBox()

        XCTAssertFalse(model.isReferenceReady)
        XCTAssertEqual(model.referenceBox, BoundingBoxDraft())
        XCTAssertEqual(model.referenceMarkerStatus, "Optional")
    }

    @MainActor
    func testBuildSessionSnapshotPersistsReferenceBBox() throws {
        let model = configuredModel()

        let session = try model.buildSessionSnapshot(videoURL: URL(fileURLWithPath: "/tmp/reference-workflow.mp4"))

        XCTAssertEqual(session.referenceBbox?.x, 20)
        XCTAssertEqual(session.referenceBbox?.y, 24)
        XCTAssertEqual(session.referenceBbox?.width, 36)
        XCTAssertEqual(session.referenceBbox?.height, 18)
    }

    @MainActor
    func testApplySessionHydratesAndClearsReferenceMarker() {
        let model = AppModel()
        let sessionURL = URL(fileURLWithPath: "/tmp/reference-session.json")

        model.referenceBox = BoundingBoxDraft(x: "1", y: "2", width: "3", height: "4")
        model.apply(session: makeSession(referenceBox: BBoxSnapshot(x: 7, y: 8, width: 9, height: 10)), sessionURL: sessionURL, loadBundle: false)

        XCTAssertTrue(model.isReferenceReady)
        XCTAssertEqual(model.referenceBox.x, "7.0")
        XCTAssertEqual(model.referenceBox.y, "8.0")
        XCTAssertEqual(model.referenceBox.width, "9.0")
        XCTAssertEqual(model.referenceBox.height, "10.0")

        model.apply(session: makeSession(referenceBox: nil), sessionURL: sessionURL, loadBundle: false)

        XCTAssertFalse(model.isReferenceReady)
        XCTAssertEqual(model.referenceBox, BoundingBoxDraft())
    }

    @MainActor
    func testRunConfigurationAndNativeExportCarryReferenceMarker() throws {
        let model = AppModel()
        let session = makeSession(referenceBox: BBoxSnapshot(x: 14, y: 16, width: 28, height: 30))
        let outputDirectory = makeTemporaryDirectory()

        let configuration = try model.runConfiguration(from: session, outputDirectory: outputDirectory)
        XCTAssertEqual(configuration.referenceBox?.x, "14.0")
        XCTAssertEqual(configuration.referenceBox?.y, "16.0")
        XCTAssertEqual(configuration.referenceBox?.width, "28.0")
        XCTAssertEqual(configuration.referenceBox?.height, "30.0")

        let exporter = NativeResearchBundleExporter()
        let payload = NativeResearchBundlePayload(
            session: session,
            trackID: "primary",
            trackName: "Primary Object",
            analysisRows: sampleRows(),
            pairwiseMetrics: [],
            eventMarkers: [],
            outputDirectory: outputDirectory,
            reportTemplate: "research",
            trackingProfile: .marker,
            includeOverlay: true,
            includePlots: true,
            debugTracking: false,
            summary: nil,
            quality: nil,
            modules: []
        )

        _ = try exporter.export(payload)

        let bridge = PythonEngineBridge()
        let savedSession = try bridge.loadSession(from: outputDirectory.appendingPathComponent("session.json"))
        XCTAssertEqual(savedSession.referenceBbox?.x, 14)
        XCTAssertEqual(savedSession.referenceBbox?.y, 16)
        XCTAssertEqual(savedSession.referenceBbox?.width, 28)
        XCTAssertEqual(savedSession.referenceBbox?.height, 30)

        let reproduceCommand = try String(contentsOf: outputDirectory.appendingPathComponent("reproduce_command.sh"), encoding: .utf8)
        XCTAssertTrue(reproduceCommand.contains("Reference marker bbox: 14 16 28 30"))
        XCTAssertTrue(reproduceCommand.contains("open -a TrackerAI"))
        XCTAssertFalse(reproduceCommand.contains("python3"))

        let reportMarkdown = try String(contentsOf: outputDirectory.appendingPathComponent("report.md"), encoding: .utf8)
        XCTAssertTrue(reportMarkdown.contains("Reference marker enabled: `true`"))
    }

    @MainActor
    private func configuredModel() -> AppModel {
        let model = AppModel()
        model.referenceLength = "1.5"
        model.unitLabel = "m"
        model.targetBox = BoundingBoxDraft(x: "10", y: "12", width: "42", height: "24")
        model.scaleLine = ScaleLineDraft(x1: "0", y1: "0", x2: "100", y2: "0")
        model.referenceBox = BoundingBoxDraft(x: "20", y: "24", width: "36", height: "18")
        model.trackingProfile = .marker
        return model
    }

    private func makeSession(referenceBox: BBoxSnapshot?) -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/reference-source.mp4",
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
            trackingConfig: TrackingConfigSnapshot(
                profile: .marker,
                robustRecovery: true,
                bidirectionalRefinement: true,
                debugTracking: false
            ),
            metadata: ExperimentMetadataSnapshot(
                experimentLabel: "Reference Session",
                trialID: "trial-reference",
                operatorName: "tester",
                notes: "Reference regression",
                tags: ["reference", "swift"]
            ),
            advancedMode: true,
            selectedStartFrame: 3,
            selectedEndFrame: 12,
            scalePoints: [0, 0, 50, 0],
            referenceBbox: referenceBox,
            corrections: nil,
            reviewState: nil,
            eventMarkers: nil,
            additionalObjects: nil,
            trackQuality: nil,
            exportPreferences: ExportPreferencesSnapshot(
                includeOverlay: true,
                includeDebugTracking: false,
                includePlots: true,
                reportTemplate: "research"
            )
        )
    }

    private func sampleRows() -> [AnalysisRow] {
        [
            AnalysisRow(
                frameIndex: 3,
                timeSeconds: 0.1,
                xUnits: 0.2,
                yUnits: 0.4,
                speed: 1.0,
                accelerationMagnitude: 0.5,
                trackerConfidence: 0.94,
                scientificConfidence: 0.91,
                xPixels: 14,
                yPixels: 16
            ),
            AnalysisRow(
                frameIndex: 4,
                timeSeconds: 0.133,
                xUnits: 0.24,
                yUnits: 0.45,
                speed: 1.1,
                accelerationMagnitude: 0.55,
                trackerConfidence: 0.95,
                scientificConfidence: 0.92,
                xPixels: 15,
                yPixels: 17
            ),
        ]
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
