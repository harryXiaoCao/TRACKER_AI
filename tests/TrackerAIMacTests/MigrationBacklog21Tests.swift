import Foundation
import XCTest
@testable import TrackerAIMac

final class MigrationBacklog21Tests: XCTestCase {
    func testSessionAndWorkspaceRoundTripSecurityScopedBookmarkMetadata() throws {
        let bridge = PythonEngineBridge()
        let directory = makeTemporaryDirectory()

        let sessionURL = directory.appendingPathComponent("session.json")
        let workspaceURL = directory.appendingPathComponent("workspace.json")

        let session = makeSessionSnapshot()
        try bridge.saveSession(session, to: sessionURL)
        let loadedSession = try bridge.loadSession(from: sessionURL)
        XCTAssertEqual(loadedSession.videoBookmarkData, "video-bookmark-token")
        XCTAssertEqual(loadedSession.bundleDirectoryBookmarkData, "bundle-bookmark-token")

        let workspace = WorkspaceSnapshot(
            title: "Bookmark Workspace",
            activeVideoPath: session.videoPath,
            items: [
                WorkspaceClip(
                    label: "bookmark-trial",
                    videoPath: session.videoPath,
                    videoBookmarkData: "video-bookmark-token",
                    sessionPath: sessionURL.path,
                    sessionBookmarkData: "session-bookmark-token",
                    notes: "sandboxed reopen"
                )
            ]
        )
        try bridge.saveWorkspace(workspace, to: workspaceURL)
        let loadedWorkspace = try bridge.loadWorkspace(from: workspaceURL)
        XCTAssertEqual(loadedWorkspace.items.first?.videoBookmarkData, "video-bookmark-token")
        XCTAssertEqual(loadedWorkspace.items.first?.sessionBookmarkData, "session-bookmark-token")
    }

    func testNativeReproductionWorkflowUsesAppLaunchInstructions() {
        let workflow = NativeReproductionWorkflow.build(
            session: makeSessionSnapshot(),
            outputDirectory: URL(fileURLWithPath: "/tmp/native-bundle", isDirectory: true),
            trackingProfile: .marker,
            includeOverlay: false,
            includePlots: false,
            debugTracking: true
        )

        XCTAssertTrue(workflow.contains("Session file: ./session.json"))
        XCTAssertTrue(workflow.contains("Source video: /tmp/bookmark-video.mp4"))
        XCTAssertTrue(workflow.contains("Reference marker bbox: 6 8 10 12"))
        XCTAssertTrue(workflow.contains("open -a TrackerAI"))
        XCTAssertFalse(workflow.contains("python3"))
        XCTAssertFalse(workflow.contains("tracker-ai"))
    }

    private func makeSessionSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/bookmark-video.mp4",
            videoBookmarkData: "video-bookmark-token",
            bundleDirectoryBookmarkData: "bundle-bookmark-token",
            initialBbox: BBoxSnapshot(x: 2, y: 4, width: 20, height: 24),
            calibration: CalibrationSnapshot(
                referenceLength: 1.0,
                unitLabel: "m",
                pixelDistance: 40,
                mode: "single_line",
                originXPx: 0,
                originYPx: 0,
                axisAngleDeg: 0,
                invertX: false,
                invertY: false,
                homography: nil,
                presetName: "bookmark"
            ),
            analysisConfig: AnalysisConfigSnapshot(
                smoothingWindow: 5,
                smoothingPolyorder: 2
            ),
            trackingConfig: TrackingConfigSnapshot(
                profile: .marker,
                robustRecovery: true,
                bidirectionalRefinement: true,
                debugTracking: true
            ),
            metadata: ExperimentMetadataSnapshot(
                experimentLabel: "Bookmark Regression",
                trialID: "bookmark-trial",
                operatorName: "Codex",
                notes: "Security-scoped metadata coverage",
                tags: ["sandbox", "native"]
            ),
            advancedMode: true,
            selectedStartFrame: 1,
            selectedEndFrame: 12,
            scalePoints: [0, 0, 40, 0],
            referenceBbox: BBoxSnapshot(x: 6, y: 8, width: 10, height: 12),
            corrections: nil,
            reviewState: nil,
            eventMarkers: nil,
            additionalObjects: nil,
            trackQuality: nil,
            exportPreferences: ExportPreferencesSnapshot(
                includeOverlay: false,
                includeDebugTracking: true,
                includePlots: false,
                reportTemplate: "research"
            )
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
