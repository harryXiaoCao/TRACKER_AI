import CoreGraphics
import Foundation

enum NativeTrackingRuntimeError: LocalizedError {
    case invalidInitialTemplate
    case invalidFrameRange(start: Int, end: Int)
    case emptyFrameSequence

    var errorDescription: String? {
        switch self {
        case .invalidInitialTemplate:
            return "The initial bounding box produced an empty native tracking template."
        case .invalidFrameRange(let start, let end):
            return "The selected frame range is invalid: \(start) to \(end)."
        case .emptyFrameSequence:
            return "Synthetic tracking requires at least one frame image."
        }
    }
}

enum NativeTrackingState: String {
    case tracking
    case suspect
    case lost
    case reacquired
}

struct NativeTrackResult {
    var observations: [NativeTrackingObservation]
    var trackerName: String
    var averageConfidence: Double
    var startFrame: Int
    var endFrame: Int
    var initialBBox: BBoxSnapshot
    var quality: TrackQualitySnapshot
    var trackingConfig: TrackingConfigSnapshot
    var trackID: String = "primary"
    var trackName: String = "Primary Object"
    var trackKind: String = "primary"

    func observationByFrame() -> [Int: NativeTrackingObservation] {
        Dictionary(uniqueKeysWithValues: observations.map { ($0.frameIndex, $0) })
    }
}

struct NativeReferenceCorrectedTrackResult {
    var displayTrack: NativeTrackResult
    var analysisTrack: NativeTrackResult
    var referenceTrack: NativeTrackResult
}

struct NativeTrackedObjectSpecification {
    var trackID: String
    var trackName: String
    var trackKind: String
    var initialBBox: BBoxSnapshot
}

struct NativeMultiObjectExperimentResult {
    var primaryTrackID: String
    var displayTracks: [String: NativeTrackResult]
    var analysisTracks: [String: NativeTrackResult]
    var analysesByTrackID: [String: [AnalysisRow]]
    var pairwiseMetrics: [PairwiseMetricSnapshot]
    var referenceTrack: NativeTrackResult?

    func asLoadResult(session: SessionSnapshot, outputDirectory: URL) -> AnalysisLoadResult {
        let orderedBundles = analysisTracks.values
            .sorted { lhs, rhs in
                if lhs.trackID == primaryTrackID { return true }
                if rhs.trackID == primaryTrackID { return false }
                return lhs.trackID < rhs.trackID
            }
            .compactMap { track -> AnalysisTrackBundle? in
                guard let rows = analysesByTrackID[track.trackID] else { return nil }
                let bundleDirectory: URL
                if analysisTracks.count > 1 {
                    bundleDirectory = outputDirectory.appendingPathComponent(track.trackID, isDirectory: true)
                } else {
                    bundleDirectory = outputDirectory
                }
                return AnalysisTrackBundle(
                    trackID: track.trackID,
                    trackName: track.trackName,
                    trackKind: track.trackKind,
                    summary: nil,
                    quality: nil,
                    modules: [],
                    analysisRows: rows,
                    reportMarkdown: "",
                    exportDirectory: bundleDirectory
                )
            }

        let primaryBundle = orderedBundles.first(where: { $0.trackID == primaryTrackID }) ?? orderedBundles.first
        return AnalysisLoadResult(
            summary: nil,
            quality: nil,
            modules: [],
            analysisRows: primaryBundle?.analysisRows ?? [],
            session: session,
            reportMarkdown: "",
            exportDirectory: outputDirectory,
            trackBundles: orderedBundles,
            pairwiseMetrics: pairwiseMetrics
        )
    }
}

struct NativeMultiObjectTrackingRunner {
    private let trackingRunner = NativeSingleObjectTrackingRunner()
    private let scientificProcessor = NativeScientificProcessor()
    private let trackingPipeline = NativeTrackingPipeline()

    func run(
        video: NativeVideoSource,
        session: SessionSnapshot,
        primaryTrackID: String = "primary"
    ) throws -> NativeMultiObjectExperimentResult {
        let trackedObjects = trackedObjects(from: session, primaryTrackID: primaryTrackID)
        let trackingConfig = session.resolvedTrackingConfig
        let startFrame = max(session.selectedStartFrame ?? 0, 0)
        let endFrame = session.selectedEndFrame
        let referenceTrack = try session.referenceBbox.map { referenceBBox in
            try trackingRunner.runSingleObjectTracking(
                video: video,
                initialBBox: referenceBBox,
                startFrame: startFrame,
                endFrame: endFrame,
                corrected: false,
                config: trackingRunner.referenceTrackingConfig(from: trackingConfig),
                trackID: "reference",
                trackName: "Reference Marker",
                trackKind: "reference"
            )
        }

        return try coordinateRun(
            trackedObjects: trackedObjects,
            session: session,
            referenceTrack: referenceTrack,
            primaryTrackID: primaryTrackID
        ) { object in
            try trackingRunner.runSingleObjectTracking(
                video: video,
                initialBBox: object.initialBBox,
                startFrame: startFrame,
                endFrame: endFrame,
                corrected: false,
                config: trackingConfig,
                trackID: object.trackID,
                trackName: object.trackName,
                trackKind: object.trackKind
            )
        }
    }

    func run(
        frameImages: [CGImage],
        session: SessionSnapshot,
        primaryTrackID: String = "primary",
        fps: Double = 30.0
    ) throws -> NativeMultiObjectExperimentResult {
        let trackedObjects = trackedObjects(from: session, primaryTrackID: primaryTrackID)
        let trackingConfig = session.resolvedTrackingConfig
        let referenceTrack = try session.referenceBbox.map { referenceBBox in
            try trackingRunner.runSingleObjectTracking(
                frameImages: frameImages,
                initialBBox: referenceBBox,
                corrected: false,
                config: trackingRunner.referenceTrackingConfig(from: trackingConfig),
                fps: fps,
                trackID: "reference",
                trackName: "Reference Marker",
                trackKind: "reference"
            )
        }

        return try coordinateRun(
            trackedObjects: trackedObjects,
            session: session,
            referenceTrack: referenceTrack,
            primaryTrackID: primaryTrackID
        ) { object in
            try trackingRunner.runSingleObjectTracking(
                frameImages: frameImages,
                initialBBox: object.initialBBox,
                corrected: false,
                config: trackingConfig,
                fps: fps,
                trackID: object.trackID,
                trackName: object.trackName,
                trackKind: object.trackKind
            )
        }
    }

    private func coordinateRun(
        trackedObjects: [NativeTrackedObjectSpecification],
        session: SessionSnapshot,
        referenceTrack: NativeTrackResult?,
        primaryTrackID: String,
        trackRunner: (NativeTrackedObjectSpecification) throws -> NativeTrackResult
    ) throws -> NativeMultiObjectExperimentResult {
        let calibrationProfile = try session.calibration.makeCalibrationProfile()
        var displayTracks: [String: NativeTrackResult] = [:]
        var analysisTracks: [String: NativeTrackResult] = [:]
        var analysesByTrackID: [String: [AnalysisRow]] = [:]

        for object in trackedObjects {
            let displayTrack = try trackRunner(object)
            let analysisTrack: NativeTrackResult
            if let referenceTrack {
                analysisTrack = trackingRunner.applyReferenceMotionCorrection(
                    primaryTrack: displayTrack,
                    referenceTrack: referenceTrack
                )
            } else {
                analysisTrack = displayTrack
            }

            displayTracks[object.trackID] = displayTrack
            analysisTracks[object.trackID] = analysisTrack
            analysesByTrackID[object.trackID] = scientificProcessor.process(
                observations: analysisTrack.observations,
                calibration: calibrationProfile,
                config: session.analysisConfig
            )
        }

        let reconstructions = analysisTracks.values.map { track in
            NativeTrackReconstruction(
                trackID: track.trackID,
                trackName: track.trackName,
                trackKind: track.trackKind,
                observations: track.observations,
                quality: track.quality,
                averageConfidence: track.averageConfidence
            )
        }
        let pairwiseMetrics = trackingPipeline.rebuildPairwiseMetrics(
            tracks: reconstructions,
            analysesByTrackID: analysesByTrackID
        )

        return NativeMultiObjectExperimentResult(
            primaryTrackID: primaryTrackID,
            displayTracks: displayTracks,
            analysisTracks: analysisTracks,
            analysesByTrackID: analysesByTrackID,
            pairwiseMetrics: pairwiseMetrics,
            referenceTrack: referenceTrack
        )
    }

    private func trackedObjects(
        from session: SessionSnapshot,
        primaryTrackID: String
    ) -> [NativeTrackedObjectSpecification] {
        var objects = [
            NativeTrackedObjectSpecification(
                trackID: primaryTrackID,
                trackName: "Primary Object",
                trackKind: "primary",
                initialBBox: session.initialBbox
            )
        ]
        objects.append(
            contentsOf: (session.additionalObjects ?? []).map {
                NativeTrackedObjectSpecification(
                    trackID: $0.trackID,
                    trackName: $0.name,
                    trackKind: $0.kind ?? "secondary",
                    initialBBox: $0.bbox
                )
            }
        )
        return objects
    }

}

struct NativeTrackingParityTarget: Hashable {
    var clipName: String
    var maxP95CenterErrorPixels: Double
    var maxLostFrameRate: Double
    var maxReacquisitionLatencyFrames: Int
}

enum NativeTrackingParityTargets {
    static let benchmarkReleaseGate: [NativeTrackingParityTarget] = [
        NativeTrackingParityTarget(
            clipName: "marker_blur_glare",
            maxP95CenterErrorPixels: 6.0,
            maxLostFrameRate: 0.00,
            maxReacquisitionLatencyFrames: 0
        ),
        NativeTrackingParityTarget(
            clipName: "marker_occlusion_reentry",
            maxP95CenterErrorPixels: 18.0,
            maxLostFrameRate: 0.10,
            maxReacquisitionLatencyFrames: 10
        ),
        NativeTrackingParityTarget(
            clipName: "marker_jitter_distractor_scale",
            maxP95CenterErrorPixels: 6.0,
            maxLostFrameRate: 0.00,
            maxReacquisitionLatencyFrames: 0
        ),
    ]
}

struct NativeSingleObjectTrackingRunner {
    func replayCorrection(
        video: NativeVideoSource,
        baseTrack: NativeTrackResult,
        correctedBBox: BBoxSnapshot,
        startFrame: Int,
        endFrame: Int? = nil,
        config: TrackingConfigSnapshot = .pythonDefaults,
        trackID: String = "primary",
        trackName: String = "Primary Object",
        trackKind: String = "primary"
    ) throws -> NativeTrackResult {
        let replacement = try runSingleObjectTracking(
            video: video,
            initialBBox: correctedBBox,
            startFrame: startFrame,
            endFrame: endFrame,
            corrected: true,
            config: config,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
        return mergeTrackResults(base: baseTrack, replacement: replacement)
    }

    func replayCorrection(
        frameImages: [CGImage],
        baseTrack: NativeTrackResult,
        correctedBBox: BBoxSnapshot,
        startFrame: Int,
        config: TrackingConfigSnapshot = .pythonDefaults,
        fps: Double = 30.0,
        trackID: String = "primary",
        trackName: String = "Primary Object",
        trackKind: String = "primary"
    ) throws -> NativeTrackResult {
        guard startFrame >= 0, startFrame < frameImages.count else {
            throw NativeTrackingRuntimeError.invalidFrameRange(start: startFrame, end: frameImages.count - 1)
        }

        let replacementFrames = Array(frameImages[startFrame...])
        let replacement = try runSingleObjectTracking(
            frameImages: replacementFrames,
            initialBBox: correctedBBox,
            corrected: true,
            config: config,
            fps: fps,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
        let rebasedReplacement = NativeTrackResult(
            observations: replacement.observations.map { observation in
                NativeTrackingObservation(
                    frameIndex: observation.frameIndex + startFrame,
                    timeSeconds: observation.timeSeconds + (Double(startFrame) / max(fps, 1.0)),
                    centroidXPixels: observation.centroidXPixels,
                    centroidYPixels: observation.centroidYPixels,
                    bbox: observation.bbox,
                    confidence: observation.confidence,
                    lost: observation.lost,
                    corrected: observation.corrected,
                    state: observation.state,
                    failureReason: observation.failureReason,
                    source: observation.source,
                    isInferred: observation.isInferred,
                    isInterpolated: observation.isInterpolated,
                    debug: observation.debug,
                    trackID: observation.trackID,
                    trackName: observation.trackName,
                    trackKind: observation.trackKind
                )
            },
            trackerName: replacement.trackerName,
            averageConfidence: replacement.averageConfidence,
            startFrame: startFrame,
            endFrame: replacement.endFrame + startFrame,
            initialBBox: replacement.initialBBox,
            quality: replacement.quality,
            trackingConfig: replacement.trackingConfig,
            trackID: replacement.trackID,
            trackName: replacement.trackName,
            trackKind: replacement.trackKind
        )
        return mergeTrackResults(base: baseTrack, replacement: rebasedReplacement)
    }

    func runReferenceCorrectedTracking(
        video: NativeVideoSource,
        initialBBox: BBoxSnapshot,
        referenceBBox: BBoxSnapshot,
        startFrame: Int = 0,
        endFrame: Int? = nil,
        corrected: Bool = false,
        config: TrackingConfigSnapshot = .pythonDefaults,
        trackID: String = "primary",
        trackName: String = "Primary Object",
        trackKind: String = "primary"
    ) throws -> NativeReferenceCorrectedTrackResult {
        let displayTrack = try runSingleObjectTracking(
            video: video,
            initialBBox: initialBBox,
            startFrame: startFrame,
            endFrame: endFrame,
            corrected: corrected,
            config: config,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
        let referenceTrack = try runSingleObjectTracking(
            video: video,
            initialBBox: referenceBBox,
            startFrame: startFrame,
            endFrame: endFrame,
            corrected: corrected,
            config: referenceTrackingConfig(from: config),
            trackID: "reference",
            trackName: "Reference Marker",
            trackKind: "reference"
        )
        let analysisTrack = applyReferenceMotionCorrection(primaryTrack: displayTrack, referenceTrack: referenceTrack)
        return NativeReferenceCorrectedTrackResult(
            displayTrack: displayTrack,
            analysisTrack: analysisTrack,
            referenceTrack: referenceTrack
        )
    }

    func runReferenceCorrectedTracking(
        frameImages: [CGImage],
        initialBBox: BBoxSnapshot,
        referenceBBox: BBoxSnapshot,
        corrected: Bool = false,
        config: TrackingConfigSnapshot = .pythonDefaults,
        fps: Double = 30.0,
        trackID: String = "primary",
        trackName: String = "Primary Object",
        trackKind: String = "primary"
    ) throws -> NativeReferenceCorrectedTrackResult {
        let displayTrack = try runSingleObjectTracking(
            frameImages: frameImages,
            initialBBox: initialBBox,
            corrected: corrected,
            config: config,
            fps: fps,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
        let referenceTrack = try runSingleObjectTracking(
            frameImages: frameImages,
            initialBBox: referenceBBox,
            corrected: corrected,
            config: referenceTrackingConfig(from: config),
            fps: fps,
            trackID: "reference",
            trackName: "Reference Marker",
            trackKind: "reference"
        )
        let analysisTrack = applyReferenceMotionCorrection(primaryTrack: displayTrack, referenceTrack: referenceTrack)
        return NativeReferenceCorrectedTrackResult(
            displayTrack: displayTrack,
            analysisTrack: analysisTrack,
            referenceTrack: referenceTrack
        )
    }

    func runSingleObjectTracking(
        video: NativeVideoSource,
        initialBBox: BBoxSnapshot,
        startFrame: Int = 0,
        endFrame: Int? = nil,
        corrected: Bool = false,
        config: TrackingConfigSnapshot = .pythonDefaults,
        trackID: String = "primary",
        trackName: String = "Primary Object",
        trackKind: String = "primary"
    ) throws -> NativeTrackResult {
        let trackingConfig = config.resolved()
        let selectedEndFrame = min(endFrame ?? (video.metadata.frameCount - 1), video.metadata.frameCount - 1)
        guard selectedEndFrame >= startFrame else {
            throw NativeTrackingRuntimeError.invalidFrameRange(start: startFrame, end: selectedEndFrame)
        }

        let forwardTrack = try runTrackingPass(
            video: video,
            initialBBox: initialBBox,
            startFrame: startFrame,
            endFrame: selectedEndFrame,
            step: 1,
            corrected: corrected,
            config: trackingConfig,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
        guard trackingConfig.bidirectionalRefinement ?? true, selectedEndFrame - startFrame >= 8 else {
            return forwardTrack
        }

        let detectionThreshold = trackingConfig.detectionThreshold ?? TrackingConfigSnapshot.pythonDefaults.detectionThreshold ?? 0.5
        let seedObservation = forwardTrack.observations.reversed().first {
            !$0.lost && $0.confidence >= detectionThreshold
        } ?? forwardTrack.observations.last
        guard let seedObservation, seedObservation.frameIndex > startFrame else {
            return forwardTrack
        }

        let backwardTrack = try runTrackingPass(
            video: video,
            initialBBox: seedObservation.bbox,
            startFrame: seedObservation.frameIndex,
            endFrame: startFrame,
            step: -1,
            corrected: corrected,
            config: trackingConfig,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
        return mergeBidirectionalTracks(forward: forwardTrack, backward: backwardTrack)
    }

    func runSingleObjectTracking(
        frameImages: [CGImage],
        initialBBox: BBoxSnapshot,
        corrected: Bool = false,
        config: TrackingConfigSnapshot = .pythonDefaults,
        fps: Double = 30.0,
        trackID: String = "primary",
        trackName: String = "Primary Object",
        trackKind: String = "primary"
    ) throws -> NativeTrackResult {
        guard !frameImages.isEmpty else {
            throw NativeTrackingRuntimeError.emptyFrameSequence
        }

        let trackingConfig = config.resolved()
        let frames = try frameImages.map { try NativeTrackerImage(cgImage: $0) }
        let endFrame = frames.count - 1
        return try runTrackingPass(
            frames: frames,
            fps: fps,
            initialBBox: initialBBox,
            startFrame: 0,
            endFrame: endFrame,
            step: 1,
            corrected: corrected,
            config: trackingConfig,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
    }

    private func runTrackingPass(
        video: NativeVideoSource,
        initialBBox: BBoxSnapshot,
        startFrame: Int,
        endFrame: Int,
        step: Int,
        corrected: Bool,
        config: TrackingConfigSnapshot,
        trackID: String,
        trackName: String,
        trackKind: String
    ) throws -> NativeTrackResult {
        let initialFrameImage = try video.readFrame(atFrameIndex: startFrame).image
        let initialFrame = try NativeTrackerImage(cgImage: initialFrameImage)
        let tracker = try NativeRobustHybridTracker(
            initialFrame: initialFrame,
            initialBBox: initialBBox,
            config: config
        )

        var observations: [NativeTrackingObservation] = []
        for frameIndex in stride(from: startFrame, through: endFrame, by: step) {
            let frame = try NativeTrackerImage(cgImage: video.readFrame(atFrameIndex: frameIndex).image)
            if frameIndex == startFrame {
                let bbox = initialBBox.clipped(frameWidth: frame.width, frameHeight: frame.height)
                let center = bbox.center
                observations.append(
                    NativeTrackingObservation(
                        frameIndex: frameIndex,
                        timeSeconds: try video.frameTimestamp(forFrameIndex: frameIndex),
                        centroidXPixels: center.x,
                        centroidYPixels: center.y,
                        bbox: bbox,
                        confidence: 1.0,
                        lost: false,
                        corrected: corrected,
                        state: NativeTrackingState.tracking.rawValue,
                        failureReason: nil,
                        source: "measured",
                        isInferred: false,
                        isInterpolated: false,
                        debug: ["search_mode": "initial", "profile": tracker.activeProfile.rawValue],
                        trackID: trackID,
                        trackName: trackName,
                        trackKind: trackKind
                    )
                )
                continue
            }

            let update = tracker.update(frame: frame)
            observations.append(
                NativeTrackingObservation(
                    frameIndex: frameIndex,
                    timeSeconds: try video.frameTimestamp(forFrameIndex: frameIndex),
                    centroidXPixels: update.centroid.x,
                    centroidYPixels: update.centroid.y,
                    bbox: update.bbox,
                    confidence: update.confidence,
                    lost: update.lost,
                    corrected: corrected,
                    state: update.state.rawValue,
                    failureReason: update.failureReason,
                    source: update.lost ? "predicted" : "measured",
                    isInferred: update.lost,
                    isInterpolated: false,
                    debug: update.debug,
                    trackID: trackID,
                    trackName: trackName,
                    trackKind: trackKind
                )
            )
        }

        return buildTrackResult(
            observations: observations,
            trackerName: "robust_hybrid_tracker",
            startFrame: min(startFrame, endFrame),
            endFrame: max(startFrame, endFrame),
            initialBBox: initialBBox,
            trackingConfig: tracker.resolvedTrackingConfig,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
    }

    func applyReferenceMotionCorrection(
        primaryTrack: NativeTrackResult,
        referenceTrack: NativeTrackResult
    ) -> NativeTrackResult {
        guard let referenceOrigin = referenceTrack.observations.first else {
            return primaryTrack
        }

        let referenceByFrame = referenceTrack.observationByFrame()
        let correctedObservations = primaryTrack.observations.map { observation -> NativeTrackingObservation in
            guard let referenceObservation = referenceByFrame[observation.frameIndex] else {
                return observation
            }

            let dx = referenceObservation.centroidXPixels - referenceOrigin.centroidXPixels
            let dy = referenceObservation.centroidYPixels - referenceOrigin.centroidYPixels
            var debug = observation.debug
            debug["reference_dx"] = roundedReferenceDebugValue(dx)
            debug["reference_dy"] = roundedReferenceDebugValue(dy)
            debug["reference_profile"] = referenceTrack.trackingConfig.profile?.rawValue ?? TrackingProfileOption.auto.rawValue

            let resolvedFailureReason: String?
            if referenceObservation.lost {
                resolvedFailureReason = observation.failureReason ?? "reference_marker_lost"
            } else {
                resolvedFailureReason = observation.failureReason
            }

            return NativeTrackingObservation(
                frameIndex: observation.frameIndex,
                timeSeconds: observation.timeSeconds,
                centroidXPixels: observation.centroidXPixels - dx,
                centroidYPixels: observation.centroidYPixels - dy,
                bbox: observation.bbox,
                confidence: min(observation.confidence, referenceObservation.confidence),
                lost: observation.lost || referenceObservation.lost,
                corrected: observation.corrected,
                state: referenceObservation.lost ? NativeTrackingState.suspect.rawValue : observation.state,
                failureReason: resolvedFailureReason,
                source: observation.source,
                isInferred: observation.isInferred,
                isInterpolated: observation.isInterpolated,
                debug: debug,
                trackID: observation.trackID,
                trackName: observation.trackName,
                trackKind: observation.trackKind
            )
        }

        let averageConfidence = correctedObservations.isEmpty ? 0 : correctedObservations.map(\.confidence).mean()
        return NativeTrackResult(
            observations: correctedObservations,
            trackerName: "\(primaryTrack.trackerName)_reference_corrected",
            averageConfidence: averageConfidence,
            startFrame: primaryTrack.startFrame,
            endFrame: primaryTrack.endFrame,
            initialBBox: primaryTrack.initialBBox,
            quality: primaryTrack.quality,
            trackingConfig: primaryTrack.trackingConfig,
            trackID: primaryTrack.trackID,
            trackName: primaryTrack.trackName,
            trackKind: primaryTrack.trackKind
        )
    }

    func referenceTrackingConfig(from config: TrackingConfigSnapshot) -> TrackingConfigSnapshot {
        var resolved = config.resolved()
        if resolved.profile == .auto {
            resolved.profile = .marker
        }
        return resolved
    }

    private func runTrackingPass(
        frames: [NativeTrackerImage],
        fps: Double,
        initialBBox: BBoxSnapshot,
        startFrame: Int,
        endFrame: Int,
        step: Int,
        corrected: Bool,
        config: TrackingConfigSnapshot,
        trackID: String,
        trackName: String,
        trackKind: String
    ) throws -> NativeTrackResult {
        guard !frames.isEmpty else {
            throw NativeTrackingRuntimeError.emptyFrameSequence
        }
        let tracker = try NativeRobustHybridTracker(
            initialFrame: frames[startFrame],
            initialBBox: initialBBox,
            config: config
        )

        var observations: [NativeTrackingObservation] = []
        for frameIndex in stride(from: startFrame, through: endFrame, by: step) {
            let frame = frames[frameIndex]
            if frameIndex == startFrame {
                let bbox = initialBBox.clipped(frameWidth: frame.width, frameHeight: frame.height)
                let center = bbox.center
                observations.append(
                    NativeTrackingObservation(
                        frameIndex: frameIndex,
                        timeSeconds: Double(frameIndex) / max(fps, 1.0),
                        centroidXPixels: center.x,
                        centroidYPixels: center.y,
                        bbox: bbox,
                        confidence: 1.0,
                        lost: false,
                        corrected: corrected,
                        state: NativeTrackingState.tracking.rawValue,
                        failureReason: nil,
                        source: "measured",
                        isInferred: false,
                        isInterpolated: false,
                        debug: ["search_mode": "initial", "profile": tracker.activeProfile.rawValue],
                        trackID: trackID,
                        trackName: trackName,
                        trackKind: trackKind
                    )
                )
                continue
            }

            let update = tracker.update(frame: frame)
            observations.append(
                NativeTrackingObservation(
                    frameIndex: frameIndex,
                    timeSeconds: Double(frameIndex) / max(fps, 1.0),
                    centroidXPixels: update.centroid.x,
                    centroidYPixels: update.centroid.y,
                    bbox: update.bbox,
                    confidence: update.confidence,
                    lost: update.lost,
                    corrected: corrected,
                    state: update.state.rawValue,
                    failureReason: update.failureReason,
                    source: update.lost ? "predicted" : "measured",
                    isInferred: update.lost,
                    isInterpolated: false,
                    debug: update.debug,
                    trackID: trackID,
                    trackName: trackName,
                    trackKind: trackKind
                )
            )
        }

        return buildTrackResult(
            observations: observations,
            trackerName: "robust_hybrid_tracker",
            startFrame: min(startFrame, endFrame),
            endFrame: max(startFrame, endFrame),
            initialBBox: initialBBox,
            trackingConfig: tracker.resolvedTrackingConfig,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
    }

    private func buildTrackResult(
        observations: [NativeTrackingObservation],
        trackerName: String,
        startFrame: Int,
        endFrame: Int,
        initialBBox: BBoxSnapshot,
        trackingConfig: TrackingConfigSnapshot,
        trackID: String,
        trackName: String,
        trackKind: String
    ) -> NativeTrackResult {
        let ordered = NativeTrackRuntimeDerivation.interpolateShortGaps(
            observations.sorted { $0.frameIndex < $1.frameIndex },
            config: trackingConfig
        )
        let averageConfidence = ordered.isEmpty ? 0 : ordered.map(\.confidence).mean()
        return NativeTrackResult(
            observations: ordered,
            trackerName: trackerName,
            averageConfidence: averageConfidence,
            startFrame: startFrame,
            endFrame: endFrame,
            initialBBox: initialBBox,
            quality: NativeTrackRuntimeDerivation.computeQualityMetadata(observations: ordered),
            trackingConfig: trackingConfig,
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind
        )
    }

    private func mergeBidirectionalTracks(
        forward: NativeTrackResult,
        backward: NativeTrackResult
    ) -> NativeTrackResult {
        let backwardByFrame = backward.observationByFrame()
        let merged = forward.observations.map { observation -> NativeTrackingObservation in
            guard let reverse = backwardByFrame[observation.frameIndex] else { return observation }
            return mergeBidirectionalObservations(forward: observation, backward: reverse)
        }

        return buildTrackResult(
            observations: merged,
            trackerName: "robust_bidirectional_tracker",
            startFrame: forward.startFrame,
            endFrame: forward.endFrame,
            initialBBox: forward.initialBBox,
            trackingConfig: forward.trackingConfig,
            trackID: forward.trackID,
            trackName: forward.trackName,
            trackKind: forward.trackKind
        )
    }

    private func mergeBidirectionalObservations(
        forward: NativeTrackingObservation,
        backward: NativeTrackingObservation
    ) -> NativeTrackingObservation {
        if forward.lost != backward.lost {
            let preferred = forward.lost ? backward : forward
            var debug = forward.debug
            backward.debug.forEach { debug[$0.key] = $0.value }
            debug["merge_mode"] = "preferred_non_lost"
            var merged = preferred
            merged.corrected = preferred.corrected || backward.corrected
            merged.debug = debug
            return merged
        }

        if abs(forward.confidence - backward.confidence) > 0.10 {
            let preferred = forward.confidence >= backward.confidence ? forward : backward
            var debug = forward.debug
            backward.debug.forEach { debug[$0.key] = $0.value }
            debug["merge_mode"] = "preferred_confidence"
            var merged = preferred
            merged.corrected = forward.corrected || backward.corrected
            merged.debug = debug
            return merged
        }

        let forwardWeight = max(forward.confidence, 0.05)
        let backwardWeight = max(backward.confidence, 0.05)
        let total = forwardWeight + backwardWeight
        let mergedBBox = BBoxSnapshot(
            x: (forward.bbox.x * forwardWeight + backward.bbox.x * backwardWeight) / total,
            y: (forward.bbox.y * forwardWeight + backward.bbox.y * backwardWeight) / total,
            width: (forward.bbox.width * forwardWeight + backward.bbox.width * backwardWeight) / total,
            height: (forward.bbox.height * forwardWeight + backward.bbox.height * backwardWeight) / total
        )
        let mergedState = forward.state == backward.state
            ? forward.state
            : (forward.confidence >= backward.confidence ? forward.state : backward.state)
        var debug = forward.debug
        backward.debug.forEach { debug[$0.key] = $0.value }
        debug["merge_mode"] = "blended"
        return NativeTrackingObservation(
            frameIndex: forward.frameIndex,
            timeSeconds: forward.timeSeconds,
            centroidXPixels: (forward.centroidXPixels * forwardWeight + backward.centroidXPixels * backwardWeight) / total,
            centroidYPixels: (forward.centroidYPixels * forwardWeight + backward.centroidYPixels * backwardWeight) / total,
            bbox: mergedBBox,
            confidence: (forward.confidence * forwardWeight + backward.confidence * backwardWeight) / total,
            lost: forward.lost && backward.lost,
            corrected: forward.corrected || backward.corrected,
            state: mergedState,
            failureReason: forward.failureReason ?? backward.failureReason,
            source: forward.source,
            isInferred: forward.lost && backward.lost,
            isInterpolated: false,
            debug: debug,
            trackID: forward.trackID,
            trackName: forward.trackName,
            trackKind: forward.trackKind
        )
    }

    private func roundedReferenceDebugValue(_ value: Double) -> String {
        String((value * 10_000).rounded() / 10_000)
    }

    func mergeTrackResults(
        base: NativeTrackResult,
        replacement: NativeTrackResult
    ) -> NativeTrackResult {
        var merged = base.observations.filter { $0.frameIndex < replacement.startFrame }
        merged.append(contentsOf: replacement.observations)
        merged.sort { $0.frameIndex < $1.frameIndex }

        let averageConfidence = merged.isEmpty ? 0 : merged.map(\.confidence).mean()
        let derivedQuality = NativeTrackRuntimeDerivation.computeQualityMetadata(observations: merged)
        let correctedSpan = TrackSpanSnapshot(
            startFrame: replacement.startFrame,
            endFrame: replacement.observations.last?.frameIndex ?? replacement.startFrame,
            reason: "manual_correction"
        )
        let correctedSpans = ((base.quality.correctedSpans ?? []) + [correctedSpan])
            .sorted { lhs, rhs in
                if lhs.startFrame == rhs.startFrame {
                    if lhs.endFrame == rhs.endFrame {
                        return lhs.reason < rhs.reason
                    }
                    return lhs.endFrame < rhs.endFrame
                }
                return lhs.startFrame < rhs.startFrame
            }

        return NativeTrackResult(
            observations: merged,
            trackerName: base.trackerName,
            averageConfidence: averageConfidence,
            startFrame: base.startFrame,
            endFrame: max(base.endFrame, replacement.endFrame),
            initialBBox: base.initialBBox,
            quality: TrackQualitySnapshot(
                lostSpans: derivedQuality.lostSpans,
                suspectSpans: derivedQuality.suspectSpans,
                correctedSpans: correctedSpans,
                reacquisitionCount: derivedQuality.reacquisitionCount,
                reviewRecommended: derivedQuality.reviewRecommended
            ),
            trackingConfig: replacement.trackingConfig,
            trackID: base.trackID,
            trackName: base.trackName,
            trackKind: base.trackKind
        )
    }
}

private enum NativeSearchMode: String {
    case normal
    case expanded
    case full
}

private enum NativeResolvedTrackingProfile: String {
    case marker
    case generic
    case bright
    case dark
    case circular
    case elongated
}

private struct NativeMarkerModel {
    var lowHue: Double
    var highHue: Double
    var lowSaturation: Double
    var highSaturation: Double
    var lowValue: Double
    var highValue: Double
    var referenceRatio: Double
}

private struct NativeTrackerUpdate {
    var bbox: BBoxSnapshot
    var centroid: CGPoint
    var confidence: Double
    var lost: Bool
    var state: NativeTrackingState
    var failureReason: String?
    var debug: [String: String]
}

private struct NativeScoredCandidate {
    var bbox: BBoxSnapshot
    var score: Double
    var templateScore: Double
    var markerScore: Double
    var motionScore: Double
    var stabilityScore: Double
    var sizeScore: Double
    var searchMode: NativeSearchMode
}

private struct NativeTrackerCandidateContext {
    var frame: NativeTrackerImage
    var referenceFrame: NativeTrackerImage
    var predictedBBox: BBoxSnapshot
    var mode: NativeSearchMode
    var config: TrackingConfigSnapshot
    var markerModel: NativeMarkerModel?
}

private protocol NativeTrackerCandidateProvider {
    func generateCandidates(context: NativeTrackerCandidateContext) -> [BBoxSnapshot]
}

private struct TemplateGridCandidateProvider: NativeTrackerCandidateProvider {
    func generateCandidates(context: NativeTrackerCandidateContext) -> [BBoxSnapshot] {
        let frameWidth = context.frame.width
        let frameHeight = context.frame.height
        let scales = context.config.scaleFactors ?? TrackingConfigSnapshot.pythonDefaults.scaleFactors ?? [0.9, 1.0, 1.1]
        var candidates: [BBoxSnapshot] = []

        switch context.mode {
        case .normal, .expanded:
            let multiplier = context.mode == .normal
                ? (context.config.searchMargin ?? TrackingConfigSnapshot.pythonDefaults.searchMargin ?? 2.4)
                : (context.config.expandedSearchMargin ?? TrackingConfigSnapshot.pythonDefaults.expandedSearchMargin ?? 5.5)
            let marginX = context.predictedBBox.width * multiplier
            let marginY = context.predictedBBox.height * multiplier
            let xOffsets = linearSpace(from: -marginX, to: marginX, count: context.mode == .normal ? 5 : 7)
            let yOffsets = linearSpace(from: -marginY, to: marginY, count: context.mode == .normal ? 5 : 7)
            for scale in scales {
                let width = max(6.0, context.predictedBBox.width * scale)
                let height = max(6.0, context.predictedBBox.height * scale)
                for xOffset in xOffsets {
                    for yOffset in yOffsets {
                        let center = context.predictedBBox.center
                        candidates.append(
                            BBoxSnapshot(
                                x: center.x + xOffset - (width / 2),
                                y: center.y + yOffset - (height / 2),
                                width: width,
                                height: height
                            ).clipped(frameWidth: frameWidth, frameHeight: frameHeight)
                        )
                    }
                }
            }
        case .full:
            let columns = max(4, min(8, Int(Double(frameWidth) / max(context.predictedBBox.width * 1.4, 32))))
            let rows = max(3, min(6, Int(Double(frameHeight) / max(context.predictedBBox.height * 1.4, 32))))
            for scale in scales {
                let width = max(6.0, context.predictedBBox.width * scale)
                let height = max(6.0, context.predictedBBox.height * scale)
                for column in 0..<columns {
                    for row in 0..<rows {
                        let centerX = (Double(column) + 0.5) * Double(frameWidth) / Double(columns)
                        let centerY = (Double(row) + 0.5) * Double(frameHeight) / Double(rows)
                        candidates.append(
                            BBoxSnapshot(
                                x: centerX - (width / 2),
                                y: centerY - (height / 2),
                                width: width,
                                height: height
                            ).clipped(frameWidth: frameWidth, frameHeight: frameHeight)
                        )
                    }
                }
            }
        }

        candidates.append(context.predictedBBox.clipped(frameWidth: frameWidth, frameHeight: frameHeight))
        return candidates
    }

    private func linearSpace(from start: Double, to end: Double, count: Int) -> [Double] {
        guard count > 1 else { return [start] }
        return (0..<count).map { index in
            let alpha = Double(index) / Double(count - 1)
            return start + ((end - start) * alpha)
        }
    }
}

private struct ForegroundCandidateProvider: NativeTrackerCandidateProvider {
    func generateCandidates(context: NativeTrackerCandidateContext) -> [BBoxSnapshot] {
        let region = searchRegion(
            in: context.frame,
            predictedBBox: context.predictedBBox,
            mode: context.mode,
            config: context.config
        )
        guard let patch = context.frame.patch(x: region.x0, y: region.y0, width: region.width, height: region.height) else {
            return []
        }

        var candidates: [BBoxSnapshot] = []

        if let markerModel = context.markerModel {
            let markerMask = patch.markerMask(model: markerModel).opened(radius: 1).closed(radius: 1)
            let minimumArea = max(36.0, context.predictedBBox.area * 0.12)
            for component in markerMask.connectedBoundingBoxes(width: patch.width, height: patch.height) where component.area >= minimumArea {
                candidates.append(
                    BBoxSnapshot(
                        x: Double(region.x0) + component.x,
                        y: Double(region.y0) + component.y,
                        width: max(component.width, context.predictedBBox.width * 0.75),
                        height: max(component.height, context.predictedBBox.height * 0.75)
                    ).clipped(frameWidth: context.frame.width, frameHeight: context.frame.height)
                )
            }
        }

        if let referenceRegion = context.referenceFrame.patch(x: region.x0, y: region.y0, width: region.width, height: region.height),
           referenceRegion.width == patch.width,
           referenceRegion.height == patch.height {
            let diffMask = patch.motionMask(against: referenceRegion, threshold: 18.0 / 255.0)
                .opened(radius: 1)
                .dilated(radius: 1)
                .dilated(radius: 1)
            let minimumArea = max(48.0, context.predictedBBox.area * 0.10)
            for component in diffMask.connectedBoundingBoxes(width: patch.width, height: patch.height) where component.area >= minimumArea {
                candidates.append(
                    BBoxSnapshot(
                        x: Double(region.x0) + component.x,
                        y: Double(region.y0) + component.y,
                        width: max(component.width, context.predictedBBox.width * 0.70),
                        height: max(component.height, context.predictedBBox.height * 0.70)
                    ).clipped(frameWidth: context.frame.width, frameHeight: context.frame.height)
                )
            }
        }

        return candidates
    }

    private func searchRegion(
        in frame: NativeTrackerImage,
        predictedBBox: BBoxSnapshot,
        mode: NativeSearchMode,
        config: TrackingConfigSnapshot
    ) -> (x0: Int, y0: Int, width: Int, height: Int) {
        if mode == .full {
            return (0, 0, frame.width, frame.height)
        }

        let multiplier = mode == .normal
            ? (config.searchMargin ?? TrackingConfigSnapshot.pythonDefaults.searchMargin ?? 2.4)
            : (config.expandedSearchMargin ?? TrackingConfigSnapshot.pythonDefaults.expandedSearchMargin ?? 5.5)
        let marginX = predictedBBox.width * multiplier
        let marginY = predictedBBox.height * multiplier
        let x0 = max(0, Int((predictedBBox.x - marginX).rounded(.down)))
        let y0 = max(0, Int((predictedBBox.y - marginY).rounded(.down)))
        let x1 = min(frame.width, Int((predictedBBox.x + predictedBBox.width + marginX).rounded(.up)))
        let y1 = min(frame.height, Int((predictedBBox.y + predictedBBox.height + marginY).rounded(.up)))
        return (x0, y0, max(1, x1 - x0), max(1, y1 - y0))
    }
}

private final class NativeRobustHybridTracker {
    let activeProfile: NativeResolvedTrackingProfile
    let resolvedTrackingConfig: TrackingConfigSnapshot

    private let frameWidth: Int
    private let frameHeight: Int
    private let referenceFrame: NativeTrackerImage
    private let markerModel: NativeMarkerModel?
    private let longTermTemplate: NativeTemplatePatch
    private var shortTermTemplate: NativeTemplatePatch
    private var currentBBox: BBoxSnapshot
    private var badFrameStreak = 0
    private var reacquireStreak = 0
    private var reacquisitionCount = 0
    private var state: NativeTrackingState = .tracking
    private var velocity = CGPoint.zero
    private var lastMeasuredCenter: CGPoint
    private let candidateProviders: [any NativeTrackerCandidateProvider]

    init(
        initialFrame: NativeTrackerImage,
        initialBBox: BBoxSnapshot,
        config: TrackingConfigSnapshot
    ) throws {
        self.resolvedTrackingConfig = config.resolved()
        self.frameWidth = initialFrame.width
        self.frameHeight = initialFrame.height
        self.referenceFrame = initialFrame
        self.currentBBox = initialBBox.clipped(frameWidth: initialFrame.width, frameHeight: initialFrame.height)
        self.lastMeasuredCenter = self.currentBBox.center
        guard let templatePatch = initialFrame.patch(bbox: self.currentBBox) else {
            throw NativeTrackingRuntimeError.invalidInitialTemplate
        }
        self.longTermTemplate = NativeTemplatePatch(from: templatePatch)
        self.shortTermTemplate = NativeTemplatePatch(from: templatePatch)
        self.markerModel = NativeRobustHybridTracker.buildMarkerModel(
            patch: templatePatch,
            minimumRatio: self.resolvedTrackingConfig.autoMarkerMinRatio ?? TrackingConfigSnapshot.pythonDefaults.autoMarkerMinRatio ?? 0.12
        )
        self.activeProfile = NativeRobustHybridTracker.resolveProfile(
            requestedProfile: self.resolvedTrackingConfig.profile ?? .auto,
            templatePatch: templatePatch,
            markerModel: self.markerModel
        )
        self.candidateProviders = [
            TemplateGridCandidateProvider(),
            ForegroundCandidateProvider(),
        ]
    }

    func update(frame: NativeTrackerImage) -> NativeTrackerUpdate {
        let predictedBBox = predictBBox()
        var detection = detect(frame: frame, predictedBBox: predictedBBox, mode: .normal)
        let reacquireThreshold = resolvedTrackingConfig.reacquireThreshold ?? TrackingConfigSnapshot.pythonDefaults.reacquireThreshold ?? 0.56

        if (resolvedTrackingConfig.robustRecovery ?? true),
           badFrameStreak >= (resolvedTrackingConfig.recoveryAfterFrames ?? TrackingConfigSnapshot.pythonDefaults.recoveryAfterFrames ?? 5),
           detection.best.score < reacquireThreshold {
            let expanded = detect(frame: frame, predictedBBox: predictedBBox, mode: .expanded)
            if expanded.best.score >= detection.best.score {
                detection = expanded
            }
            if detection.best.score < reacquireThreshold {
                let full = detect(frame: frame, predictedBBox: predictedBBox, mode: .full)
                if full.best.score >= detection.best.score {
                    detection = full
                }
            }
        }

        let detectionThreshold = resolvedTrackingConfig.detectionThreshold ?? TrackingConfigSnapshot.pythonDefaults.detectionThreshold ?? 0.50
        let lowConfidenceThreshold = resolvedTrackingConfig.lowConfidenceThreshold ?? TrackingConfigSnapshot.pythonDefaults.lowConfidenceThreshold ?? 0.36
        let accepted = detection.best.score >= detectionThreshold
        let semiAccepted = detection.best.score >= lowConfidenceThreshold

        var centroidOverride: CGPoint?
        if accepted || semiAccepted {
            currentBBox = detection.best.bbox.clipped(frameWidth: frameWidth, frameHeight: frameHeight)
            let refined = refineMarkerBBox(frame: frame, bbox: currentBBox)
            currentBBox = refined.bbox
            centroidOverride = refined.centroid
            let measuredCenter = refined.centroid ?? currentBBox.center
            velocity = CGPoint(
                x: measuredCenter.x - lastMeasuredCenter.x,
                y: measuredCenter.y - lastMeasuredCenter.y
            )
            lastMeasuredCenter = measuredCenter
        } else {
            currentBBox = predictedBBox
        }

        let previousState = state
        var resolvedFailureReason: String?
        if accepted {
            if previousState == .suspect || previousState == .lost || previousState == .reacquired {
                reacquireStreak += 1
                if reacquireStreak >= 2 {
                    if previousState != .reacquired {
                        reacquisitionCount += 1
                    }
                    state = .reacquired
                } else {
                    state = .suspect
                }
            } else {
                state = .tracking
                reacquireStreak = 0
            }
            badFrameStreak = 0
        } else {
            badFrameStreak += 1
            reacquireStreak = 0
            resolvedFailureReason = failureReason(for: detection.best)
            if badFrameStreak >= (resolvedTrackingConfig.maxPredictionFrames ?? TrackingConfigSnapshot.pythonDefaults.maxPredictionFrames ?? 8) {
                state = .lost
            } else if badFrameStreak >= (resolvedTrackingConfig.suspectAfterFrames ?? TrackingConfigSnapshot.pythonDefaults.suspectAfterFrames ?? 3) {
                state = .suspect
            } else {
                state = .tracking
            }
        }

        if previousState == .reacquired && accepted {
            state = .tracking
        }
        if state == .reacquired && !accepted {
            state = .suspect
        }
        if state == .lost && semiAccepted {
            state = .suspect
        }

        let lost = state == .lost
        let confidence = accepted || semiAccepted ? detection.best.score : max(0.08, detection.best.score * 0.6)
        updateTemplates(frame: frame, bbox: currentBBox, confidence: confidence)

        var debug: [String: String] = [
            "search_mode": detection.best.searchMode.rawValue,
            "profile": activeProfile.rawValue,
        ]
        if resolvedTrackingConfig.debugTracking ?? false {
            debug["template_score"] = String(format: "%.4f", detection.best.templateScore)
            debug["marker_score"] = String(format: "%.4f", detection.best.markerScore)
            debug["motion_score"] = String(format: "%.4f", detection.best.motionScore)
            debug["stability_score"] = String(format: "%.4f", detection.best.stabilityScore)
            debug["size_score"] = String(format: "%.4f", detection.best.sizeScore)
            debug["candidate_rankings"] = detection.ranked.prefix(3).enumerated().map {
                "\($0.offset + 1):" + String(format: "%.3f", $0.element.score) + "@\($0.element.searchMode.rawValue)"
            }.joined(separator: " | ")
            debug["candidate_count"] = String(detection.ranked.count)
            debug["reacquisition_count"] = String(reacquisitionCount)
        }

        return NativeTrackerUpdate(
            bbox: currentBBox,
            centroid: centroidOverride ?? currentBBox.center,
            confidence: clamp(confidence),
            lost: lost,
            state: state,
            failureReason: resolvedFailureReason,
            debug: debug
        )
    }

    private func predictBBox() -> BBoxSnapshot {
        let center = currentBBox.center
        return BBoxSnapshot(
            x: center.x + velocity.x - (currentBBox.width / 2),
            y: center.y + velocity.y - (currentBBox.height / 2),
            width: currentBBox.width,
            height: currentBBox.height
        ).clipped(frameWidth: frameWidth, frameHeight: frameHeight)
    }

    private func detect(
        frame: NativeTrackerImage,
        predictedBBox: BBoxSnapshot,
        mode: NativeSearchMode
    ) -> (best: NativeScoredCandidate, ranked: [NativeScoredCandidate]) {
        let context = NativeTrackerCandidateContext(
            frame: frame,
            referenceFrame: referenceFrame,
            predictedBBox: predictedBBox,
            mode: mode,
            config: resolvedTrackingConfig,
            markerModel: markerModel
        )

        var candidates = candidateProviders.flatMap { $0.generateCandidates(context: context) }
        candidates.append(predictedBBox.clipped(frameWidth: frameWidth, frameHeight: frameHeight))
        let maxCandidates: Int = {
            switch mode {
            case .normal: return 90
            case .expanded: return 140
            case .full: return 180
            }
        }()
        if candidates.count > maxCandidates {
            let predictedCenter = predictedBBox.center
            candidates = candidates
                .sorted {
                    hypot($0.center.x - predictedCenter.x, $0.center.y - predictedCenter.y) <
                    hypot($1.center.x - predictedCenter.x, $1.center.y - predictedCenter.y)
                }
                .prefix(maxCandidates)
                .map { $0 }
        }

        var seen = Set<String>()
        var ranked: [NativeScoredCandidate] = []
        for candidate in candidates {
            let key = candidate.deduplicationKey
            guard seen.insert(key).inserted else { continue }
            ranked.append(scoreCandidate(frame: frame, bbox: candidate, predictedBBox: predictedBBox, searchMode: mode))
        }
        ranked.sort { $0.score > $1.score }
        let topRanked = Array(ranked.prefix(3))
        let best = topRanked.first ?? NativeScoredCandidate(
            bbox: predictedBBox,
            score: 0,
            templateScore: 0,
            markerScore: 0,
            motionScore: 0,
            stabilityScore: 0,
            sizeScore: 0,
            searchMode: mode
        )
        return (best, topRanked)
    }

    private func scoreCandidate(
        frame: NativeTrackerImage,
        bbox: BBoxSnapshot,
        predictedBBox: BBoxSnapshot,
        searchMode: NativeSearchMode
    ) -> NativeScoredCandidate {
        guard let patch = frame.patch(bbox: bbox) else {
            return NativeScoredCandidate(
                bbox: bbox,
                score: 0,
                templateScore: 0,
                markerScore: 0,
                motionScore: 0,
                stabilityScore: 0,
                sizeScore: 0,
                searchMode: searchMode
            )
        }

        let resizedGray = patch.resizedGray(width: longTermTemplate.width, height: longTermTemplate.height)
        let templateScore = max(
            normalizedCorrelation(lhs: resizedGray, rhs: shortTermTemplate.gray),
            normalizedCorrelation(lhs: resizedGray, rhs: longTermTemplate.gray)
        )

        let markerScore: Double = {
            guard let markerModel else { return 0 }
            let ratio = patch.markerMask(model: markerModel).ratio
            guard markerModel.referenceRatio > 0 else { return 0 }
            return clamp(ratio / markerModel.referenceRatio)
        }()

        let motionScore: Double = {
            guard let referencePatch = referenceFrame.patch(bbox: bbox),
                  referencePatch.width == patch.width,
                  referencePatch.height == patch.height else {
                return 0
            }
            return scaledMotionDifference(current: patch.gray, reference: referencePatch.gray)
        }()

        let distance = hypot(bbox.center.x - predictedBBox.center.x, bbox.center.y - predictedBBox.center.y)
        let reference = max(predictedBBox.width, predictedBBox.height, 1)
        let stabilityScore = max(0, 1 - (distance / (reference * 2)))
        let areaRatio = bbox.area / max(predictedBBox.area, 1)
        let sizeScore = max(0, 1 - abs(1 - areaRatio))
        let brightnessScore = clamp(patch.gray.map(Double.init).mean())
        let aspectRatio = bbox.width / max(bbox.height, 1e-6)
        let circularityScore = max(0, 1 - abs(1 - aspectRatio))
        let elongatedScore = clamp(abs(aspectRatio - 1) / 1.5)

        let score: Double
        switch activeProfile {
        case .marker:
            score = (
                (0.34 * max(templateScore, 0)) +
                (0.36 * markerScore) +
                (0.12 * motionScore) +
                (0.10 * stabilityScore) +
                (0.08 * sizeScore)
            )
        case .bright:
            score = (
                (0.42 * max(templateScore, 0)) +
                (0.18 * brightnessScore) +
                (0.16 * motionScore) +
                (0.14 * stabilityScore) +
                (0.10 * sizeScore)
            )
        case .dark:
            score = (
                (0.42 * max(templateScore, 0)) +
                (0.18 * (1 - brightnessScore)) +
                (0.16 * motionScore) +
                (0.14 * stabilityScore) +
                (0.10 * sizeScore)
            )
        case .circular:
            score = (
                (0.40 * max(templateScore, 0)) +
                (0.18 * circularityScore) +
                (0.14 * motionScore) +
                (0.14 * stabilityScore) +
                (0.14 * sizeScore)
            )
        case .elongated:
            score = (
                (0.40 * max(templateScore, 0)) +
                (0.18 * elongatedScore) +
                (0.14 * motionScore) +
                (0.14 * stabilityScore) +
                (0.14 * sizeScore)
            )
        case .generic:
            score = (
                (0.46 * max(templateScore, 0)) +
                (0.12 * markerScore) +
                (0.16 * motionScore) +
                (0.16 * stabilityScore) +
                (0.10 * sizeScore)
            )
        }

        return NativeScoredCandidate(
            bbox: bbox.clipped(frameWidth: frameWidth, frameHeight: frameHeight),
            score: clamp(score),
            templateScore: clamp(templateScore),
            markerScore: clamp(markerScore),
            motionScore: clamp(motionScore),
            stabilityScore: clamp(stabilityScore),
            sizeScore: clamp(sizeScore),
            searchMode: searchMode
        )
    }

    private func failureReason(for candidate: NativeScoredCandidate) -> String {
        let lowConfidenceThreshold = resolvedTrackingConfig.lowConfidenceThreshold ?? TrackingConfigSnapshot.pythonDefaults.lowConfidenceThreshold ?? 0.36
        if candidate.searchMode == .full, candidate.score < lowConfidenceThreshold {
            return "search_exhausted"
        }
        if activeProfile == .marker, candidate.markerScore < 0.20 {
            return "marker_missing"
        }
        if candidate.templateScore < 0.20, candidate.motionScore < 0.08 {
            return "weak_visual_signal"
        }
        if candidate.motionScore < 0.05 {
            return "motion_only_prediction"
        }
        return "low_confidence"
    }

    private func refineMarkerBBox(
        frame: NativeTrackerImage,
        bbox: BBoxSnapshot
    ) -> (bbox: BBoxSnapshot, centroid: CGPoint?) {
        guard activeProfile == .marker, let markerModel, let patch = frame.patch(bbox: bbox) else {
            return (bbox, nil)
        }
        let mask = patch.markerMask(model: markerModel)
        guard mask.nonZeroCount >= 10, let centroid = mask.centroid(width: patch.width, height: patch.height) else {
            return (bbox, nil)
        }
        let globalCentroid = CGPoint(x: bbox.x + centroid.x, y: bbox.y + centroid.y)
        let refined = BBoxSnapshot(
            x: globalCentroid.x - (bbox.width / 2),
            y: globalCentroid.y - (bbox.height / 2),
            width: bbox.width,
            height: bbox.height
        ).clipped(frameWidth: frameWidth, frameHeight: frameHeight)
        return (refined, globalCentroid)
    }

    private func updateTemplates(frame: NativeTrackerImage, bbox: BBoxSnapshot, confidence: Double) {
        let stableUpdateThreshold = resolvedTrackingConfig.stableUpdateThreshold ?? TrackingConfigSnapshot.pythonDefaults.stableUpdateThreshold ?? 0.66
        guard confidence >= stableUpdateThreshold, state != .suspect, state != .lost,
              let patch = frame.patch(bbox: bbox) else {
            return
        }
        let resized = patch.resizedGray(width: shortTermTemplate.width, height: shortTermTemplate.height)
        let rate = resolvedTrackingConfig.templateUpdateRate ?? TrackingConfigSnapshot.pythonDefaults.templateUpdateRate ?? 0.10
        shortTermTemplate.gray = zip(shortTermTemplate.gray, resized).map {
            Float((Double($0.0) * (1 - rate)) + (Double($0.1) * rate))
        }
    }

    private static func resolveProfile(
        requestedProfile: TrackingProfileOption,
        templatePatch: NativeTrackerPatch,
        markerModel: NativeMarkerModel?
    ) -> NativeResolvedTrackingProfile {
        switch requestedProfile {
        case .marker:
            return .marker
        case .template:
            return .generic
        case .auto:
            if let markerModel, markerModel.referenceRatio >= 0.12 {
                return .marker
            }
            let meanIntensity = templatePatch.gray.map(Double.init).mean() * 255
            let aspectRatio = Double(templatePatch.width) / max(Double(templatePatch.height), 1)
            if meanIntensity >= 180 {
                return .bright
            }
            if meanIntensity <= 75 {
                return .dark
            }
            if aspectRatio >= 0.78, aspectRatio <= 1.22 {
                return .circular
            }
            if aspectRatio >= 1.5 || aspectRatio <= 0.67 {
                return .elongated
            }
            return .generic
        }
    }

    private static func buildMarkerModel(
        patch: NativeTrackerPatch,
        minimumRatio: Double
    ) -> NativeMarkerModel? {
        let hsv = patch.hsv
        guard !hsv.isEmpty else { return nil }
        let saturated = hsv.filter { $0.1 > 45 && $0.2 > 35 }
        let samples = saturated.count >= 20 ? saturated : hsv
        guard samples.count >= 20 else { return nil }

        let hueValues = samples.map(\.0).sorted()
        let saturationValues = samples.map(\.1).sorted()
        let valueValues = samples.map(\.2).sorted()
        let lower = (
            percentile(sorted: hueValues, quantile: 0.10),
            percentile(sorted: saturationValues, quantile: 0.10),
            percentile(sorted: valueValues, quantile: 0.10)
        )
        let upper = (
            percentile(sorted: hueValues, quantile: 0.90),
            percentile(sorted: saturationValues, quantile: 0.90),
            percentile(sorted: valueValues, quantile: 0.90)
        )

        let model = NativeMarkerModel(
            lowHue: max(0, lower.0 - 8),
            highHue: min(179, upper.0 + 8),
            lowSaturation: max(20, lower.1 - 28),
            highSaturation: min(255, upper.1 + 28),
            lowValue: max(20, lower.2 - 28),
            highValue: min(255, upper.2 + 28),
            referenceRatio: 0
        )
        let mask = patch.markerMask(model: model)
        let ratio = mask.ratio
        guard ratio >= minimumRatio else { return nil }
        var resolved = model
        resolved.referenceRatio = ratio
        return resolved
    }

    private static func percentile(sorted: [Double], quantile: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = max(0, min(Double(sorted.count - 1), Double(sorted.count - 1) * quantile))
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }
        let alpha = position - Double(lowerIndex)
        return sorted[lowerIndex] + ((sorted[upperIndex] - sorted[lowerIndex]) * alpha)
    }
}

private struct NativeTrackerImage {
    var width: Int
    var height: Int
    var rgba: [UInt8]
    var gray: [Float]

    init(cgImage: CGImage) throws {
        width = cgImage.width
        height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        rgba = Array(repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NativeTrackingRuntimeError.invalidInitialTemplate
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        gray = Array(repeating: 0, count: width * height)
        for pixelIndex in 0..<(width * height) {
            let base = pixelIndex * bytesPerPixel
            let red = Float(rgba[base]) / 255
            let green = Float(rgba[base + 1]) / 255
            let blue = Float(rgba[base + 2]) / 255
            gray[pixelIndex] = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        }
    }

    init(width: Int, height: Int, rgba: [UInt8], gray: [Float]) {
        self.width = width
        self.height = height
        self.rgba = rgba
        self.gray = gray
    }

    func patch(bbox: BBoxSnapshot) -> NativeTrackerPatch? {
        let rect = clampedRect(bbox.integerRect, maxWidth: width, maxHeight: height)
        return patch(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    func patch(x: Int, y: Int, width: Int, height: Int) -> NativeTrackerPatch? {
        guard width > 0, height > 0, x >= 0, y >= 0, x + width <= self.width, y + height <= self.height else {
            return nil
        }
        var patchRGBA = Array(repeating: UInt8.zero, count: width * height * 4)
        var patchGray = Array(repeating: Float.zero, count: width * height)
        for row in 0..<height {
            let sourcePixelOffset = ((y + row) * self.width) + x
            let targetPixelOffset = row * width
            for column in 0..<width {
                let sourceIndex = sourcePixelOffset + column
                let targetIndex = targetPixelOffset + column
                patchGray[targetIndex] = gray[sourceIndex]
                let sourceBase = sourceIndex * 4
                let targetBase = targetIndex * 4
                patchRGBA[targetBase] = rgba[sourceBase]
                patchRGBA[targetBase + 1] = rgba[sourceBase + 1]
                patchRGBA[targetBase + 2] = rgba[sourceBase + 2]
                patchRGBA[targetBase + 3] = rgba[sourceBase + 3]
            }
        }
        return NativeTrackerPatch(width: width, height: height, rgba: patchRGBA, gray: patchGray)
    }
}

private struct NativeTrackerPatch {
    var width: Int
    var height: Int
    var rgba: [UInt8]
    var gray: [Float]

    var hsv: [(Double, Double, Double)] {
        (0..<(width * height)).map { index in
            let base = index * 4
            let red = Double(rgba[base]) / 255
            let green = Double(rgba[base + 1]) / 255
            let blue = Double(rgba[base + 2]) / 255
            return rgbToHSV(red: red, green: green, blue: blue)
        }
    }

    func resizedGray(width targetWidth: Int, height targetHeight: Int) -> [Float] {
        guard targetWidth > 0, targetHeight > 0 else { return [] }
        if targetWidth == width, targetHeight == height {
            return gray
        }

        var result = Array(repeating: Float.zero, count: targetWidth * targetHeight)
        let xScale = Double(width) / Double(targetWidth)
        let yScale = Double(height) / Double(targetHeight)
        for y in 0..<targetHeight {
            let sourceY = min(height - 1, Int((Double(y) * yScale).rounded(.down)))
            for x in 0..<targetWidth {
                let sourceX = min(width - 1, Int((Double(x) * xScale).rounded(.down)))
                result[(y * targetWidth) + x] = gray[(sourceY * width) + sourceX]
            }
        }
        return result
    }

    func markerMask(model: NativeMarkerModel) -> NativeBinaryMask {
        var values = Array(repeating: UInt8.zero, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            let red = Double(rgba[base]) / 255
            let green = Double(rgba[base + 1]) / 255
            let blue = Double(rgba[base + 2]) / 255
            let hsv = rgbToHSV(red: red, green: green, blue: blue)
            let isMatch = hsv.0 >= model.lowHue && hsv.0 <= model.highHue &&
                hsv.1 >= model.lowSaturation && hsv.1 <= model.highSaturation &&
                hsv.2 >= model.lowValue && hsv.2 <= model.highValue
            values[index] = isMatch ? 1 : 0
        }
        return NativeBinaryMask(width: width, height: height, values: values)
    }

    func motionMask(against reference: NativeTrackerPatch, threshold: Double) -> NativeBinaryMask {
        let values = zip(gray, reference.gray).map { abs(Double($0 - $1)) >= threshold ? UInt8(1) : UInt8(0) }
        return NativeBinaryMask(width: width, height: height, values: values)
    }
}

private struct NativeTemplatePatch {
    var width: Int
    var height: Int
    var gray: [Float]

    init(from patch: NativeTrackerPatch) {
        self.width = patch.width
        self.height = patch.height
        self.gray = patch.gray
    }
}

private struct NativeBinaryMask {
    var width: Int
    var height: Int
    var values: [UInt8]

    var ratio: Double {
        guard !values.isEmpty else { return 0 }
        return Double(nonZeroCount) / Double(values.count)
    }

    var nonZeroCount: Int {
        values.reduce(into: 0) { partial, value in
            if value != 0 { partial += 1 }
        }
    }

    func eroded(radius: Int) -> NativeBinaryMask {
        guard radius > 0 else { return self }
        return applying(radius: radius, requireAll: true)
    }

    func dilated(radius: Int) -> NativeBinaryMask {
        guard radius > 0 else { return self }
        return applying(radius: radius, requireAll: false)
    }

    func opened(radius: Int) -> NativeBinaryMask {
        eroded(radius: radius).dilated(radius: radius)
    }

    func closed(radius: Int) -> NativeBinaryMask {
        dilated(radius: radius).eroded(radius: radius)
    }

    func centroid(width: Int, height: Int) -> CGPoint? {
        guard nonZeroCount > 0 else { return nil }
        var xSum = 0.0
        var ySum = 0.0
        var count = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width) + x
                guard values[index] != 0 else { continue }
                xSum += Double(x)
                ySum += Double(y)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return CGPoint(x: xSum / count, y: ySum / count)
    }

    func connectedBoundingBoxes(width: Int, height: Int) -> [BBoxSnapshot] {
        guard width > 0, height > 0, values.count == width * height else { return [] }
        var visited = Array(repeating: false, count: values.count)
        var components: [BBoxSnapshot] = []
        let offsets = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0),           (1, 0),
            (-1, 1),  (0, 1),  (1, 1),
        ]

        for y in 0..<height {
            for x in 0..<width {
                let startIndex = (y * width) + x
                guard values[startIndex] != 0, !visited[startIndex] else { continue }
                var queue = [(x, y)]
                visited[startIndex] = true
                var minX = x
                var minY = y
                var maxX = x
                var maxY = y

                while let (currentX, currentY) = queue.popLast() {
                    minX = min(minX, currentX)
                    minY = min(minY, currentY)
                    maxX = max(maxX, currentX)
                    maxY = max(maxY, currentY)

                    for (offsetX, offsetY) in offsets {
                        let nextX = currentX + offsetX
                        let nextY = currentY + offsetY
                        guard nextX >= 0, nextY >= 0, nextX < width, nextY < height else { continue }
                        let nextIndex = (nextY * width) + nextX
                        guard values[nextIndex] != 0, !visited[nextIndex] else { continue }
                        visited[nextIndex] = true
                        queue.append((nextX, nextY))
                    }
                }

                components.append(
                    BBoxSnapshot(
                        x: Double(minX),
                        y: Double(minY),
                        width: Double((maxX - minX) + 1),
                        height: Double((maxY - minY) + 1)
                    )
                )
            }
        }

        return components
    }

    private func applying(radius: Int, requireAll: Bool) -> NativeBinaryMask {
        guard width > 0, height > 0, values.count == width * height else { return self }
        var result = Array(repeating: UInt8.zero, count: values.count)

        for y in 0..<height {
            for x in 0..<width {
                var matched = requireAll
                for sampleY in max(0, y - radius)...min(height - 1, y + radius) {
                    for sampleX in max(0, x - radius)...min(width - 1, x + radius) {
                        let value = values[(sampleY * width) + sampleX] != 0
                        if requireAll {
                            matched = matched && value
                            if !matched { break }
                        } else {
                            matched = matched || value
                            if matched { break }
                        }
                    }
                    if requireAll && !matched { break }
                    if !requireAll && matched { break }
                }
                result[(y * width) + x] = matched ? 1 : 0
            }
        }

        return NativeBinaryMask(width: width, height: height, values: result)
    }
}

enum NativeTrackRuntimeDerivation {
    static func emptyQuality() -> TrackQualitySnapshot {
        TrackQualitySnapshot(
            lostSpans: nil,
            suspectSpans: nil,
            correctedSpans: nil,
            reacquisitionCount: nil,
            reviewRecommended: nil
        )
    }

    static func interpolateShortGaps(
        _ observations: [NativeTrackingObservation],
        config: TrackingConfigSnapshot
    ) -> [NativeTrackingObservation] {
        guard config.interpolateShortGaps ?? true, observations.count >= 3 else { return observations }
        var interpolated = observations
        let maxGap = config.maxInterpolationGap ?? TrackingConfigSnapshot.pythonDefaults.maxInterpolationGap ?? 3
        var index = 1
        while index < interpolated.count - 1 {
            if !interpolated[index].lost {
                index += 1
                continue
            }
            let start = index
            var end = index
            while end + 1 < interpolated.count, interpolated[end + 1].lost {
                end += 1
            }
            let gap = end - start + 1
            if gap > maxGap || start == 0 || end >= interpolated.count - 1 {
                index = end + 1
                continue
            }

            let previous = interpolated[start - 1]
            let following = interpolated[end + 1]
            if previous.lost || following.lost {
                index = end + 1
                continue
            }

            for (offset, targetIndex) in Array(start...end).enumerated() {
                let alpha = Double(offset + 1) / Double(gap + 1)
                let bbox = BBoxSnapshot(
                    x: ((1 - alpha) * previous.bbox.x) + (alpha * following.bbox.x),
                    y: ((1 - alpha) * previous.bbox.y) + (alpha * following.bbox.y),
                    width: ((1 - alpha) * previous.bbox.width) + (alpha * following.bbox.width),
                    height: ((1 - alpha) * previous.bbox.height) + (alpha * following.bbox.height)
                )
                var debug = interpolated[targetIndex].debug
                debug["interpolation"] = "linear_short_gap"
                interpolated[targetIndex] = NativeTrackingObservation(
                    frameIndex: interpolated[targetIndex].frameIndex,
                    timeSeconds: interpolated[targetIndex].timeSeconds,
                    centroidXPixels: ((1 - alpha) * previous.centroidXPixels) + (alpha * following.centroidXPixels),
                    centroidYPixels: ((1 - alpha) * previous.centroidYPixels) + (alpha * following.centroidYPixels),
                    bbox: bbox,
                    confidence: min(previous.confidence, following.confidence) * 0.72,
                    lost: false,
                    corrected: interpolated[targetIndex].corrected,
                    state: NativeTrackingState.suspect.rawValue,
                    failureReason: "short_gap_interpolated",
                    source: "interpolated",
                    isInferred: true,
                    isInterpolated: true,
                    debug: debug,
                    trackID: interpolated[targetIndex].trackID,
                    trackName: interpolated[targetIndex].trackName,
                    trackKind: interpolated[targetIndex].trackKind
                )
            }

            index = end + 1
        }
        return interpolated
    }

    static func computeQualityMetadata(
        observations: [NativeTrackingObservation]
    ) -> TrackQualitySnapshot {
        let lostSpans = buildSpans(observations: observations, reason: "lost_tracking") { $0.lost }
        let suspectSpans = buildSpans(observations: observations, reason: "tracking_recovery") {
            $0.state == NativeTrackingState.suspect.rawValue || $0.state == NativeTrackingState.reacquired.rawValue
        }
        let correctedSpans = buildSpans(observations: observations, reason: "manual_correction") { $0.corrected }
        let reacquisitionCount = observations.filter { $0.state == NativeTrackingState.reacquired.rawValue }.count
        let reviewRecommended = !lostSpans.isEmpty || !suspectSpans.isEmpty || observations.contains { $0.confidence < 0.35 }
        return TrackQualitySnapshot(
            lostSpans: lostSpans,
            suspectSpans: suspectSpans,
            correctedSpans: correctedSpans,
            reacquisitionCount: reacquisitionCount,
            reviewRecommended: reviewRecommended
        )
    }

    static func buildSpans(
        observations: [NativeTrackingObservation],
        reason: String,
        predicate: (NativeTrackingObservation) -> Bool
    ) -> [TrackSpanSnapshot] {
        var spans: [TrackSpanSnapshot] = []
        var startFrame: Int?
        var endFrame: Int?
        for observation in observations {
            let active = predicate(observation)
            if active, startFrame == nil {
                startFrame = observation.frameIndex
            }
            if active {
                endFrame = observation.frameIndex
            }
            if !active, let resolvedStart = startFrame, let resolvedEnd = endFrame {
                spans.append(TrackSpanSnapshot(startFrame: resolvedStart, endFrame: resolvedEnd, reason: reason))
                startFrame = nil
                endFrame = nil
            }
        }
        if let startFrame, let endFrame {
            spans.append(TrackSpanSnapshot(startFrame: startFrame, endFrame: endFrame, reason: reason))
        }
        return spans
    }
}

private func normalizedCorrelation(lhs: [Float], rhs: [Float]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
    let lhsMean = lhs.map(Double.init).mean()
    let rhsMean = rhs.map(Double.init).mean()
    var numerator = 0.0
    var lhsDenominator = 0.0
    var rhsDenominator = 0.0
    for index in lhs.indices {
        let lhsValue = Double(lhs[index]) - lhsMean
        let rhsValue = Double(rhs[index]) - rhsMean
        numerator += lhsValue * rhsValue
        lhsDenominator += lhsValue * lhsValue
        rhsDenominator += rhsValue * rhsValue
    }
    let denominator = sqrt(lhsDenominator * rhsDenominator)
    guard denominator > 1e-12 else { return 0 }
    return clamp(numerator / denominator)
}

private func scaledMotionDifference(current: [Float], reference: [Float]) -> Double {
    guard current.count == reference.count, !current.isEmpty else { return 0 }
    let rawDifference = zip(current, reference).map { abs(Double($0.0 - $0.1)) }.mean()
    // Python computes motion on a contrast-equalized, blurred grayscale patch.
    // Our native patches use direct luminance, so we damp the raw delta to keep
    // recovery thresholds aligned with the Python tracker.
    return clamp(rawDifference * 0.55)
}

private func rgbToHSV(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum

    let hue: Double
    if delta == 0 {
        hue = 0
    } else if maximum == red {
        hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
    } else if maximum == green {
        hue = ((blue - red) / delta) + 2
    } else {
        hue = ((red - green) / delta) + 4
    }
    let normalizedHue = ((hue * 30).truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
    let saturation = maximum == 0 ? 0 : (delta / maximum) * 255
    let value = maximum * 255
    return (normalizedHue, saturation, value)
}

private func clamp(_ value: Double, minimum: Double = 0, maximum: Double = 1) -> Double {
    max(minimum, min(maximum, value))
}

private extension Array where Element == Double {
    func mean() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

private extension BBoxSnapshot {
    var center: CGPoint {
        CGPoint(x: x + (width / 2), y: y + (height / 2))
    }

    var area: Double {
        max(width, 0) * max(height, 0)
    }

    var deduplicationKey: String {
        let rect = integerRect
        return "\(rect.x)|\(rect.y)|\(rect.width)|\(rect.height)"
    }

    var integerRect: (x: Int, y: Int, width: Int, height: Int) {
        (
            Int(x.rounded()),
            Int(y.rounded()),
            max(1, Int(width.rounded())),
            max(1, Int(height.rounded()))
        )
    }

    func clipped(frameWidth: Int, frameHeight: Int) -> BBoxSnapshot {
        let clippedX = min(max(x, 0), max(Double(frameWidth) - 1, 0))
        let clippedY = min(max(y, 0), max(Double(frameHeight) - 1, 0))
        let clippedWidth = min(width, max(Double(frameWidth) - clippedX, 1))
        let clippedHeight = min(height, max(Double(frameHeight) - clippedY, 1))
        return BBoxSnapshot(x: clippedX, y: clippedY, width: clippedWidth, height: clippedHeight)
    }
}

private func clampedRect(
    _ rect: (x: Int, y: Int, width: Int, height: Int),
    maxWidth: Int,
    maxHeight: Int
) -> (x: Int, y: Int, width: Int, height: Int) {
    let x = min(max(rect.x, 0), max(maxWidth - 1, 0))
    let y = min(max(rect.y, 0), max(maxHeight - 1, 0))
    let width = min(max(rect.width, 1), max(maxWidth - x, 1))
    let height = min(max(rect.height, 1), max(maxHeight - y, 1))
    return (x, y, width, height)
}
