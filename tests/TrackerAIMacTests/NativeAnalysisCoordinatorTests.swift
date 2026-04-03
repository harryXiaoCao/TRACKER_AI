import Foundation
import XCTest
@testable import TrackerAIMac

final class NativeAnalysisCoordinatorTests: XCTestCase {
    func testCoordinatorExportsBundleAndReloadsThroughLegacyImporter() async throws {
        let clip = try XCTUnwrap(loadBenchmarkClips().first(where: { $0.name == "marker_blur_glare" }))
        let outputDirectory = makeTemporaryOutputDirectory(name: "native-analysis-coordinator")
        defer { try? FileManager.default.removeItem(at: outputDirectory.deletingLastPathComponent()) }

        let session = makeSessionSnapshot(for: clip, endFrame: clip.startFrame + 8)
        let config = makeRunConfiguration(for: clip, session: session, outputDirectory: outputDirectory)
        let coordinator = NativeAnalysisCoordinator()
        let result: AnalysisLoadResult
        do {
            result = try await coordinator.run(config: config, preservedSession: session)
        } catch {
            try skipIfVideoDecodingUnsupported(error)
            throw error
        }

        XCTAssertEqual(result.exportDirectory, outputDirectory)
        XCTAssertFalse(result.trackBundles.isEmpty)
        XCTAssertFalse(result.analysisRows.isEmpty)
        XCTAssertEqual(result.session?.videoPath, clip.videoURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("session.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("pairwise_metrics.csv").path))

        let primaryBundle = try XCTUnwrap(result.trackBundles.first(where: { $0.trackID == "primary" }) ?? result.trackBundles.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryBundle.exportDirectory.appendingPathComponent("analysis.csv").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryBundle.exportDirectory.appendingPathComponent("report.md").path))
    }

    func testCoordinatorHonorsTaskCancellation() async throws {
        let clip = try XCTUnwrap(loadBenchmarkClips().first(where: { $0.name == "marker_blur_glare" }))
        let outputDirectory = makeTemporaryOutputDirectory(name: "native-analysis-cancel")
        defer { try? FileManager.default.removeItem(at: outputDirectory.deletingLastPathComponent()) }

        let session = makeSessionSnapshot(for: clip, endFrame: clip.startFrame + 6)
        let config = makeRunConfiguration(for: clip, session: session, outputDirectory: outputDirectory)
        let coordinator = NativeAnalysisCoordinator()

        let task = Task {
            try await coordinator.run(config: config, preservedSession: session)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected coordinator cancellation to throw.")
        } catch is CancellationError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    private func makeRunConfiguration(
        for clip: NativeBenchmarkClip,
        session: SessionSnapshot,
        outputDirectory: URL
    ) -> NativeRunConfiguration {
        NativeRunConfiguration(
            videoURL: clip.videoURL,
            outputDirectory: outputDirectory,
            targetBox: BoundingBoxDraft(
                x: String(clip.initialBBox.x),
                y: String(clip.initialBBox.y),
                width: String(clip.initialBBox.width),
                height: String(clip.initialBBox.height)
            ),
            scaleLine: ScaleLineDraft(
                x1: "0",
                y1: "0",
                x2: "100",
                y2: "0"
            ),
            referenceBox: nil,
            referenceLength: session.calibration.referenceLength,
            unitLabel: session.calibration.unitLabel,
            startFrame: session.selectedStartFrame ?? clip.startFrame,
            endFrame: session.selectedEndFrame,
            smoothingWindow: session.analysisConfig.smoothingWindow,
            polyorder: session.analysisConfig.smoothingPolyorder,
            trackingConfig: session.resolvedTrackingConfig,
            trackingProfile: session.resolvedTrackingConfig.profile ?? .auto,
            debugTracking: session.exportPreferences?.includeDebugTracking ?? false,
            includeOverlay: session.exportPreferences?.includeOverlay ?? true,
            includePlots: session.exportPreferences?.includePlots ?? true,
            reportTemplate: session.exportPreferences?.reportTemplate ?? "research",
            experimentLabel: session.metadata?.experimentLabel ?? "",
            trialID: session.metadata?.trialID ?? "",
            operatorName: session.metadata?.operatorName ?? "",
            notes: session.metadata?.notes ?? "",
            tags: session.metadata?.tags ?? [],
            additionalObjects: []
        )
    }

    private func makeSessionSnapshot(for clip: NativeBenchmarkClip, endFrame: Int) -> SessionSnapshot {
        var trackingConfig = TrackingConfigSnapshot.pythonDefaults.resolved()
        trackingConfig.profile = .marker
        trackingConfig.bidirectionalRefinement = false

        return SessionSnapshot(
            videoPath: clip.videoURL.path,
            initialBbox: clip.initialBBox,
            calibration: CalibrationSnapshot(
                referenceLength: 1.0,
                unitLabel: "m",
                pixelDistance: 100.0,
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
            trackingConfig: trackingConfig,
            metadata: ExperimentMetadataSnapshot(
                experimentLabel: "Coordinator Test",
                trialID: clip.name,
                operatorName: "Codex",
                notes: "Coordinator integration regression",
                tags: ["native", "coordinator"]
            ),
            advancedMode: true,
            selectedStartFrame: clip.startFrame,
            selectedEndFrame: endFrame,
            scalePoints: [0, 0, 100, 0],
            referenceBbox: nil,
            corrections: nil,
            reviewState: ReviewStateSnapshot(
                lastFrameIndex: clip.startFrame,
                selectedWindowStart: clip.startFrame,
                selectedWindowEnd: endFrame,
                dismissedReviewFrames: []
            ),
            eventMarkers: [
                EventMarkerSnapshot(
                    name: "start",
                    frameIndex: clip.startFrame,
                    timeS: 0,
                    value: 0,
                    unitLabel: "s",
                    axis: nil,
                    note: "native coordinator smoke test",
                    origin: "manual"
                )
            ],
            additionalObjects: [],
            trackQuality: nil,
            exportPreferences: ExportPreferencesSnapshot(
                includeOverlay: false,
                includeDebugTracking: false,
                includePlots: false,
                reportTemplate: "research"
            )
        )
    }

    private func loadBenchmarkClips() throws -> [NativeBenchmarkClip] {
        try NativeTrackingBenchmark.loadClips(
            manifestURL: try NativeTrackingBenchmark.defaultManifestURL(repositoryRoot: repositoryRoot),
            repositoryRoot: repositoryRoot
        )
    }

    private func makeTemporaryOutputDirectory(name: String) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(name, isDirectory: true)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
