import AVFoundation
import CoreGraphics
import Foundation

struct NativeVideoMetadata: Codable, Hashable {
    var path: String
    var fps: Double
    var frameCount: Int
    var width: Int
    var height: Int
    var durationSeconds: Double
    var nominalFrameDurationSeconds: Double

    var presentationSize: CGSize {
        CGSize(width: width, height: height)
    }
}

struct NativeVideoFrame {
    var frameIndex: Int
    var timestamp: Double
    var image: CGImage
}

enum NativeVideoSourceError: LocalizedError {
    case missingVideoTrack(URL)
    case invalidFrameIndex(Int)
    case zeroStep
    case unreadableFrame(Int)
    case unreadableAsset(URL)

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack(let url):
            return "No readable video track was found in \(url.lastPathComponent)."
        case .invalidFrameIndex(let index):
            return "Frame index \(index) is outside the available video range."
        case .zeroStep:
            return "Frame iteration step must not be 0."
        case .unreadableFrame(let index):
            return "The native video reader could not decode frame \(index)."
        case .unreadableAsset(let url):
            return "Unable to load frame timing metadata for \(url.lastPathComponent)."
        }
    }
}

final class NativeVideoSource {
    let url: URL
    let metadata: NativeVideoMetadata

    private let sampleTimes: [CMTime]
    private let imageGenerator: AVAssetImageGenerator

    private init(
        url: URL,
        metadata: NativeVideoMetadata,
        sampleTimes: [CMTime],
        imageGenerator: AVAssetImageGenerator
    ) {
        self.url = url
        self.metadata = metadata
        self.sampleTimes = sampleTimes
        self.imageGenerator = imageGenerator
    }

    static func open(url: URL) async throws -> NativeVideoSource {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw NativeVideoSourceError.missingVideoTrack(url)
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = max(Int(abs(transformedSize.width).rounded()), 0)
        let height = max(Int(abs(transformedSize.height).rounded()), 0)

        let nominalFrameRate = Double(try await track.load(.nominalFrameRate))
        let durationSeconds = Self.resolvedDurationSeconds(duration)
        let sampleTimes = try Self.loadSampleTimes(asset: asset, track: track, url: url)

        let fps = Self.resolvedFPS(
            nominalFrameRate: nominalFrameRate,
            frameCount: sampleTimes.count,
            durationSeconds: durationSeconds
        )
        let frameCount = Self.resolvedFrameCount(
            sampleTimes: sampleTimes,
            fps: fps,
            durationSeconds: durationSeconds
        )
        guard frameCount > 0 else {
            throw NativeVideoSourceError.unreadableAsset(url)
        }

        let resolvedTimes = Self.resolvedSampleTimes(
            sampleTimes: sampleTimes,
            frameCount: frameCount,
            fps: fps
        )

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        let metadata = NativeVideoMetadata(
            path: url.path,
            fps: fps,
            frameCount: frameCount,
            width: width,
            height: height,
            durationSeconds: durationSeconds > 0 ? durationSeconds : Double(frameCount) / fps,
            nominalFrameDurationSeconds: 1.0 / fps
        )

        return NativeVideoSource(
            url: url,
            metadata: metadata,
            sampleTimes: resolvedTimes,
            imageGenerator: imageGenerator
        )
    }

    func frameTimestamp(forFrameIndex frameIndex: Int) throws -> Double {
        try validate(frameIndex: frameIndex)
        return Double(frameIndex) / metadata.fps
    }

    func presentationTime(forFrameIndex frameIndex: Int) throws -> CMTime {
        try validate(frameIndex: frameIndex)
        return sampleTimes[frameIndex]
    }

    func readFrame(atFrameIndex frameIndex: Int) throws -> NativeVideoFrame {
        let time = try presentationTime(forFrameIndex: frameIndex)
        do {
            let image = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return NativeVideoFrame(
                frameIndex: frameIndex,
                timestamp: try frameTimestamp(forFrameIndex: frameIndex),
                image: image
            )
        } catch {
            throw NativeVideoSourceError.unreadableFrame(frameIndex)
        }
    }

    func readFrames(
        startFrame: Int = 0,
        endFrame: Int? = nil,
        step: Int = 1
    ) throws -> [NativeVideoFrame] {
        try resolvedFrameIndices(
            startFrame: startFrame,
            endFrame: endFrame,
            step: step
        ).map { frameIndex in
            try readFrame(atFrameIndex: frameIndex)
        }
    }

    func forEachFrame(
        startFrame: Int = 0,
        endFrame: Int? = nil,
        step: Int = 1,
        _ body: (NativeVideoFrame) throws -> Void
    ) throws {
        for index in try resolvedFrameIndices(
            startFrame: startFrame,
            endFrame: endFrame,
            step: step
        ) {
            try body(try readFrame(atFrameIndex: index))
        }
    }

    private func validate(frameIndex: Int) throws {
        let lastFrameIndex = metadata.frameCount - 1
        guard frameIndex >= 0, frameIndex <= lastFrameIndex else {
            throw NativeVideoSourceError.invalidFrameIndex(frameIndex)
        }
    }

    private func resolvedFrameIndices(
        startFrame: Int,
        endFrame: Int?,
        step: Int
    ) throws -> [Int] {
        guard step != 0 else {
            throw NativeVideoSourceError.zeroStep
        }
        try validate(frameIndex: startFrame)
        let terminalFrame = endFrame ?? (step > 0 ? metadata.frameCount - 1 : 0)
        try validate(frameIndex: terminalFrame)

        if step > 0, startFrame > terminalFrame {
            return []
        }
        if step < 0, startFrame < terminalFrame {
            return []
        }

        var indices: [Int] = []
        var currentFrame = startFrame
        if step > 0 {
            while currentFrame <= terminalFrame {
                indices.append(currentFrame)
                currentFrame += step
            }
        } else {
            while currentFrame >= terminalFrame {
                indices.append(currentFrame)
                currentFrame += step
            }
        }
        return indices
    }

    private static func loadSampleTimes(asset: AVAsset, track: AVAssetTrack, url: URL) throws -> [CMTime] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NativeVideoSourceError.unreadableAsset(url)
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NativeVideoSourceError.unreadableAsset(url)
        }

        var times: [CMTime] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            times.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }

        if reader.status == .failed {
            throw reader.error ?? NativeVideoSourceError.unreadableAsset(url)
        }
        return times
    }

    private static func resolvedDurationSeconds(_ duration: CMTime) -> Double {
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }
        return seconds
    }

    private static func resolvedFPS(
        nominalFrameRate: Double,
        frameCount: Int,
        durationSeconds: Double
    ) -> Double {
        if nominalFrameRate > 0 {
            return nominalFrameRate
        }
        if frameCount > 0, durationSeconds > 0 {
            return Double(frameCount) / durationSeconds
        }
        return 30.0
    }

    private static func resolvedFrameCount(
        sampleTimes: [CMTime],
        fps: Double,
        durationSeconds: Double
    ) -> Int {
        if durationSeconds > 0, fps > 0 {
            return max(Int((durationSeconds * fps).rounded()), 0)
        }
        return sampleTimes.count
    }

    private static func resolvedSampleTimes(
        sampleTimes: [CMTime],
        frameCount: Int,
        fps: Double
    ) -> [CMTime] {
        if sampleTimes.count == frameCount {
            return sampleTimes
        }

        let preferredTimescale: CMTimeScale = 600
        return (0..<frameCount).map { frameIndex in
            CMTime(
                seconds: Double(frameIndex) / fps,
                preferredTimescale: preferredTimescale
            )
        }
    }
}
