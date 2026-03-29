import Foundation
import XCTest
@testable import TrackerAIMac

final class NativeTrackingRuntimeTests: XCTestCase {
    func testNativeTrackerPreservesObservationMetadataAndFrameRange() async throws {
        let clip = try XCTUnwrap(loadBenchmarkClips().first(where: { $0.name == "marker_blur_glare" }))
        let source = try await NativeVideoSource.open(url: clip.videoURL)
        let runner = NativeSingleObjectTrackingRunner()
        let forwardOnlyConfig = TrackingConfigSnapshot.pythonDefaults
            .withBidirectionalRefinement(false)

        let result = try runner.runSingleObjectTracking(
            video: source,
            initialBBox: clip.initialBBox,
            startFrame: clip.startFrame,
            endFrame: clip.startFrame + 12,
            config: forwardOnlyConfig,
            trackID: "primary",
            trackName: "Primary Object",
            trackKind: "primary"
        )

        XCTAssertEqual(result.startFrame, clip.startFrame)
        XCTAssertEqual(result.endFrame, clip.startFrame + 12)
        XCTAssertEqual(result.observations.first?.frameIndex, clip.startFrame)
        XCTAssertEqual(result.observations.last?.frameIndex, clip.startFrame + 12)
        XCTAssertEqual(result.observations.first?.trackID, "primary")
        XCTAssertEqual(result.observations.first?.trackName, "Primary Object")
        XCTAssertEqual(result.observations.first?.trackKind, "primary")
        XCTAssertEqual(result.observations.first?.confidence ?? -1, 1.0, accuracy: 1e-12)
        XCTAssertEqual(result.observations.first?.state, NativeTrackingState.tracking.rawValue)
        XCTAssertFalse(result.observations.contains { $0.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertEqual(result.quality.reviewRecommended, false)
    }

    func testNativeTrackerMeetsBenchmarkReleaseGateTargets() async throws {
        let clips = Dictionary(uniqueKeysWithValues: try loadBenchmarkClips().map { ($0.name, $0) })
        let runner = NativeSingleObjectTrackingRunner()
        let forwardOnlyConfig = TrackingConfigSnapshot.pythonDefaults
            .withBidirectionalRefinement(false)

        for target in NativeTrackingParityTargets.benchmarkReleaseGate {
            let clip = try XCTUnwrap(clips[target.clipName], "Missing benchmark clip \(target.clipName)")
            let source = try await NativeVideoSource.open(url: clip.videoURL)
            let result = try runner.runSingleObjectTracking(
                video: source,
                initialBBox: clip.initialBBox,
                startFrame: clip.startFrame,
                config: forwardOnlyConfig
            )
            let metrics = evaluate(track: result, against: clip)

            XCTAssertLessThanOrEqual(
                metrics.p95CenterErrorPixels,
                target.maxP95CenterErrorPixels,
                "P95 center error regression for \(target.clipName)"
            )
            XCTAssertLessThanOrEqual(
                metrics.lostFrameRate,
                target.maxLostFrameRate,
                "Lost-frame regression for \(target.clipName)"
            )
            XCTAssertLessThanOrEqual(
                metrics.reacquisitionLatencyFrames,
                target.maxReacquisitionLatencyFrames,
                "Reacquisition latency regression for \(target.clipName)"
            )
        }
    }

    private func loadBenchmarkClips() throws -> [BenchmarkClipFixture] {
        let manifestURL = repositoryRoot.appendingPathComponent("sample_data/benchmark_manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BenchmarkManifestFixture.self, from: data)
        return manifest.clips.map { clip in
            BenchmarkClipFixture(
                name: clip.name,
                videoURL: repositoryRoot.appendingPathComponent("sample_data").appendingPathComponent(clip.videoPath),
                startFrame: clip.startFrame,
                initialBBox: BBoxSnapshot(
                    x: clip.initialBBox[0],
                    y: clip.initialBBox[1],
                    width: clip.initialBBox[2],
                    height: clip.initialBBox[3]
                ),
                annotations: clip.annotations.map {
                    BenchmarkAnnotationFixture(
                        frameIndex: $0.frameIndex,
                        centroidX: $0.centroidXPx,
                        centroidY: $0.centroidYPx,
                        bbox: BBoxSnapshot(
                            x: $0.bbox[0],
                            y: $0.bbox[1],
                            width: $0.bbox[2],
                            height: $0.bbox[3]
                        )
                    )
                }
            )
        }
    }

    private func evaluate(
        track: NativeTrackResult,
        against clip: BenchmarkClipFixture
    ) -> NativeBenchmarkMetricsFixture {
        let observationByFrame = track.observationByFrame()
        var centerErrors: [Double] = []
        var lostFrames = 0
        var annotatedIndices: [Int] = []

        for annotation in clip.annotations {
            guard let observation = observationByFrame[annotation.frameIndex] else { continue }
            annotatedIndices.append(annotation.frameIndex)
            centerErrors.append(
                hypot(
                    observation.centroidXPixels - annotation.centroidX,
                    observation.centroidYPixels - annotation.centroidY
                )
            )
            if observation.lost {
                lostFrames += 1
            }
        }

        let sortedIndices = annotatedIndices.sorted()
        var reacquisitionLatency = 0
        if let first = sortedIndices.first, let last = sortedIndices.last {
            var lostStart: Int?
            for frameIndex in first...last {
                guard let observation = observationByFrame[frameIndex] else { continue }
                if observation.lost, lostStart == nil {
                    lostStart = frameIndex
                } else if let start = lostStart, !observation.lost {
                    reacquisitionLatency = max(reacquisitionLatency, frameIndex - start)
                    lostStart = nil
                }
            }
        }

        return NativeBenchmarkMetricsFixture(
            p95CenterErrorPixels: percentile(values: centerErrors, quantile: 0.95),
            lostFrameRate: centerErrors.isEmpty ? 1.0 : Double(lostFrames) / Double(centerErrors.count),
            reacquisitionLatencyFrames: reacquisitionLatency
        )
    }

    private func percentile(values: [Double], quantile: Double) -> Double {
        guard let first = values.sorted().first else { return 0 }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return first }
        let position = max(0.0, min(Double(sorted.count - 1), Double(sorted.count - 1) * quantile))
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }
        let alpha = position - Double(lowerIndex)
        return sorted[lowerIndex] + ((sorted[upperIndex] - sorted[lowerIndex]) * alpha)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension TrackingConfigSnapshot {
    func withBidirectionalRefinement(_ enabled: Bool) -> TrackingConfigSnapshot {
        var copy = self
        copy.bidirectionalRefinement = enabled
        return copy.resolved()
    }
}

private struct NativeBenchmarkMetricsFixture {
    var p95CenterErrorPixels: Double
    var lostFrameRate: Double
    var reacquisitionLatencyFrames: Int
}

private struct BenchmarkClipFixture {
    var name: String
    var videoURL: URL
    var startFrame: Int
    var initialBBox: BBoxSnapshot
    var annotations: [BenchmarkAnnotationFixture]
}

private struct BenchmarkAnnotationFixture {
    var frameIndex: Int
    var centroidX: Double
    var centroidY: Double
    var bbox: BBoxSnapshot
}

private struct BenchmarkManifestFixture: Decodable {
    var clips: [BenchmarkManifestClipFixture]
}

private struct BenchmarkManifestClipFixture: Decodable {
    var name: String
    var videoPath: String
    var startFrame: Int
    var initialBBox: [Double]
    var annotations: [BenchmarkManifestAnnotationFixture]

    enum CodingKeys: String, CodingKey {
        case name
        case videoPath = "video_path"
        case startFrame = "start_frame"
        case initialBBox = "initial_bbox"
        case annotations
    }
}

private struct BenchmarkManifestAnnotationFixture: Decodable {
    var frameIndex: Int
    var centroidXPx: Double
    var centroidYPx: Double
    var bbox: [Double]

    enum CodingKeys: String, CodingKey {
        case frameIndex = "frame_index"
        case centroidXPx = "centroid_x_px"
        case centroidYPx = "centroid_y_px"
        case bbox
    }
}
