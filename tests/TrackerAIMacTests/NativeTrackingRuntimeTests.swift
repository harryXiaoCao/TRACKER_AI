import Foundation
import CoreGraphics
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

    func testSyntheticRecoveryEscalatesToFullSearchAndPreservesRecoveryMetadata() throws {
        let initialBBox = BBoxSnapshot(x: 8, y: 20, width: 14, height: 14)
        let frames = [
            makeSyntheticFrame(objectRect: CGRect(x: 8, y: 20, width: 14, height: 14)),
            makeSyntheticFrame(objectRect: nil),
            makeSyntheticFrame(objectRect: CGRect(x: 72, y: 20, width: 14, height: 14)),
            makeSyntheticFrame(objectRect: CGRect(x: 74, y: 20, width: 14, height: 14)),
            makeSyntheticFrame(objectRect: CGRect(x: 76, y: 20, width: 14, height: 14)),
        ]
        let runner = NativeSingleObjectTrackingRunner()
        let result = try runner.runSingleObjectTracking(
            frameImages: frames,
            initialBBox: initialBBox,
            config: syntheticRecoveryConfig()
        )

        XCTAssertEqual(result.observations.map(\.state), [
            NativeTrackingState.tracking.rawValue,
            NativeTrackingState.lost.rawValue,
            NativeTrackingState.suspect.rawValue,
            NativeTrackingState.reacquired.rawValue,
            NativeTrackingState.tracking.rawValue,
        ])
        XCTAssertEqual(result.observations[1].failureReason, "search_exhausted")
        XCTAssertEqual(result.observations[1].debug["search_mode"], "full")
        XCTAssertEqual(result.observations[2].debug["search_mode"], "full")
        XCTAssertEqual(result.quality.reacquisitionCount ?? -1, 1)
        XCTAssertTrue(result.quality.reviewRecommended ?? false)
        XCTAssertFalse(result.quality.lostSpans?.isEmpty ?? true)
        XCTAssertFalse(result.quality.suspectSpans?.isEmpty ?? true)

        let candidateCount = Int(result.observations[1].debug["candidate_count"] ?? "") ?? -1
        let rankingCount = result.observations[1].debug["candidate_rankings"]?
            .split(separator: "|")
            .count ?? 0
        XCTAssertGreaterThan(candidateCount, 0)
        XCTAssertLessThanOrEqual(candidateCount, 3)
        XCTAssertEqual(rankingCount, candidateCount)
    }

    func testOcclusionBenchmarkClipMarksRecoveryForReview() async throws {
        let clip = try XCTUnwrap(loadBenchmarkClips().first(where: { $0.name == "marker_occlusion_reentry" }))
        let source = try await NativeVideoSource.open(url: clip.videoURL)
        let runner = NativeSingleObjectTrackingRunner()
        let result = try runner.runSingleObjectTracking(
            video: source,
            initialBBox: clip.initialBBox,
            startFrame: clip.startFrame,
            config: TrackingConfigSnapshot.pythonDefaults.withBidirectionalRefinement(false)
        )

        XCTAssertTrue(
            result.observations.contains {
                $0.state == NativeTrackingState.suspect.rawValue ||
                $0.state == NativeTrackingState.lost.rawValue ||
                $0.state == NativeTrackingState.reacquired.rawValue
            }
        )
        XCTAssertTrue(result.quality.reviewRecommended ?? false)
        XCTAssertTrue(
            !(result.quality.lostSpans?.isEmpty ?? true) ||
            !(result.quality.suspectSpans?.isEmpty ?? true)
        )
    }

    func testRuntimeInterpolationMatchesPythonGapPenaltyAndMetadata() {
        let observations = [
            makeObservation(frameIndex: 0, x: 12, confidence: 0.9, lost: false, state: NativeTrackingState.tracking.rawValue),
            makeObservation(frameIndex: 1, x: 18, confidence: 0.2, lost: true, state: NativeTrackingState.lost.rawValue, debug: ["search_mode": "full"]),
            makeObservation(frameIndex: 2, x: 24, confidence: 0.1, lost: true, state: NativeTrackingState.lost.rawValue, debug: ["search_mode": "full"]),
            makeObservation(frameIndex: 3, x: 30, confidence: 0.8, lost: false, state: NativeTrackingState.tracking.rawValue)
        ]

        let interpolated = NativeTrackRuntimeDerivation.interpolateShortGaps(
            observations,
            config: TrackingConfigSnapshot.pythonDefaults
        )

        XCTAssertEqual(interpolated[1].frameIndex, 1)
        XCTAssertEqual(interpolated[2].frameIndex, 2)
        XCTAssertFalse(interpolated[1].lost)
        XCTAssertFalse(interpolated[2].lost)
        XCTAssertEqual(interpolated[1].state, NativeTrackingState.suspect.rawValue)
        XCTAssertEqual(interpolated[2].state, NativeTrackingState.suspect.rawValue)
        XCTAssertEqual(interpolated[1].failureReason, "short_gap_interpolated")
        XCTAssertEqual(interpolated[2].failureReason, "short_gap_interpolated")
        XCTAssertEqual(interpolated[1].source, "interpolated")
        XCTAssertEqual(interpolated[2].source, "interpolated")
        XCTAssertTrue(interpolated[1].isInterpolated)
        XCTAssertTrue(interpolated[2].isInterpolated)
        XCTAssertEqual(interpolated[1].debug["interpolation"], "linear_short_gap")
        XCTAssertEqual(interpolated[2].debug["interpolation"], "linear_short_gap")
        XCTAssertEqual(interpolated[1].confidence, 0.576, accuracy: 1e-12)
        XCTAssertEqual(interpolated[2].confidence, 0.576, accuracy: 1e-12)
        XCTAssertEqual(interpolated[1].centroidXPixels, 18, accuracy: 1e-12)
        XCTAssertEqual(interpolated[2].centroidXPixels, 24, accuracy: 1e-12)
    }

    func testRuntimeQualityMetadataBuildsPythonParitySpans() {
        let observations = [
            makeObservation(frameIndex: 0, x: 10, confidence: 0.95, lost: false, state: NativeTrackingState.tracking.rawValue),
            makeObservation(frameIndex: 1, x: 14, confidence: 0.22, lost: true, state: NativeTrackingState.lost.rawValue),
            makeObservation(frameIndex: 2, x: 18, confidence: 0.58, lost: false, corrected: false, state: NativeTrackingState.suspect.rawValue),
            makeObservation(frameIndex: 3, x: 22, confidence: 0.81, lost: false, corrected: false, state: NativeTrackingState.reacquired.rawValue),
            makeObservation(frameIndex: 4, x: 26, confidence: 0.92, lost: false, corrected: true, state: NativeTrackingState.tracking.rawValue),
            makeObservation(frameIndex: 5, x: 30, confidence: 0.31, lost: false, corrected: true, state: NativeTrackingState.tracking.rawValue)
        ]

        let quality = NativeTrackRuntimeDerivation.computeQualityMetadata(observations: observations)

        XCTAssertEqual(quality.lostSpans?.map(\.startFrame), [1])
        XCTAssertEqual(quality.lostSpans?.map(\.endFrame), [1])
        XCTAssertEqual(quality.lostSpans?.first?.reason, "lost_tracking")
        XCTAssertEqual(quality.suspectSpans?.map(\.startFrame), [2])
        XCTAssertEqual(quality.suspectSpans?.map(\.endFrame), [3])
        XCTAssertEqual(quality.suspectSpans?.first?.reason, "tracking_recovery")
        XCTAssertEqual(quality.correctedSpans?.map(\.startFrame), [4])
        XCTAssertEqual(quality.correctedSpans?.map(\.endFrame), [5])
        XCTAssertEqual(quality.correctedSpans?.first?.reason, "manual_correction")
        XCTAssertEqual(quality.reacquisitionCount, 1)
        XCTAssertEqual(quality.reviewRecommended, true)
    }

    func testReconstructionRespectsInterpolationGapLimitFromTrackingConfig() {
        var config = TrackingConfigSnapshot.pythonDefaults
        config.maxInterpolationGap = 1
        let session = makeSessionSnapshot(trackingConfig: config)
        let bundle = AnalysisTrackBundle(
            trackID: "primary",
            trackName: "Primary Object",
            trackKind: "primary",
            summary: nil,
            quality: nil,
            modules: [],
            analysisRows: [
                makeAnalysisRow(frameIndex: 0, xPixels: 12, trackerConfidence: 0.9, lost: false, state: "tracking"),
                makeAnalysisRow(frameIndex: 1, xPixels: 18, trackerConfidence: 0.2, lost: true, state: "lost", failureReason: "search_exhausted"),
                makeAnalysisRow(frameIndex: 2, xPixels: 24, trackerConfidence: 0.2, lost: true, state: "lost", failureReason: "search_exhausted"),
                makeAnalysisRow(frameIndex: 3, xPixels: 30, trackerConfidence: 0.85, lost: false, state: "tracking")
            ],
            reportMarkdown: "",
            exportDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        let reconstruction = NativeTrackingPipeline().reconstructTrack(bundle: bundle, session: session)

        XCTAssertEqual(reconstruction?.observations.map(\.lost), [false, true, true, false])
        XCTAssertEqual(reconstruction?.quality.lostSpans?.map(\.startFrame), [1])
        XCTAssertEqual(reconstruction?.quality.lostSpans?.map(\.endFrame), [2])
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

    private func syntheticRecoveryConfig() -> TrackingConfigSnapshot {
        var config = TrackingConfigSnapshot.pythonDefaults.resolved()
        config.profile = .marker
        config.bidirectionalRefinement = false
        config.debugTracking = true
        config.searchMargin = 0.35
        config.expandedSearchMargin = 0.80
        config.lowConfidenceThreshold = 0.35
        config.reacquireThreshold = 0.55
        config.suspectAfterFrames = 1
        config.recoveryAfterFrames = 0
        config.maxPredictionFrames = 1
        config.interpolateShortGaps = false
        return config
    }

    private func makeSyntheticFrame(
        width: Int = 96,
        height: Int = 64,
        objectRect: CGRect?,
        objectColor: (UInt8, UInt8, UInt8) = (32, 220, 96)
    ) -> CGImage {
        var rgba = Array(repeating: UInt8.zero, count: width * height * 4)

        if let objectRect {
            let x0 = max(0, min(width - 1, Int(objectRect.minX.rounded(.down))))
            let y0 = max(0, min(height - 1, Int(objectRect.minY.rounded(.down))))
            let x1 = max(x0 + 1, min(width, Int(objectRect.maxX.rounded(.up))))
            let y1 = max(y0 + 1, min(height, Int(objectRect.maxY.rounded(.up))))
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let base = ((y * width) + x) * 4
                    rgba[base] = objectColor.0
                    rgba[base + 1] = objectColor.1
                    rgba[base + 2] = objectColor.2
                    rgba[base + 3] = 255
                }
            }

            let inset = max(2, min(x1 - x0, y1 - y0) / 4)
            if x0 + inset < x1 - inset, y0 + inset < y1 - inset {
                for y in (y0 + inset)..<(y1 - inset) {
                    for x in (x0 + inset)..<(x1 - inset) {
                        let base = ((y * width) + x) * 4
                        rgba[base] = 255
                        rgba[base + 1] = 255
                        rgba[base + 2] = 255
                        rgba[base + 3] = 255
                    }
                }
            }

            let centerX = (x0 + x1) / 2
            let centerY = (y0 + y1) / 2
            for y in max(y0, centerY - 1)..<min(y1, centerY + 2) {
                for x in max(x0, centerX - 1)..<min(x1, centerX + 2) {
                    let base = ((y * width) + x) * 4
                    rgba[base] = 16
                    rgba[base + 1] = 16
                    rgba[base + 2] = 16
                    rgba[base + 3] = 255
                }
            }
        }

        let data = Data(rgba)
        let provider = CGDataProvider(data: data as CFData)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func makeObservation(
        frameIndex: Int,
        x: Double,
        confidence: Double,
        lost: Bool,
        corrected: Bool = false,
        state: String,
        debug: [String: String] = [:]
    ) -> NativeTrackingObservation {
        NativeTrackingObservation(
            frameIndex: frameIndex,
            timeSeconds: Double(frameIndex) / 30.0,
            centroidXPixels: x,
            centroidYPixels: 20,
            bbox: BBoxSnapshot(x: x - 3, y: 17, width: 6, height: 6),
            confidence: confidence,
            lost: lost,
            corrected: corrected,
            state: state,
            failureReason: lost ? "search_exhausted" : nil,
            source: lost ? "predicted" : "measured",
            isInferred: lost,
            isInterpolated: false,
            debug: debug
        )
    }

    private func makeAnalysisRow(
        frameIndex: Int,
        xPixels: Double,
        trackerConfidence: Double,
        lost: Bool,
        state: String,
        failureReason: String = "",
        corrected: Bool = false
    ) -> AnalysisRow {
        AnalysisRow(
            frameIndex: frameIndex,
            timeSeconds: Double(frameIndex) / 30.0,
            xUnits: xPixels / 10.0,
            yUnits: 2.0,
            speed: 0,
            accelerationMagnitude: 0,
            trackerConfidence: trackerConfidence,
            scientificConfidence: trackerConfidence,
            xPixels: xPixels,
            yPixels: 20,
            rawXUnits: nil,
            rawYUnits: nil,
            xVelocity: nil,
            yVelocity: nil,
            xAcceleration: nil,
            yAcceleration: nil,
            angleDegrees: nil,
            positionUncertainty: nil,
            velocityUncertainty: nil,
            accelerationUncertainty: nil,
            lost: lost,
            corrected: corrected,
            state: state,
            failureReason: failureReason
        )
    }

    private func makeSessionSnapshot(trackingConfig: TrackingConfigSnapshot) -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/demo.mp4",
            initialBbox: BBoxSnapshot(x: 9, y: 17, width: 6, height: 6),
            calibration: CalibrationSnapshot(
                referenceLength: 1.0,
                unitLabel: "m",
                pixelDistance: 100.0,
                mode: nil,
                originXPx: nil,
                originYPx: nil,
                axisAngleDeg: nil,
                invertX: nil,
                invertY: nil,
                homography: nil,
                presetName: nil
            ),
            analysisConfig: AnalysisConfigSnapshot(smoothingWindow: 7, smoothingPolyorder: 2),
            trackingConfig: trackingConfig,
            metadata: nil,
            advancedMode: nil,
            selectedStartFrame: 0,
            selectedEndFrame: 3,
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
