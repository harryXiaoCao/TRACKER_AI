import Foundation
import XCTest
@testable import TrackerAIMac

final class NativeBatchCoordinatorTests: XCTestCase {
    func testBatchCoordinatorRunsMixedSessionsAndExportsAggregateArtifacts() async throws {
        let clip = try XCTUnwrap(loadBenchmarkClips().first(where: { $0.name == "marker_blur_glare" }))
        let outputRoot = makeTemporaryOutputDirectory(name: "native-batch-coordinator")
        defer { try? FileManager.default.removeItem(at: outputRoot.deletingLastPathComponent()) }

        let singleSession = makeSessionSnapshot(
            for: clip,
            trialID: "single trial",
            endFrame: clip.startFrame + 6,
            additionalObjects: []
        )
        let multiSession = makeSessionSnapshot(
            for: clip,
            trialID: "multi trial",
            endFrame: clip.startFrame + 6,
            additionalObjects: [
                AdditionalObjectSnapshot(
                    trackID: "secondary_1",
                    name: "Secondary Object 1",
                    kind: "secondary",
                    bbox: BBoxSnapshot(
                        x: clip.initialBBox.x + 18,
                        y: clip.initialBBox.y + 6,
                        width: clip.initialBBox.width,
                        height: clip.initialBBox.height
                    )
                )
            ]
        )

        let entries = [
            NativeBatchSessionEntry(
                clip: WorkspaceClip(label: "single", videoPath: clip.videoURL.path),
                session: singleSession
            ),
            NativeBatchSessionEntry(
                clip: WorkspaceClip(label: "multi", videoPath: clip.videoURL.path),
                session: multiSession
            ),
        ]

        let coordinator = NativeBatchCoordinator()
        let result: NativeBatchCoordinatorResult
        do {
            result = try await coordinator.run(
                entries: entries,
                outputRoot: outputRoot,
                makeRunConfiguration: { entry, directory in
                    self.makeRunConfiguration(for: entry.session, outputDirectory: directory)
                },
                postProcess: { loadResult, session in
                    var merged = loadResult
                    merged.session = session
                    return merged
                }
            )
        } catch {
            try skipIfVideoDecodingUnsupported(error)
            throw error
        }

        XCTAssertEqual(result.aggregate.trialCount, 2)
        XCTAssertEqual(Set(result.trials.map(\.trialID)), ["single_trial", "multi_trial"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("batch_summary.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("batch_comparison.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("batch_report.md").path))

        let singleDirectory = try XCTUnwrap(result.trialDirectories["single_trial"])
        let multiDirectory = try XCTUnwrap(result.trialDirectories["multi_trial"])
        XCTAssertTrue(fileExists(in: singleDirectory, candidates: [
            "analysis.csv",
            "primary/analysis.csv",
        ]))
        XCTAssertTrue(fileExists(in: singleDirectory, candidates: [
            "reproduce_command.sh",
            "primary/reproduce_command.sh",
        ]))
        XCTAssertTrue(fileExists(in: singleDirectory, candidates: [
            "experiment_manifest.json",
            "primary/experiment_manifest.json",
        ]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: multiDirectory.appendingPathComponent("primary/analysis.csv").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: multiDirectory.appendingPathComponent("secondary_1/analysis.csv").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: multiDirectory.appendingPathComponent("pairwise_metrics.csv").path))
    }

    private func makeRunConfiguration(
        for session: SessionSnapshot,
        outputDirectory: URL
    ) -> NativeRunConfiguration {
        let scale = session.scalePoints ?? [0, 0, 100, 0]
        return NativeRunConfiguration(
            videoURL: URL(fileURLWithPath: session.videoPath),
            outputDirectory: outputDirectory,
            targetBox: BoundingBoxDraft(
                x: String(session.initialBbox.x),
                y: String(session.initialBbox.y),
                width: String(session.initialBbox.width),
                height: String(session.initialBbox.height)
            ),
            scaleLine: ScaleLineDraft(
                x1: String(scale[0]),
                y1: String(scale[1]),
                x2: String(scale[2]),
                y2: String(scale[3])
            ),
            referenceBox: session.referenceBbox.map {
                BoundingBoxDraft(
                    x: String($0.x),
                    y: String($0.y),
                    width: String($0.width),
                    height: String($0.height)
                )
            },
            referenceLength: session.calibration.referenceLength,
            unitLabel: session.calibration.unitLabel,
            startFrame: session.selectedStartFrame ?? 0,
            endFrame: session.selectedEndFrame,
            smoothingWindow: session.analysisConfig.smoothingWindow,
            polyorder: session.analysisConfig.smoothingPolyorder,
            trackingConfig: session.resolvedTrackingConfig,
            trackingProfile: session.resolvedTrackingConfig.profile ?? .auto,
            debugTracking: session.exportPreferences?.includeDebugTracking ?? false,
            includeOverlay: session.exportPreferences?.includeOverlay ?? false,
            includePlots: session.exportPreferences?.includePlots ?? false,
            reportTemplate: session.exportPreferences?.reportTemplate ?? "research",
            experimentLabel: session.metadata?.experimentLabel ?? "",
            trialID: session.metadata?.trialID ?? "",
            operatorName: session.metadata?.operatorName ?? "",
            notes: session.metadata?.notes ?? "",
            tags: session.metadata?.tags ?? [],
            additionalObjects: (session.additionalObjects ?? []).map { object in
                AdditionalObjectDraft(
                    trackID: object.trackID,
                    name: object.name,
                    kind: object.kind ?? "secondary",
                    x: String(object.bbox.x),
                    y: String(object.bbox.y),
                    width: String(object.bbox.width),
                    height: String(object.bbox.height)
                )
            }
        )
    }

    private func makeSessionSnapshot(
        for clip: NativeBenchmarkClip,
        trialID: String,
        endFrame: Int,
        additionalObjects: [AdditionalObjectSnapshot]
    ) -> SessionSnapshot {
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
                experimentLabel: "Batch Coordinator Test",
                trialID: trialID,
                operatorName: "Codex",
                notes: "Batch coordinator regression",
                tags: ["native", "batch"]
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
                    note: "batch coordinator smoke test",
                    origin: "manual"
                )
            ],
            additionalObjects: additionalObjects,
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

    private func fileExists(in directory: URL, candidates: [String]) -> Bool {
        candidates.contains { candidate in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path)
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
