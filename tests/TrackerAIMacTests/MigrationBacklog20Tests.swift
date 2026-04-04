import Foundation
import XCTest
@testable import TrackerAIMac

final class MigrationBacklog20Tests: XCTestCase {
    func testSessionAndWorkspaceSerializationMatchGoldenFixtures() throws {
        let bridge = PythonEngineBridge()
        let directory = makeTemporaryDirectory()

        let sessionURL = directory.appendingPathComponent("session.json")
        try bridge.saveSession(makeGoldenSessionSnapshot(), to: sessionURL)
        let sessionText = try String(contentsOf: sessionURL, encoding: .utf8)
        try assertFixtureTextMatches(
            actual: sessionText,
            fixtureName: "golden_session_snapshot.json",
            canonicalizer: { try self.canonicalJSONText($0) }
        )

        let loadedSession = try bridge.loadSession(from: sessionURL)
        XCTAssertEqual(loadedSession.videoPath, "/tmp/golden-video.mp4")
        XCTAssertEqual(loadedSession.selectedStartFrame, 3)
        XCTAssertEqual(loadedSession.selectedEndFrame, 18)
        XCTAssertEqual(loadedSession.additionalObjects?.map(\.trackID), ["secondary_1"])

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        try bridge.saveWorkspace(makeGoldenWorkspaceSnapshot(), to: workspaceURL)
        let workspaceText = try String(contentsOf: workspaceURL, encoding: .utf8)
        try assertFixtureTextMatches(
            actual: workspaceText,
            fixtureName: "golden_workspace_snapshot.json",
            canonicalizer: { try self.canonicalJSONText($0) }
        )

        let loadedWorkspace = try bridge.loadWorkspace(from: workspaceURL)
        XCTAssertEqual(loadedWorkspace.title, "Golden Workspace")
        XCTAssertEqual(loadedWorkspace.activeVideoPath, "/tmp/golden-video.mp4")
        XCTAssertEqual(loadedWorkspace.items.count, 2)
    }

    func testNativeResearchExportMatchesGoldenArtifacts() throws {
        let directory = makeTemporaryDirectory()
        let exporter = NativeResearchBundleExporter()
        let payload = makeGoldenBundlePayload(outputDirectory: directory)

        _ = try exporter.export(payload)

        let analysisText = try String(
            contentsOf: directory.appendingPathComponent("analysis.csv"),
            encoding: .utf8
        )
        try assertFixtureTextMatches(
            actual: analysisText,
            fixtureName: "golden_native_analysis.csv",
            canonicalizer: { try self.canonicalPlainText($0) }
        )

        let summaryText = try String(
            contentsOf: directory.appendingPathComponent("summary.json"),
            encoding: .utf8
        )
        try assertFixtureTextMatches(
            actual: summaryText,
            fixtureName: "golden_native_summary.json",
            canonicalizer: { try self.canonicalJSONText($0) }
        )

        let reportText = try String(
            contentsOf: directory.appendingPathComponent("report.md"),
            encoding: .utf8
        )
        try assertFixtureTextMatches(
            actual: reportText,
            fixtureName: "golden_native_report.md",
            canonicalizer: { try self.canonicalPlainText($0) }
        )
    }

    private func makeGoldenSessionSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/golden-video.mp4",
            initialBbox: BBoxSnapshot(x: 12, y: 24, width: 28, height: 22),
            calibration: CalibrationSnapshot(
                referenceLength: 2.0,
                unitLabel: "m",
                pixelDistance: 80.0,
                mode: "single_line",
                originXPx: 10.0,
                originYPx: 12.0,
                axisAngleDeg: 0.0,
                invertX: false,
                invertY: true,
                homography: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                presetName: "lab-bench"
            ),
            analysisConfig: AnalysisConfigSnapshot(
                smoothingWindow: 5,
                smoothingPolyorder: 2
            ),
            trackingConfig: TrackingConfigSnapshot(
                profile: .marker,
                robustRecovery: false,
                bidirectionalRefinement: false,
                debugTracking: true,
                searchMargin: 3.25,
                expandedSearchMargin: 7.5,
                scaleFactors: [0.9, 1.0, 1.15],
                detectionThreshold: 0.63,
                lowConfidenceThreshold: 0.41,
                reacquireThreshold: 0.7,
                suspectAfterFrames: 4,
                recoveryAfterFrames: 7,
                maxPredictionFrames: 11,
                templateUpdateRate: 0.14,
                stableUpdateThreshold: 0.72,
                markerConfidenceBias: 0.61,
                autoMarkerMinRatio: 0.19,
                interpolateShortGaps: false,
                maxInterpolationGap: 4
            ),
            metadata: ExperimentMetadataSnapshot(
                experimentLabel: "Golden Fixture Experiment",
                trialID: "trial-golden-01",
                operatorName: "Codex",
                notes: "Fixture-backed migration regression",
                tags: ["golden", "native", "migration"]
            ),
            advancedMode: true,
            selectedStartFrame: 3,
            selectedEndFrame: 18,
            scalePoints: [10, 20, 90, 20],
            referenceBbox: BBoxSnapshot(x: 100, y: 32, width: 18, height: 18),
            corrections: [
                CorrectionSnapshot(
                    trackID: "primary",
                    frameIndex: 11,
                    bbox: BBoxSnapshot(x: 56, y: 31, width: 28, height: 22),
                    note: "manual realignment"
                ),
            ],
            reviewState: ReviewStateSnapshot(
                lastFrameIndex: 13,
                selectedWindowStart: 6,
                selectedWindowEnd: 15,
                dismissedReviewFrames: [8, 14]
            ),
            eventMarkers: [
                EventMarkerSnapshot(
                    name: "manual_release",
                    frameIndex: 4,
                    timeS: 0.2,
                    value: 0.0,
                    unitLabel: "s",
                    axis: "",
                    note: "operator-marked release",
                    origin: "manual"
                ),
            ],
            additionalObjects: [
                AdditionalObjectSnapshot(
                    trackID: "secondary_1",
                    name: "Secondary Marker",
                    kind: "secondary",
                    bbox: BBoxSnapshot(x: 42, y: 40, width: 14, height: 14)
                ),
            ],
            trackQuality: TrackQualitySnapshot(
                lostSpans: [TrackSpanSnapshot(startFrame: 9, endFrame: 10, reason: "lost_tracking")],
                suspectSpans: [TrackSpanSnapshot(startFrame: 7, endFrame: 8, reason: "tracking_recovery")],
                correctedSpans: [TrackSpanSnapshot(startFrame: 11, endFrame: 14, reason: "manual_correction")],
                reacquisitionCount: 1,
                reviewRecommended: true
            ),
            exportPreferences: ExportPreferencesSnapshot(
                includeOverlay: false,
                includeDebugTracking: true,
                includePlots: false,
                reportTemplate: "research"
            )
        )
    }

    private func makeGoldenWorkspaceSnapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            title: "Golden Workspace",
            activeVideoPath: "/tmp/golden-video.mp4",
            items: [
                WorkspaceClip(
                    label: "golden_primary",
                    videoPath: "/tmp/golden-video.mp4",
                    sessionPath: "/tmp/golden-session.json",
                    notes: "Primary session"
                ),
                WorkspaceClip(
                    label: "golden_secondary",
                    videoPath: "/tmp/golden-video-2.mp4",
                    sessionPath: "/tmp/golden-session-2.json",
                    notes: "Secondary session"
                ),
            ]
        )
    }

    private func makeGoldenBundlePayload(outputDirectory: URL) -> NativeResearchBundlePayload {
        let session = makeGoldenSessionSnapshot()
        let analysisRows = [
            AnalysisRow(
                frameIndex: 3,
                timeSeconds: 0.15,
                xUnits: 0.0500,
                yUnits: 0.2250,
                speed: 0.0000,
                accelerationMagnitude: 0.0000,
                trackerConfidence: 0.9500,
                scientificConfidence: 0.9480,
                xPixels: 12.0,
                yPixels: 24.0,
                rawXUnits: 0.0500,
                rawYUnits: 0.2250,
                xVelocity: 0.0000,
                yVelocity: 0.0000,
                xAcceleration: 0.0000,
                yAcceleration: 0.0000,
                angleDegrees: 0.0000,
                positionUncertainty: 0.0040,
                velocityUncertainty: 0.0000,
                accelerationUncertainty: 0.0000,
                lost: false,
                corrected: false,
                state: "tracking",
                failureReason: ""
            ),
            AnalysisRow(
                frameIndex: 4,
                timeSeconds: 0.20,
                xUnits: 0.1750,
                yUnits: 0.2000,
                speed: 2.5495,
                accelerationMagnitude: 0.1803,
                trackerConfidence: 0.9200,
                scientificConfidence: 0.9120,
                xPixels: 17.0,
                yPixels: 25.0,
                rawXUnits: 0.1750,
                rawYUnits: 0.2000,
                xVelocity: 2.5000,
                yVelocity: -0.5000,
                xAcceleration: 0.1500,
                yAcceleration: -0.1000,
                angleDegrees: -11.3099,
                positionUncertainty: 0.0160,
                velocityUncertainty: 0.0550,
                accelerationUncertainty: 0.0200,
                lost: false,
                corrected: false,
                state: "tracking",
                failureReason: ""
            ),
            AnalysisRow(
                frameIndex: 5,
                timeSeconds: 0.25,
                xUnits: 0.3250,
                yUnits: 0.1625,
                speed: 3.9051,
                accelerationMagnitude: 0.5385,
                trackerConfidence: 0.8800,
                scientificConfidence: 0.7600,
                xPixels: 23.0,
                yPixels: 27.0,
                rawXUnits: 0.3250,
                rawYUnits: 0.1625,
                xVelocity: 3.0000,
                yVelocity: -0.7500,
                xAcceleration: 0.4000,
                yAcceleration: -0.3600,
                angleDegrees: -14.0362,
                positionUncertainty: 0.0400,
                velocityUncertainty: 0.1200,
                accelerationUncertainty: 0.0600,
                lost: true,
                corrected: false,
                state: "lost",
                failureReason: "occluded"
            ),
            AnalysisRow(
                frameIndex: 6,
                timeSeconds: 0.30,
                xUnits: 0.4250,
                yUnits: 0.1000,
                speed: 2.9155,
                accelerationMagnitude: 1.1402,
                trackerConfidence: 0.9000,
                scientificConfidence: 0.7700,
                xPixels: 27.0,
                yPixels: 30.0,
                rawXUnits: 0.4250,
                rawYUnits: 0.1000,
                xVelocity: 2.0000,
                yVelocity: -1.2500,
                xAcceleration: -0.8000,
                yAcceleration: -0.9000,
                angleDegrees: -32.0054,
                positionUncertainty: 0.0600,
                velocityUncertainty: 0.2200,
                accelerationUncertainty: 0.0800,
                lost: false,
                corrected: true,
                state: "reacquired",
                failureReason: "manual_correction"
            ),
        ]

        return NativeResearchBundlePayload(
            session: session,
            trackID: "primary",
            trackName: "Primary Marker",
            analysisRows: analysisRows,
            pairwiseMetrics: [
                PairwiseMetricSnapshot(
                    primaryTrackID: "primary",
                    secondaryTrackID: "secondary_1",
                    samples: [
                        PairwiseMetricSampleSnapshot(
                            frameIndex: 4,
                            timeSeconds: 0.20,
                            distanceUnits: 0.42,
                            relativeSpeedUnitsPerSecond: 0.9,
                            relativeDXUnits: 0.32,
                            relativeDYUnits: -0.12,
                            centerOfMassXUnits: 0.21,
                            centerOfMassYUnits: 0.16
                        ),
                        PairwiseMetricSampleSnapshot(
                            frameIndex: 5,
                            timeSeconds: 0.25,
                            distanceUnits: 0.26,
                            relativeSpeedUnitsPerSecond: 1.4,
                            relativeDXUnits: 0.18,
                            relativeDYUnits: -0.08,
                            centerOfMassXUnits: 0.27,
                            centerOfMassYUnits: 0.13
                        ),
                    ]
                ),
            ],
            eventMarkers: [
                EventMarkerRecord(
                    name: "manual_release",
                    frameIndex: 4,
                    timeSeconds: 0.20,
                    value: 0.0,
                    unitLabel: "s",
                    axis: "",
                    note: "operator-marked release",
                    origin: "manual"
                ),
            ],
            outputDirectory: outputDirectory,
            reportTemplate: "research",
            trackingProfile: .marker,
            includeOverlay: false,
            includePlots: false,
            debugTracking: true,
            summary: nil,
            quality: nil,
            modules: []
        )
    }

    private func assertFixtureTextMatches(
        actual: String,
        fixtureName: String,
        canonicalizer: (String) throws -> String
    ) throws {
        let normalized = try canonicalizer(actual)
        let fixtureURL = fixturesRoot.appendingPathComponent(fixtureName)

        if shouldUpdateFixtures {
            try FileManager.default.createDirectory(
                at: fixturesRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try normalized.write(to: fixtureURL, atomically: true, encoding: .utf8)
            return
        }

        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            XCTFail("Missing fixture at \(fixtureURL.path)\n\nActual output:\n\(normalized)")
            return
        }

        let expected = try canonicalizer(String(contentsOf: fixtureURL, encoding: .utf8))
        XCTAssertEqual(normalized, expected, "Fixture mismatch for \(fixtureName)")
    }

    private func canonicalJSONText(_ text: String) throws -> String {
        let data = Data(text.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: normalized, as: UTF8.self)
    }

    private func canonicalJSONText(contentsOf url: URL) throws -> String {
        try canonicalJSONText(String(contentsOf: url, encoding: .utf8))
    }

    private func canonicalPlainText(_ text: String) throws -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var shouldUpdateFixtures: Bool {
        ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1"
    }

    private var fixturesRoot: URL {
        repositoryRoot
            .appendingPathComponent("tests")
            .appendingPathComponent("TrackerAIMacTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("MigrationBacklog20")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
