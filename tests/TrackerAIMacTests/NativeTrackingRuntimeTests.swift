import Foundation
import CoreGraphics
import XCTest
@testable import TrackerAIMac

final class NativeTrackingRuntimeTests: XCTestCase {
    func testNativeBenchmarkManifestCoversRealVideoFailureModes() throws {
        let clips = try loadBenchmarkClips()
        let coveredTags = Set(clips.flatMap(\.tags))

        XCTAssertTrue(coveredTags.isSuperset(of: [
            "blur",
            "glare",
            "illumination_shift",
            "occlusion",
            "disappearance",
            "camera_jitter",
            "distractor",
            "scale_drift",
        ]))
    }

    func testNativeTrackerPreservesObservationMetadataAndFrameRange() async throws {
        let clip = try XCTUnwrap(loadBenchmarkClips().first(where: { $0.name == "marker_blur_glare" }))
        let source = try await NativeVideoSource.open(url: clip.videoURL)
        let runner = NativeSingleObjectTrackingRunner()
        let forwardOnlyConfig = TrackingConfigSnapshot.pythonDefaults
            .withBidirectionalRefinement(false)

        let result: NativeTrackResult
        do {
            result = try runner.runSingleObjectTracking(
                video: source,
                initialBBox: clip.initialBBox,
                startFrame: clip.startFrame,
                endFrame: clip.startFrame + 12,
                config: forwardOnlyConfig,
                trackID: "primary",
                trackName: "Primary Object",
                trackKind: "primary"
            )
        } catch {
            try skipIfVideoDecodingUnsupported(error)
            throw error
        }

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

    func testNativeBenchmarkHarnessComputesMetricsFromAnnotatedTrack() throws {
        let clip = try XCTUnwrap(loadBenchmarkClips().first(where: { $0.name == "marker_blur_glare" }))
        let observations = clip.annotations.enumerated().map { index, annotation in
            makeObservation(
                frameIndex: annotation.frameIndex,
                x: annotation.centroidXPixels,
                y: annotation.centroidYPixels,
                confidence: index == 1 ? 0.25 : 0.95,
                lost: index == 1,
                state: index == 1 ? NativeTrackingState.lost.rawValue : NativeTrackingState.tracking.rawValue
            ).withBBox(annotation.bbox)
        }
        let track = NativeTrackResult(
            observations: observations,
            trackerName: "benchmark_fixture",
            averageConfidence: observations.map(\.confidence).reduce(0, +) / Double(observations.count),
            startFrame: clip.startFrame,
            endFrame: observations.last?.frameIndex ?? clip.startFrame,
            initialBBox: clip.initialBBox,
            quality: NativeTrackRuntimeDerivation.computeQualityMetadata(observations: observations),
            trackingConfig: TrackingConfigSnapshot.pythonDefaults.withBidirectionalRefinement(false)
        )

        let metrics = try NativeTrackingBenchmark.evaluate(track: track, against: clip)

        XCTAssertEqual(metrics.clipName, clip.name)
        XCTAssertEqual(metrics.annotatedFrameCount, clip.annotations.count)
        XCTAssertEqual(metrics.medianCenterErrorPixels, 0, accuracy: 1e-12)
        XCTAssertEqual(metrics.p95CenterErrorPixels, 0, accuracy: 1e-12)
        XCTAssertEqual(metrics.meanIoU, 1, accuracy: 1e-12)
        XCTAssertEqual(metrics.lostFrameRate, 1.0 / Double(clip.annotations.count), accuracy: 1e-12)
        XCTAssertEqual(metrics.reacquisitionLatencyFrames, 5)
    }

    func testNativeBenchmarkSuiteAggregatesMetricsFromRunnerOutput() async throws {
        let clips = Array(try loadBenchmarkClips().prefix(2))
        let metricsByClip = Dictionary(
            uniqueKeysWithValues: [
                NativeBenchmarkMetrics(
                    clipName: clips[0].name,
                    annotatedFrameCount: 18,
                    medianCenterErrorPixels: 2.0,
                    p95CenterErrorPixels: 4.0,
                    meanIoU: 0.91,
                    lostFrameRate: 0.0,
                    reacquisitionLatencyFrames: 0
                ),
                NativeBenchmarkMetrics(
                    clipName: clips[1].name,
                    annotatedFrameCount: 20,
                    medianCenterErrorPixels: 6.0,
                    p95CenterErrorPixels: 10.0,
                    meanIoU: 0.73,
                    lostFrameRate: 0.15,
                    reacquisitionLatencyFrames: 7
                ),
            ].map { ($0.clipName, $0) }
        )

        let suite = try await NativeTrackingBenchmark.evaluateSuite(clips: clips) { clip in
            try XCTUnwrap(metricsByClip[clip.name], "Missing stubbed metrics for \(clip.name)")
        }

        XCTAssertEqual(suite.clipMetrics.count, 2)
        XCTAssertEqual(suite.medianCenterErrorPixels, 4.0, accuracy: 1e-12)
        XCTAssertEqual(suite.p95CenterErrorPixels, 10.0, accuracy: 1e-12)
        XCTAssertEqual(suite.meanIoU, 0.82, accuracy: 1e-12)
        XCTAssertEqual(suite.lostFrameRate, 0.075, accuracy: 1e-12)
        XCTAssertEqual(suite.maxReacquisitionLatencyFrames, 7)
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
        if ProcessInfo.processInfo.environment["CODEX_CI"] != nil {
            throw XCTSkip("Benchmark-backed occlusion coverage is skipped in the Codex CI-style environment.")
        }
        let clip = try XCTUnwrap(loadBenchmarkClips().first(where: { $0.name == "marker_occlusion_reentry" }))
        let source = try await NativeVideoSource.open(url: clip.videoURL)
        let runner = NativeSingleObjectTrackingRunner()
        let result: NativeTrackResult
        do {
            result = try runner.runSingleObjectTracking(
                video: source,
                initialBBox: clip.initialBBox,
                startFrame: clip.startFrame,
                config: TrackingConfigSnapshot.pythonDefaults.withBidirectionalRefinement(false)
            )
        } catch {
            try skipIfVideoDecodingUnsupported(error)
            throw error
        }

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

    func testCorrectionReplayRerunsForwardFromAnchorAndReplacesDownstreamObservations() throws {
        let runner = NativeSingleObjectTrackingRunner()
        let config = syntheticRecoveryConfig()
        let initialBBox = BBoxSnapshot(x: 8, y: 20, width: 14, height: 14)
        let correctionBBox = BBoxSnapshot(x: 54, y: 20, width: 14, height: 14)
        let frames = [
            makeSyntheticFrame(objectRect: CGRect(x: 8, y: 20, width: 14, height: 14)),
            makeSyntheticFrame(objectRect: CGRect(x: 14, y: 20, width: 14, height: 14)),
            makeSyntheticFrame(objectRect: CGRect(x: 20, y: 20, width: 14, height: 14)),
            makeSyntheticFrame(objectRect: CGRect(x: 54, y: 20, width: 14, height: 14)),
            makeSyntheticFrame(objectRect: CGRect(x: 60, y: 20, width: 14, height: 14)),
        ]
        let baseObservations = [
            makeObservation(frameIndex: 0, x: 15, confidence: 1.0, lost: false, state: NativeTrackingState.tracking.rawValue),
            makeObservation(frameIndex: 1, x: 21, confidence: 0.92, lost: false, state: NativeTrackingState.tracking.rawValue),
            makeObservation(frameIndex: 2, x: 27, confidence: 0.91, lost: false, state: NativeTrackingState.tracking.rawValue),
            makeObservation(frameIndex: 3, x: 33, confidence: 0.28, lost: true, state: NativeTrackingState.lost.rawValue),
            makeObservation(frameIndex: 4, x: 39, confidence: 0.24, lost: true, state: NativeTrackingState.lost.rawValue),
        ]
        let baseTrack = NativeTrackResult(
            observations: baseObservations,
            trackerName: "robust_hybrid_tracker",
            averageConfidence: baseObservations.map(\.confidence).reduce(0, +) / Double(baseObservations.count),
            startFrame: 0,
            endFrame: 4,
            initialBBox: initialBBox,
            quality: NativeTrackRuntimeDerivation.computeQualityMetadata(observations: baseObservations),
            trackingConfig: config,
            trackID: "primary",
            trackName: "Primary Object",
            trackKind: "primary"
        )

        let replayed = try runner.replayCorrection(
            frameImages: frames,
            baseTrack: baseTrack,
            correctedBBox: correctionBBox,
            startFrame: 3,
            config: config,
            fps: 30.0
        )

        XCTAssertEqual(replayed.observations.map(\.frameIndex), [0, 1, 2, 3, 4])
        XCTAssertEqual(replayed.observations.prefix(3).map(\.centroidXPixels), baseObservations.prefix(3).map(\.centroidXPixels))
        XCTAssertTrue(replayed.observations[3].corrected)
        XCTAssertTrue(replayed.observations[4].corrected)
        XCTAssertLessThan(abs(replayed.observations[3].centroidXPixels - 61.0), 1.5)
        XCTAssertLessThan(abs(replayed.observations[4].centroidXPixels - 67.0), 1.5)
        XCTAssertGreaterThan(abs(replayed.observations[4].centroidXPixels - baseObservations[4].centroidXPixels), 20.0)
        XCTAssertEqual(replayed.quality.correctedSpans?.map(\.startFrame), [3])
        XCTAssertEqual(replayed.quality.correctedSpans?.map(\.endFrame), [4])
    }

    func testReferenceMotionCorrectionMatchesPythonSemantics() {
        let runner = NativeSingleObjectTrackingRunner()
        let primaryTrack = NativeTrackResult(
            observations: [
                makeObservation(frameIndex: 0, x: 20, y: 30, confidence: 0.95, lost: false, state: NativeTrackingState.tracking.rawValue),
                makeObservation(frameIndex: 1, x: 24, y: 31, confidence: 0.80, lost: false, state: NativeTrackingState.tracking.rawValue),
                makeObservation(frameIndex: 2, x: 29, y: 32, confidence: 0.42, lost: true, state: NativeTrackingState.lost.rawValue)
            ],
            trackerName: "robust_hybrid_tracker",
            averageConfidence: (0.95 + 0.80 + 0.42) / 3.0,
            startFrame: 0,
            endFrame: 2,
            initialBBox: BBoxSnapshot(x: 17, y: 27, width: 6, height: 6),
            quality: TrackQualitySnapshot(
                lostSpans: [TrackSpanSnapshot(startFrame: 2, endFrame: 2, reason: "lost_tracking")],
                suspectSpans: nil,
                correctedSpans: nil,
                reacquisitionCount: 0,
                reviewRecommended: true
            ),
            trackingConfig: TrackingConfigSnapshot.pythonDefaults.withBidirectionalRefinement(false),
            trackID: "primary",
            trackName: "Primary Object",
            trackKind: "primary"
        )
        let referenceTrack = NativeTrackResult(
            observations: [
                makeObservation(frameIndex: 0, x: 80, y: 60, confidence: 1.0, lost: false, state: NativeTrackingState.tracking.rawValue, trackID: "reference", trackName: "Reference Marker", trackKind: "reference"),
                makeObservation(frameIndex: 1, x: 84, y: 63, confidence: 0.65, lost: false, state: NativeTrackingState.tracking.rawValue, trackID: "reference", trackName: "Reference Marker", trackKind: "reference"),
                makeObservation(frameIndex: 2, x: 89, y: 66, confidence: 0.30, lost: true, state: NativeTrackingState.lost.rawValue, trackID: "reference", trackName: "Reference Marker", trackKind: "reference")
            ],
            trackerName: "robust_hybrid_tracker",
            averageConfidence: (1.0 + 0.65 + 0.30) / 3.0,
            startFrame: 0,
            endFrame: 2,
            initialBBox: BBoxSnapshot(x: 77, y: 57, width: 6, height: 6),
            quality: TrackQualitySnapshot(
                lostSpans: nil,
                suspectSpans: nil,
                correctedSpans: nil,
                reacquisitionCount: 0,
                reviewRecommended: false
            ),
            trackingConfig: TrackingConfigSnapshot(profile: .marker).resolved(),
            trackID: "reference",
            trackName: "Reference Marker",
            trackKind: "reference"
        )

        let corrected = runner.applyReferenceMotionCorrection(primaryTrack: primaryTrack, referenceTrack: referenceTrack)

        XCTAssertEqual(corrected.trackerName, "robust_hybrid_tracker_reference_corrected")
        XCTAssertEqual(corrected.quality.lostSpans?.first?.startFrame, 2)
        XCTAssertEqual(corrected.observations.map(\.centroidXPixels), [20, 20, 20])
        XCTAssertEqual(corrected.observations.map(\.centroidYPixels), [30, 28, 26])
        assertApproximatelyEqual(corrected.observations.map(\.confidence), [0.95, 0.65, 0.30], accuracy: 1e-12)
        XCTAssertEqual(corrected.observations.map(\.lost), [false, false, true])
        XCTAssertEqual(corrected.observations.map(\.state), [
            NativeTrackingState.tracking.rawValue,
            NativeTrackingState.tracking.rawValue,
            NativeTrackingState.suspect.rawValue,
        ])
        XCTAssertEqual(corrected.observations[2].failureReason, "search_exhausted")
        XCTAssertEqual(corrected.observations[1].debug["reference_dx"], "4.0")
        XCTAssertEqual(corrected.observations[1].debug["reference_dy"], "3.0")
        XCTAssertEqual(corrected.observations[1].debug["reference_profile"], TrackingProfileOption.marker.rawValue)
        XCTAssertEqual(corrected.averageConfidence, (0.95 + 0.65 + 0.30) / 3.0, accuracy: 1e-12)
    }

    func testNativeReferenceTrackingStabilizesDriftScenario() throws {
        let frames = [
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 16, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 70, y: 42, width: 10, height: 10), color: (220, 120, 32)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 21, y: 19, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 75, y: 43, width: 10, height: 10), color: (220, 120, 32)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 25, y: 17, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 79, y: 41, width: 10, height: 10), color: (220, 120, 32)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 30, y: 20, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 84, y: 44, width: 10, height: 10), color: (220, 120, 32)),
            ]),
        ]
        var config = TrackingConfigSnapshot.pythonDefaults.resolved()
        config.profile = .marker
        config.bidirectionalRefinement = false
        config.interpolateShortGaps = false

        let result = try NativeSingleObjectTrackingRunner().runReferenceCorrectedTracking(
            frameImages: frames,
            initialBBox: BBoxSnapshot(x: 16, y: 18, width: 12, height: 12),
            referenceBBox: BBoxSnapshot(x: 70, y: 42, width: 10, height: 10),
            corrected: false,
            config: config,
            fps: 30.0
        )

        let displaySpan = (result.displayTrack.observations.map(\.centroidXPixels).max() ?? 0) - (result.displayTrack.observations.map(\.centroidXPixels).min() ?? 0)
        let correctedSpan = (result.analysisTrack.observations.map(\.centroidXPixels).max() ?? 0) - (result.analysisTrack.observations.map(\.centroidXPixels).min() ?? 0)

        XCTAssertEqual(result.referenceTrack.trackID, "reference")
        XCTAssertEqual(result.referenceTrack.trackKind, "reference")
        XCTAssertEqual(result.referenceTrack.trackingConfig.profile, .marker)
        XCTAssertFalse(result.referenceTrack.observations.contains(where: \.lost))
        XCTAssertGreaterThan(displaySpan, 10.0)
        XCTAssertLessThan(correctedSpan, 4.0)
        XCTAssertLessThan(correctedSpan, displaySpan * 0.3)
        XCTAssertEqual(result.analysisTrack.observations.first?.centroidXPixels ?? 0, result.analysisTrack.observations.last?.centroidXPixels ?? 1, accuracy: 3.5)
        XCTAssertEqual(result.analysisTrack.observations.first?.debug["reference_profile"], TrackingProfileOption.marker.rawValue)
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

    func testNativeMultiObjectExperimentCoordinatesReferenceCorrectionAndPairwiseMetrics() throws {
        let frames = [
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 20, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 50, y: 18, width: 12, height: 12), color: (64, 160, 240)),
                SyntheticObject(rect: CGRect(x: 80, y: 42, width: 10, height: 10), color: (220, 120, 32)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 24, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 56, y: 18, width: 12, height: 12), color: (64, 160, 240)),
                SyntheticObject(rect: CGRect(x: 84, y: 42, width: 10, height: 10), color: (220, 120, 32)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 28, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 62, y: 18, width: 12, height: 12), color: (64, 160, 240)),
                SyntheticObject(rect: CGRect(x: 88, y: 42, width: 10, height: 10), color: (220, 120, 32)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 32, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 68, y: 18, width: 12, height: 12), color: (64, 160, 240)),
                SyntheticObject(rect: CGRect(x: 92, y: 42, width: 10, height: 10), color: (220, 120, 32)),
            ]),
        ]
        var config = TrackingConfigSnapshot.pythonDefaults.resolved()
        config.profile = .marker
        config.bidirectionalRefinement = false
        config.interpolateShortGaps = false

        var session = makeSessionSnapshot(trackingConfig: config)
        session.referenceBbox = BBoxSnapshot(x: 80, y: 42, width: 10, height: 10)
        session.additionalObjects = [
            AdditionalObjectSnapshot(
                trackID: "secondary_cart",
                name: "Secondary Cart",
                kind: "secondary",
                bbox: BBoxSnapshot(x: 50, y: 18, width: 12, height: 12)
            )
        ]

        let result = try NativeMultiObjectTrackingRunner().run(
            frameImages: frames,
            session: session,
            fps: 30.0
        )

        XCTAssertEqual(result.primaryTrackID, "primary")
        XCTAssertEqual(result.displayTracks.keys.sorted(), ["primary", "secondary_cart"])
        XCTAssertEqual(result.analysisTracks.keys.sorted(), ["primary", "secondary_cart"])
        XCTAssertEqual(result.referenceTrack?.trackID, "reference")
        XCTAssertEqual(result.referenceTrack?.trackKind, "reference")
        XCTAssertEqual(result.displayTracks["primary"]?.trackName, "Primary Object")
        XCTAssertEqual(result.analysisTracks["secondary_cart"]?.trackName, "Secondary Cart")
        XCTAssertEqual(result.analysisTracks["secondary_cart"]?.trackKind, "secondary")

        let primaryAnalysisTrack = try XCTUnwrap(result.analysisTracks["primary"])
        XCTAssertEqual(primaryAnalysisTrack.observations.count, 4)
        XCTAssertTrue(
            primaryAnalysisTrack.observations.allSatisfy {
                $0.debug["reference_profile"] == TrackingProfileOption.marker.rawValue
            }
        )

        let pairwise = try XCTUnwrap(result.pairwiseMetrics.first)
        XCTAssertEqual(pairwise.primaryTrackID, "primary")
        XCTAssertEqual(pairwise.secondaryTrackID, "secondary_cart")
        XCTAssertEqual(pairwise.samples.count, 4)
        XCTAssertEqual(pairwise.samples.map(\.frameIndex), [0, 1, 2, 3])
        XCTAssertTrue(pairwise.samples.allSatisfy { $0.relativeDXUnits > 0 })
        XCTAssertTrue(pairwise.samples.allSatisfy { $0.relativeSpeedUnitsPerSecond >= 0 })
        XCTAssertTrue(pairwise.samples.allSatisfy { $0.centerOfMassXUnits != nil })
        XCTAssertTrue(pairwise.samples.allSatisfy { $0.centerOfMassYUnits != nil })
        XCTAssertLessThan(pairwise.samples.first?.distanceUnits ?? .greatestFiniteMagnitude, pairwise.samples.last?.distanceUnits ?? 0)
        XCTAssertLessThan(pairwise.samples.first?.relativeDXUnits ?? .greatestFiniteMagnitude, pairwise.samples.last?.relativeDXUnits ?? 0)

        let loadResult = result.asLoadResult(
            session: session,
            outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("native-multi-test")
        )
        XCTAssertEqual(loadResult.trackBundles.map(\.trackID), ["primary", "secondary_cart"])
        XCTAssertEqual(loadResult.trackBundles[0].trackKind, "primary")
        XCTAssertEqual(loadResult.trackBundles[1].trackKind, "secondary")
    }

    func testNativePairwiseMetricsPersistAsAuthoritativeBundleArtifact() throws {
        let frames = [
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 10, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 18, y: 18, width: 12, height: 12), color: (64, 160, 240)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 12, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 16, y: 18, width: 12, height: 12), color: (64, 160, 240)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 14, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 14, y: 18, width: 12, height: 12), color: (64, 160, 240)),
            ]),
            makeSyntheticFrame(objects: [
                SyntheticObject(rect: CGRect(x: 16, y: 18, width: 12, height: 12), color: (32, 220, 96)),
                SyntheticObject(rect: CGRect(x: 12, y: 18, width: 12, height: 12), color: (64, 160, 240)),
            ]),
        ]
        var config = TrackingConfigSnapshot.pythonDefaults.resolved()
        config.profile = .marker
        config.bidirectionalRefinement = false
        config.interpolateShortGaps = false

        var session = makeSessionSnapshot(trackingConfig: config)
        session.additionalObjects = [
            AdditionalObjectSnapshot(
                trackID: "secondary_cart",
                name: "Secondary Cart",
                kind: "secondary",
                bbox: BBoxSnapshot(x: 18, y: 18, width: 12, height: 12)
            )
        ]

        let result = try NativeMultiObjectTrackingRunner().run(
            frameImages: frames,
            session: session,
            fps: 30.0
        )
        let loadResult = result.asLoadResult(
            session: session,
            outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        )

        let exporter = NativeResearchBundleExporter()
        for bundle in loadResult.trackBundles {
            _ = try exporter.export(
                NativeResearchBundlePayload(
                    session: session,
                    trackID: bundle.trackID,
                    trackName: bundle.trackName,
                    analysisRows: bundle.analysisRows,
                    pairwiseMetrics: loadResult.pairwiseMetrics,
                    eventMarkers: [],
                    outputDirectory: bundle.exportDirectory,
                    reportTemplate: "research",
                    trackingProfile: .marker,
                    includeOverlay: false,
                    includePlots: false,
                    debugTracking: false,
                    summary: bundle.summary,
                    quality: bundle.quality,
                    modules: bundle.modules
                )
            )
        }
        try exporter.exportPairwiseMetrics(loadResult.pairwiseMetrics, to: loadResult.exportDirectory)

        let expected = try XCTUnwrap(loadResult.pairwiseMetrics.first)
        let reloaded = try PythonEngineBridge().loadBundle(from: loadResult.exportDirectory)
        let pairwise = try XCTUnwrap(reloaded.pairwiseMetrics.first)
        XCTAssertEqual(pairwise.primaryTrackID, expected.primaryTrackID)
        XCTAssertEqual(pairwise.secondaryTrackID, expected.secondaryTrackID)
        XCTAssertEqual(pairwise.collisionFrame, expected.collisionFrame)
        XCTAssertEqual(pairwise.minimumSeparation, expected.minimumSeparation, accuracy: 0.0001)
        XCTAssertEqual(pairwise.peakRelativeSpeed, expected.peakRelativeSpeed, accuracy: 0.0001)
        XCTAssertEqual(pairwise.samples.map(\.frameIndex), expected.samples.map(\.frameIndex))
        XCTAssertEqual(
            try XCTUnwrap(pairwise.samples[2].centerOfMassXUnits),
            try XCTUnwrap(expected.samples[2].centerOfMassXUnits),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(pairwise.samples[2].centerOfMassYUnits),
            try XCTUnwrap(expected.samples[2].centerOfMassYUnits),
            accuracy: 0.0001
        )
    }

    func testNativeTrackerMeetsBenchmarkReleaseGateTargets() async throws {
        if ProcessInfo.processInfo.environment["CODEX_CI"] != nil {
            throw XCTSkip("Benchmark release-gate coverage is skipped in the Codex CI-style environment.")
        }
        let clips = Dictionary(uniqueKeysWithValues: try loadBenchmarkClips().map { ($0.name, $0) })
        let runner = NativeSingleObjectTrackingRunner()
        let forwardOnlyConfig = TrackingConfigSnapshot.pythonDefaults
            .withBidirectionalRefinement(false)

        for target in NativeTrackingParityTargets.benchmarkReleaseGate {
            let clip = try XCTUnwrap(clips[target.clipName], "Missing benchmark clip \(target.clipName)")
            let source = try await NativeVideoSource.open(url: clip.videoURL)
            let result: NativeTrackResult
            do {
                result = try runner.runSingleObjectTracking(
                    video: source,
                    initialBBox: clip.initialBBox,
                    startFrame: clip.startFrame,
                    config: forwardOnlyConfig
                )
            } catch {
                try skipIfVideoDecodingUnsupported(error)
                throw error
            }
            let metrics = try evaluate(track: result, against: clip)
            XCTAssertGreaterThan(metrics.meanIoU, 0)

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

    func testNativeBenchmarkSuiteAggregatesRegressionMetrics() async throws {
        if ProcessInfo.processInfo.environment["CODEX_CI"] != nil {
            throw XCTSkip("Benchmark suite coverage is skipped in the Codex CI-style environment.")
        }

        let runner = NativeTrackingBenchmarkRunner()
        let suite: NativeBenchmarkSuiteMetrics
        do {
            suite = try await runner.evaluateSuite(
                manifestURL: try NativeTrackingBenchmark.defaultManifestURL(repositoryRoot: repositoryRoot),
                repositoryRoot: repositoryRoot
            )
        } catch {
            try skipIfVideoDecodingUnsupported(error)
            throw error
        }

        XCTAssertEqual(suite.clipMetrics.count, NativeTrackingParityTargets.benchmarkReleaseGate.count)
        XCTAssertLessThanOrEqual(suite.medianCenterErrorPixels, 6.0)
        XCTAssertLessThanOrEqual(suite.p95CenterErrorPixels, 18.0)
        XCTAssertLessThanOrEqual(suite.lostFrameRate, 0.05)
        XCTAssertLessThanOrEqual(suite.maxReacquisitionLatencyFrames, 10)
        XCTAssertGreaterThan(suite.meanIoU, 0)
    }

    private func evaluate(
        track: NativeTrackResult,
        against clip: NativeBenchmarkClip
    ) throws -> NativeBenchmarkMetrics {
        try NativeTrackingBenchmark.evaluate(track: track, against: clip)
    }

    private func loadBenchmarkClips() throws -> [NativeBenchmarkClip] {
        try NativeTrackingBenchmark.loadClips(
            manifestURL: try NativeTrackingBenchmark.defaultManifestURL(repositoryRoot: repositoryRoot),
            repositoryRoot: repositoryRoot
        )
    }

    private func assertApproximatelyEqual(
        _ lhs: [Double],
        _ rhs: [Double],
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for (left, right) in zip(lhs, rhs) {
            XCTAssertEqual(left, right, accuracy: accuracy, file: file, line: line)
        }
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

    private func makeSyntheticFrame(
        width: Int = 120,
        height: Int = 80,
        objects: [SyntheticObject]
    ) -> CGImage {
        var rgba = Array(repeating: UInt8.zero, count: width * height * 4)
        for object in objects {
            drawSyntheticObject(
                into: &rgba,
                width: width,
                height: height,
                objectRect: object.rect,
                objectColor: object.color
            )
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

    private func drawSyntheticObject(
        into rgba: inout [UInt8],
        width: Int,
        height: Int,
        objectRect: CGRect,
        objectColor: (UInt8, UInt8, UInt8)
    ) {
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

    private func makeObservation(
        frameIndex: Int,
        x: Double,
        y: Double = 20,
        confidence: Double,
        lost: Bool,
        corrected: Bool = false,
        state: String,
        debug: [String: String] = [:],
        trackID: String = "primary",
        trackName: String = "Primary Object",
        trackKind: String = "primary"
    ) -> NativeTrackingObservation {
        NativeTrackingObservation(
            frameIndex: frameIndex,
            timeSeconds: Double(frameIndex) / 30.0,
            centroidXPixels: x,
            centroidYPixels: y,
            bbox: BBoxSnapshot(x: x - 3, y: y - 3, width: 6, height: 6),
            confidence: confidence,
            lost: lost,
            corrected: corrected,
            state: state,
            failureReason: lost ? "search_exhausted" : nil,
            source: lost ? "predicted" : "measured",
            isInferred: lost,
            isInterpolated: false,
            debug: debug,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
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

private extension NativeTrackingObservation {
    func withBBox(_ bbox: BBoxSnapshot) -> NativeTrackingObservation {
        var copy = self
        copy.bbox = bbox
        return copy
    }
}

private struct SyntheticObject {
    var rect: CGRect
    var color: (UInt8, UInt8, UInt8)
}
