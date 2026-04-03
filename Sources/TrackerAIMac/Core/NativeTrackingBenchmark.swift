import Foundation

enum NativeTrackingBenchmarkError: LocalizedError {
    case missingRepositoryRoot
    case noOverlappingAnnotations(String)

    var errorDescription: String? {
        switch self {
        case .missingRepositoryRoot:
            return "The native benchmark harness could not infer the repository root for sample data."
        case .noOverlappingAnnotations(let clipName):
            return "No overlapping annotations were found for benchmark clip '\(clipName)'."
        }
    }
}

struct NativeBenchmarkAnnotation {
    var frameIndex: Int
    var centroidXPixels: Double
    var centroidYPixels: Double
    var bbox: BBoxSnapshot
}

struct NativeBenchmarkClip {
    var name: String
    var videoURL: URL
    var startFrame: Int
    var initialBBox: BBoxSnapshot
    var tags: [String]
    var annotations: [NativeBenchmarkAnnotation]
}

struct NativeBenchmarkMetrics {
    var clipName: String
    var annotatedFrameCount: Int
    var medianCenterErrorPixels: Double
    var p95CenterErrorPixels: Double
    var meanIoU: Double
    var lostFrameRate: Double
    var reacquisitionLatencyFrames: Int
}

struct NativeBenchmarkSuiteMetrics {
    var clipMetrics: [NativeBenchmarkMetrics]
    var medianCenterErrorPixels: Double
    var p95CenterErrorPixels: Double
    var meanIoU: Double
    var lostFrameRate: Double
    var maxReacquisitionLatencyFrames: Int
}

struct NativeTrackingBenchmarkRunner {
    var trackingRunner = NativeSingleObjectTrackingRunner()
    var trackingConfig: TrackingConfigSnapshot = {
        var config = TrackingConfigSnapshot.pythonDefaults
        config.bidirectionalRefinement = false
        return config.resolved()
    }()

    func evaluateClip(_ clip: NativeBenchmarkClip) async throws -> NativeBenchmarkMetrics {
        let source = try await NativeVideoSource.open(url: clip.videoURL)
        let track = try trackingRunner.runSingleObjectTracking(
            video: source,
            initialBBox: clip.initialBBox,
            startFrame: clip.startFrame,
            config: trackingConfig
        )
        return try NativeTrackingBenchmark.evaluate(track: track, against: clip)
    }

    func evaluateSuite(
        manifestURL: URL,
        repositoryRoot: URL? = nil
    ) async throws -> NativeBenchmarkSuiteMetrics {
        let clips = try NativeTrackingBenchmark.loadClips(
            manifestURL: manifestURL,
            repositoryRoot: repositoryRoot
        )
        return try await NativeTrackingBenchmark.evaluateSuite(clips: clips) { clip in
            try await evaluateClip(clip)
        }
    }
}

enum NativeTrackingBenchmark {
    static func defaultManifestURL(repositoryRoot: URL? = inferredRepositoryRoot()) throws -> URL {
        guard let repositoryRoot else {
            throw NativeTrackingBenchmarkError.missingRepositoryRoot
        }
        return repositoryRoot.appendingPathComponent("sample_data/benchmark_manifest.json")
    }

    static func loadClips(
        manifestURL: URL,
        repositoryRoot: URL? = nil
    ) throws -> [NativeBenchmarkClip] {
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BenchmarkManifestPayload.self, from: data)
        let baseURL = repositoryRoot ?? manifestURL.deletingLastPathComponent()

        return manifest.clips.map { clip in
            let relativeVideoURL = URL(fileURLWithPath: clip.videoPath, relativeTo: manifestURL.deletingLastPathComponent())
            let fallbackVideoURL = baseURL.appendingPathComponent("sample_data").appendingPathComponent(clip.videoPath)
            let resolvedVideoURL: URL
            if FileManager.default.fileExists(atPath: relativeVideoURL.path) {
                resolvedVideoURL = relativeVideoURL.standardizedFileURL
            } else {
                resolvedVideoURL = fallbackVideoURL.standardizedFileURL
            }

            return NativeBenchmarkClip(
                name: clip.name,
                videoURL: resolvedVideoURL,
                startFrame: clip.startFrame,
                initialBBox: BBoxSnapshot(
                    x: clip.initialBBox[0],
                    y: clip.initialBBox[1],
                    width: clip.initialBBox[2],
                    height: clip.initialBBox[3]
                ),
                tags: clip.tags,
                annotations: clip.annotations.map { annotation in
                    NativeBenchmarkAnnotation(
                        frameIndex: annotation.frameIndex,
                        centroidXPixels: annotation.centroidXPx,
                        centroidYPixels: annotation.centroidYPx,
                        bbox: BBoxSnapshot(
                            x: annotation.bbox[0],
                            y: annotation.bbox[1],
                            width: annotation.bbox[2],
                            height: annotation.bbox[3]
                        )
                    )
                }
            )
        }
    }

    static func evaluate(
        track: NativeTrackResult,
        against clip: NativeBenchmarkClip
    ) throws -> NativeBenchmarkMetrics {
        let observationByFrame = track.observationByFrame()
        var centerErrors: [Double] = []
        var ious: [Double] = []
        var lostFrames = 0
        var annotatedIndices: [Int] = []

        for annotation in clip.annotations {
            guard let observation = observationByFrame[annotation.frameIndex] else { continue }
            annotatedIndices.append(annotation.frameIndex)
            centerErrors.append(
                hypot(
                    observation.centroidXPixels - annotation.centroidXPixels,
                    observation.centroidYPixels - annotation.centroidYPixels
                )
            )
            ious.append(iou(observation.bbox, annotation.bbox))
            if observation.lost {
                lostFrames += 1
            }
        }

        guard !centerErrors.isEmpty else {
            throw NativeTrackingBenchmarkError.noOverlappingAnnotations(clip.name)
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

        return NativeBenchmarkMetrics(
            clipName: clip.name,
            annotatedFrameCount: centerErrors.count,
            medianCenterErrorPixels: percentile(values: centerErrors, quantile: 0.5),
            p95CenterErrorPixels: percentile(values: centerErrors, quantile: 0.95),
            meanIoU: ious.reduce(0, +) / Double(ious.count),
            lostFrameRate: Double(lostFrames) / Double(centerErrors.count),
            reacquisitionLatencyFrames: reacquisitionLatency
        )
    }

    static func evaluateSuite(
        clips: [NativeBenchmarkClip],
        trackRunner: (NativeBenchmarkClip) async throws -> NativeBenchmarkMetrics
    ) async throws -> NativeBenchmarkSuiteMetrics {
        var clipMetrics: [NativeBenchmarkMetrics] = []
        clipMetrics.reserveCapacity(clips.count)

        for clip in clips {
            clipMetrics.append(try await trackRunner(clip))
        }

        return NativeBenchmarkSuiteMetrics(
            clipMetrics: clipMetrics,
            medianCenterErrorPixels: percentile(values: clipMetrics.map(\.medianCenterErrorPixels), quantile: 0.5),
            p95CenterErrorPixels: clipMetrics.map(\.p95CenterErrorPixels).max() ?? 0,
            meanIoU: clipMetrics.map(\.meanIoU).reduce(0, +) / Double(max(clipMetrics.count, 1)),
            lostFrameRate: clipMetrics.map(\.lostFrameRate).reduce(0, +) / Double(max(clipMetrics.count, 1)),
            maxReacquisitionLatencyFrames: clipMetrics.map(\.reacquisitionLatencyFrames).max() ?? 0
        )
    }

    static func inferredRepositoryRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func iou(_ lhs: BBoxSnapshot, _ rhs: BBoxSnapshot) -> Double {
        let ax1 = lhs.x
        let ay1 = lhs.y
        let ax2 = lhs.x + lhs.width
        let ay2 = lhs.y + lhs.height
        let bx1 = rhs.x
        let by1 = rhs.y
        let bx2 = rhs.x + rhs.width
        let by2 = rhs.y + rhs.height
        let interX1 = max(ax1, bx1)
        let interY1 = max(ay1, by1)
        let interX2 = min(ax2, bx2)
        let interY2 = min(ay2, by2)
        let interWidth = max(0, interX2 - interX1)
        let interHeight = max(0, interY2 - interY1)
        let intersection = interWidth * interHeight
        let union = lhs.width * lhs.height + rhs.width * rhs.height - intersection
        guard union > 0 else { return 0 }
        return intersection / union
    }

    private static func percentile(values: [Double], quantile: Double) -> Double {
        let sorted = values.sorted()
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let boundedQuantile = max(0, min(1, quantile))
        let position = Double(sorted.count - 1) * boundedQuantile
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }
        let alpha = position - Double(lowerIndex)
        return sorted[lowerIndex] + ((sorted[upperIndex] - sorted[lowerIndex]) * alpha)
    }
}

private struct BenchmarkManifestPayload: Decodable {
    var clips: [BenchmarkManifestClipPayload]
}

private struct BenchmarkManifestClipPayload: Decodable {
    var name: String
    var videoPath: String
    var startFrame: Int
    var initialBBox: [Double]
    var tags: [String]
    var annotations: [BenchmarkManifestAnnotationPayload]

    enum CodingKeys: String, CodingKey {
        case name
        case videoPath = "video_path"
        case startFrame = "start_frame"
        case initialBBox = "initial_bbox"
        case tags
        case annotations
    }
}

private struct BenchmarkManifestAnnotationPayload: Decodable {
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
