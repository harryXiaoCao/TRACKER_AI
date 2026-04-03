import Foundation
import XCTest
@testable import TrackerAIMac

final class NativeVideoSourceTests: XCTestCase {
    func testMetadataAndTimestampsMatchPythonFixtures() async throws {
        for fixture in try loadFixtures() {
            let source = try await NativeVideoSource.open(url: repositoryRoot.appendingPathComponent(fixture.path))

            XCTAssertEqual(source.metadata.frameCount, fixture.frameCount, "Frame count mismatch for \(fixture.path)")
            XCTAssertEqual(source.metadata.width, fixture.width, "Width mismatch for \(fixture.path)")
            XCTAssertEqual(source.metadata.height, fixture.height, "Height mismatch for \(fixture.path)")
            XCTAssertEqual(source.metadata.fps, fixture.fps, accuracy: 1e-9, "FPS mismatch for \(fixture.path)")
            XCTAssertEqual(source.metadata.durationSeconds, fixture.durationSeconds, accuracy: 1e-9, "Duration mismatch for \(fixture.path)")

            for (frameIndex, expectedTimestamp) in fixture.orderedTimestamps {
                XCTAssertEqual(
                    try source.frameTimestamp(forFrameIndex: frameIndex),
                    expectedTimestamp,
                    accuracy: 1e-9,
                    "Timestamp mismatch for \(fixture.path) frame \(frameIndex)"
                )
            }
        }
    }

    func testRandomAccessReturnsExpectedFrames() async throws {
        let fixture = try XCTUnwrap(try loadFixtures().first(where: { $0.path == "sample_data/projectile_sample.mp4" }))
        let source = try await NativeVideoSource.open(url: repositoryRoot.appendingPathComponent(fixture.path))
        let frame: NativeVideoFrame
        do {
            frame = try source.readFrame(atFrameIndex: 15)
        } catch {
            try skipIfVideoDecodingUnsupported(error)
            throw error
        }
        XCTAssertEqual(frame.frameIndex, 15)
        XCTAssertEqual(frame.timestamp, 0.25, accuracy: 1e-9)
        XCTAssertEqual(frame.image.width, fixture.width)
        XCTAssertEqual(frame.image.height, fixture.height)
    }

    func testInclusiveFrameRangesMatchPythonSemantics() async throws {
        let source = try await NativeVideoSource.open(
            url: repositoryRoot.appendingPathComponent("sample_data/projectile_sample.mp4")
        )

        let forwardFrames: [NativeVideoFrame]
        do {
            forwardFrames = try source.readFrames(startFrame: 3, endFrame: 7, step: 2)
        } catch {
            try skipIfVideoDecodingUnsupported(error)
            throw error
        }
        XCTAssertEqual(forwardFrames.map(\.frameIndex), [3, 5, 7])

        let reverseFrames: [NativeVideoFrame]
        do {
            reverseFrames = try source.readFrames(startFrame: 7, endFrame: 3, step: -2)
        } catch {
            try skipIfVideoDecodingUnsupported(error)
            throw error
        }
        XCTAssertEqual(reverseFrames.map(\.frameIndex), [7, 5, 3])
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadFixtures() throws -> [VideoReaderFixture] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "video_reader_fixtures", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([VideoReaderFixture].self, from: data)
    }
}

private struct VideoReaderFixture: Decodable {
    var path: String
    var fps: Double
    var frameCount: Int
    var width: Int
    var height: Int
    var durationSeconds: Double
    var timestamps: [String: Double]

    var orderedTimestamps: [(Int, Double)] {
        timestamps.compactMap { key, value in
            guard let frameIndex = Int(key) else { return nil }
            return (frameIndex, value)
        }
        .sorted { lhs, rhs in lhs.0 < rhs.0 }
    }
}
