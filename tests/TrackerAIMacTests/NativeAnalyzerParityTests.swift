import Foundation
import XCTest
@testable import TrackerAIMac

final class NativeAnalyzerParityTests: XCTestCase {
    private let numericTolerance = 1e-5

    func testNativeBuiltInAnalyzersCoverPythonAnalyzerSet() throws {
        let observedIDs = Set(try fixtures.flatMap { try analyzerIDs(for: $0) })
        XCTAssertEqual(observedIDs, ["projectile", "pendulum", "circular", "incline", "spring", "collision"])
    }

    func testNativeAnalyzerFixturesMatchExpectedMetrics() throws {
        for fixture in fixtures {
            let modules = try analyzers(for: fixture)
            XCTAssertEqual(modules.map(\.analyzerID), fixture.expectedModules.map(\.analyzerID), "Analyzer ids mismatch for \(fixture.name)")

            for (module, expectedModule) in zip(modules, fixture.expectedModules) {
                XCTAssertEqual(module.title, expectedModule.title, "Title mismatch for \(fixture.name) / \(expectedModule.analyzerID)")
                XCTAssertEqual(module.confidence, expectedModule.confidence, accuracy: numericTolerance, "Confidence mismatch for \(fixture.name) / \(expectedModule.analyzerID)")
                XCTAssertEqual(module.notes ?? [], expectedModule.notes, "Notes mismatch for \(fixture.name) / \(expectedModule.analyzerID)")
                XCTAssertEqual(module.metrics.count, expectedModule.metrics.count, "Metric count mismatch for \(fixture.name) / \(expectedModule.analyzerID)")

                for (metric, expectedMetric) in zip(module.metrics, expectedModule.metrics) {
                    XCTAssertEqual(metric.key, expectedMetric.key, "Metric key mismatch for \(fixture.name) / \(expectedModule.analyzerID)")
                    XCTAssertEqual(metric.unitLabel, expectedMetric.unitLabel, "Metric unit mismatch for \(fixture.name) / \(expectedModule.analyzerID) / \(expectedMetric.key)")
                    XCTAssertEqual(metric.value, expectedMetric.value, accuracy: numericTolerance, "Metric value mismatch for \(fixture.name) / \(expectedModule.analyzerID) / \(expectedMetric.key)")
                }
            }
        }
    }

    func testClassificationUsesStableSpecificTieBreaks() throws {
        for fixture in fixtures {
            let (session, rows, modules) = try resolvedFixture(fixture)
            let classification = reporter.buildClassification(
                session: session,
                rows: rows,
                modules: modules,
                trackID: fixture.primaryTrack.trackID
            )

            XCTAssertEqual(classification.classificationID, fixture.expectedClassification.classificationID, "Classification id mismatch for \(fixture.name)")
            XCTAssertEqual(classification.title, fixture.expectedClassification.title, "Classification title mismatch for \(fixture.name)")
            XCTAssertEqual(classification.confidence, fixture.expectedClassification.confidence, accuracy: numericTolerance, "Classification confidence mismatch for \(fixture.name)")
            XCTAssertEqual(classification.summary, fixture.expectedClassification.summary, "Classification summary mismatch for \(fixture.name)")
            XCTAssertEqual(classification.supportingAnalyzerIDs, fixture.expectedClassification.supportingAnalyzerIDs, "Supporting analyzers mismatch for \(fixture.name)")
        }
    }

    private let processor = NativeScientificProcessor()
    private let reporter = NativeResearchReporter()

    private var fixtures: [AnalyzerFixture] {
        [
            AnalyzerFixture(
                name: "projectile",
                analysisConfig: AnalysisConfigSnapshot(smoothingWindow: 5, smoothingPolyorder: 2),
                primaryTrack: Self.makeTrack(
                    xs: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
                    ys: [0, 4, 7, 9, 10, 10, 9, 7, 4, 0],
                    trackID: "primary",
                    trackName: "Primary",
                    trackKind: "primary"
                ),
                secondaryTrack: nil,
                expectedModules: [
                    ExpectedAnalyzer(
                        analyzerID: "projectile",
                        title: "Projectile Motion",
                        confidence: 0.9499999999999955,
                        metrics: [
                            ExpectedMetric(key: "launch_angle_deg", value: 75.96375653139945, unitLabel: "deg"),
                            ExpectedMetric(key: "gravity_fit", value: -400.0000000000005, unitLabel: "m/s^2"),
                            ExpectedMetric(key: "flight_time", value: 0.45, unitLabel: "s"),
                        ],
                        notes: ["Estimated from a quadratic fit of vertical displacement over time."]
                    ),
                    ExpectedAnalyzer(
                        analyzerID: "circular",
                        title: "Circular Motion",
                        confidence: 0.6147483960393255,
                        metrics: [
                            ExpectedMetric(key: "mean_radius", value: 4.321788423623097, unitLabel: "m"),
                            ExpectedMetric(key: "angular_velocity", value: 5.3699126464286255, unitLabel: "rad/s"),
                            ExpectedMetric(key: "circularity", value: 0.6147483960393255, unitLabel: ""),
                        ],
                        notes: ["Center estimated from the mean track position."]
                    ),
                ],
                expectedClassification: ExpectedClassification(
                    classificationID: "projectile",
                    title: "Projectile Motion",
                    confidence: 0.9499999999999955,
                    summary: "Estimated from a quadratic fit of vertical displacement over time.",
                    supportingAnalyzerIDs: ["projectile", "circular"]
                )
            ),
            AnalyzerFixture(
                name: "pendulum",
                analysisConfig: AnalysisConfigSnapshot(smoothingWindow: 5, smoothingPolyorder: 2),
                primaryTrack: Self.makeTrack(
                    xs: [0, 2, 4, 2, 0, -2, -4, -2, 0, 2, 4, 2, 0, -2, -4, -2, 0],
                    ys: Array(repeating: 0, count: 17),
                    trackID: "primary",
                    trackName: "Primary",
                    trackKind: "primary"
                ),
                secondaryTrack: nil,
                expectedModules: [
                    ExpectedAnalyzer(
                        analyzerID: "pendulum",
                        title: "Pendulum Motion",
                        confidence: 0.7054621848739551,
                        metrics: [
                            ExpectedMetric(key: "period", value: 0.39999999999999997, unitLabel: "s"),
                            ExpectedMetric(key: "damping_ratio", value: 0.0, unitLabel: ""),
                            ExpectedMetric(key: "peak_angle", value: 180.0, unitLabel: "deg"),
                        ],
                        notes: ["Detected from repeated lateral turning points in the track."]
                    ),
                    ExpectedAnalyzer(
                        analyzerID: "incline",
                        title: "Incline Motion",
                        confidence: 0.7054621848739551,
                        metrics: [
                            ExpectedMetric(key: "track_angle_deg", value: -0.0, unitLabel: "deg"),
                            ExpectedMetric(key: "along_track_acceleration", value: 5.550592665231842e-13, unitLabel: "m/s^2"),
                            ExpectedMetric(key: "line_residual_std", value: 0.0, unitLabel: "m"),
                        ],
                        notes: ["Estimated from a line fit through the smoothed path."]
                    ),
                    ExpectedAnalyzer(
                        analyzerID: "spring",
                        title: "Spring Oscillation",
                        confidence: 0.7054621848739551,
                        metrics: [
                            ExpectedMetric(key: "period", value: 0.39999999999999997, unitLabel: "s"),
                            ExpectedMetric(key: "frequency", value: 2.5, unitLabel: "Hz"),
                            ExpectedMetric(key: "damping_ratio", value: 0.0, unitLabel: ""),
                        ],
                        notes: ["Dominant oscillation axis selected automatically from the larger path span."]
                    ),
                ],
                expectedClassification: ExpectedClassification(
                    classificationID: "pendulum",
                    title: "Pendulum Motion",
                    confidence: 0.7054621848739551,
                    summary: "Detected from repeated lateral turning points in the track.",
                    supportingAnalyzerIDs: ["pendulum", "incline", "spring"]
                )
            ),
            AnalyzerFixture(
                name: "rotation_uses_circular_replacement",
                analysisConfig: AnalysisConfigSnapshot(smoothingWindow: 5, smoothingPolyorder: 2),
                primaryTrack: Self.makeTrack(
                    xs: [15.0, 14.619397662556434, 13.535533905932738, 11.91341716182545, 10.0, 8.086582838174552, 6.464466094067262, 5.380602337443566, 5.0, 5.380602337443566, 6.464466094067261, 8.086582838174548, 9.999999999999998, 11.91341716182545, 13.535533905932738, 14.619397662556432],
                    ys: [10.0, 11.91341716182545, 13.535533905932738, 14.619397662556434, 15.0, 14.619397662556434, 13.535533905932738, 11.91341716182545, 10.0, 8.086582838174552, 6.464466094067262, 5.380602337443566, 5.0, 5.380602337443566, 6.464466094067261, 8.086582838174548],
                    trackID: "primary",
                    trackName: "Primary",
                    trackKind: "primary"
                ),
                secondaryTrack: nil,
                expectedModules: [
                    ExpectedAnalyzer(
                        analyzerID: "projectile",
                        title: "Projectile Motion",
                        confidence: 0.9369812610987189,
                        metrics: [
                            ExpectedMetric(key: "launch_angle_deg", value: 101.74034403439366, unitLabel: "deg"),
                            ExpectedMetric(key: "gravity_fit", value: -28.100374675646304, unitLabel: "m/s^2"),
                            ExpectedMetric(key: "flight_time", value: 0.75, unitLabel: "s"),
                        ],
                        notes: ["Estimated from a quadratic fit of vertical displacement over time."]
                    ),
                    ExpectedAnalyzer(
                        analyzerID: "circular",
                        title: "Circular Motion",
                        confidence: 0.9369812610987189,
                        metrics: [
                            ExpectedMetric(key: "mean_radius", value: 4.99148676924147, unitLabel: "m"),
                            ExpectedMetric(key: "angular_velocity", value: 7.088578000914385, unitLabel: "rad/s"),
                            ExpectedMetric(key: "circularity", value: 0.9991836131578922, unitLabel: ""),
                        ],
                        notes: ["Center estimated from the mean track position."]
                    ),
                ],
                expectedClassification: ExpectedClassification(
                    classificationID: "circular",
                    title: "Circular Motion",
                    confidence: 0.9369812610987189,
                    summary: "Center estimated from the mean track position.",
                    supportingAnalyzerIDs: ["projectile", "circular"]
                )
            ),
            AnalyzerFixture(
                name: "collision_prefers_pairwise_over_linear_overlap",
                analysisConfig: AnalysisConfigSnapshot(smoothingWindow: 7, smoothingPolyorder: 2),
                primaryTrack: Self.makeTrack(
                    xs: [0, 1, 2, 3, 4, 5],
                    ys: Array(repeating: 0, count: 6),
                    trackID: "primary",
                    trackName: "Primary",
                    trackKind: "primary"
                ),
                secondaryTrack: Self.makeTrack(
                    xs: [4, 3, 2, 1, 0, -1],
                    ys: Array(repeating: 0, count: 6),
                    trackID: "secondary",
                    trackName: "Secondary",
                    trackKind: "secondary"
                ),
                expectedModules: [
                    ExpectedAnalyzer(
                        analyzerID: "incline",
                        title: "Incline Motion",
                        confidence: 0.949999999999999,
                        metrics: [
                            ExpectedMetric(key: "track_angle_deg", value: 0.0, unitLabel: "deg"),
                            ExpectedMetric(key: "along_track_acceleration", value: 2.250051996573651e-13, unitLabel: "m/s^2"),
                            ExpectedMetric(key: "line_residual_std", value: 0.0, unitLabel: "m"),
                        ],
                        notes: ["Estimated from a line fit through the smoothed path."]
                    ),
                    ExpectedAnalyzer(
                        analyzerID: "collision",
                        title: "Collision Pair: primary vs secondary",
                        confidence: 0.949999999999999,
                        metrics: [
                            ExpectedMetric(key: "minimum_separation", value: 2.6645352591003757e-15, unitLabel: "m"),
                            ExpectedMetric(key: "peak_relative_speed", value: 40.00000000000005, unitLabel: "m/s"),
                            ExpectedMetric(key: "coefficient_of_restitution", value: 0.9999999999999982, unitLabel: ""),
                        ],
                        notes: ["Collision frame detected at 2."]
                    ),
                ],
                expectedClassification: ExpectedClassification(
                    classificationID: "collision",
                    title: "Collision Pair: primary vs secondary",
                    confidence: 0.949999999999999,
                    summary: "Collision frame detected at 2.",
                    supportingAnalyzerIDs: ["incline", "collision"]
                )
            ),
        ]
    }

    private func analyzers(for fixture: AnalyzerFixture) throws -> [AnalyzerSnapshot] {
        let (_, _, modules) = try resolvedFixture(fixture)
        return modules
    }

    private func analyzerIDs(for fixture: AnalyzerFixture) throws -> [String] {
        try analyzers(for: fixture).map(\.analyzerID)
    }

    private func resolvedFixture(_ fixture: AnalyzerFixture) throws -> (SessionSnapshot, [AnalysisRow], [AnalyzerSnapshot]) {
        let session = makeSessionSnapshot(analysisConfig: fixture.analysisConfig)
        let primaryRows = processor.process(
            observations: fixture.primaryTrack.observations,
            calibration: try session.calibration.makeCalibrationProfile(),
            config: fixture.analysisConfig
        )

        let pairwiseMetrics: [PairwiseMetricSnapshot]
        if let secondaryTrack = fixture.secondaryTrack {
            let secondaryRows = processor.process(
                observations: secondaryTrack.observations,
                calibration: try session.calibration.makeCalibrationProfile(),
                config: fixture.analysisConfig
            )
            pairwiseMetrics = reporter.rebuildPairwiseMetrics(
                trackBundles: [
                    AnalysisTrackBundle(
                        trackID: fixture.primaryTrack.trackID,
                        trackName: fixture.primaryTrack.trackName,
                        trackKind: fixture.primaryTrack.trackKind,
                        summary: nil,
                        quality: nil,
                        modules: [],
                        analysisRows: primaryRows,
                        reportMarkdown: "",
                        exportDirectory: URL(fileURLWithPath: "/tmp")
                    ),
                    AnalysisTrackBundle(
                        trackID: secondaryTrack.trackID,
                        trackName: secondaryTrack.trackName,
                        trackKind: secondaryTrack.trackKind,
                        summary: nil,
                        quality: nil,
                        modules: [],
                        analysisRows: secondaryRows,
                        reportMarkdown: "",
                        exportDirectory: URL(fileURLWithPath: "/tmp")
                    ),
                ]
            )
        } else {
            pairwiseMetrics = []
        }

        let modules = reporter.buildAnalyzers(
            session: session,
            rows: primaryRows,
            trackID: fixture.primaryTrack.trackID,
            pairwiseMetrics: pairwiseMetrics
        )
        return (session, primaryRows, modules)
    }

    private func makeSessionSnapshot(analysisConfig: AnalysisConfigSnapshot) -> SessionSnapshot {
        SessionSnapshot(
            videoPath: "/tmp/demo.mp4",
            initialBbox: BBoxSnapshot(x: 0, y: 0, width: 4, height: 4),
            calibration: CalibrationSnapshot(
                referenceLength: 1.0,
                unitLabel: "m",
                pixelDistance: 1.0,
                mode: "single_line",
                originXPx: 0,
                originYPx: 0,
                axisAngleDeg: 0,
                invertX: false,
                invertY: false,
                homography: nil,
                presetName: nil
            ),
            analysisConfig: analysisConfig,
            trackingConfig: TrackingConfigSnapshot.pythonDefaults,
            metadata: nil,
            advancedMode: nil,
            selectedStartFrame: 0,
            selectedEndFrame: nil,
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

    private static func makeTrack(
        xs: [Double],
        ys: [Double],
        trackID: String,
        trackName: String,
        trackKind: String
    ) -> NativeTrackFixture {
        precondition(xs.count == ys.count)
        let observations = zip(xs, ys).enumerated().map { index, point in
            NativeTrackingObservation(
                frameIndex: index,
                timeSeconds: Double(index) / 20.0,
                centroidXPixels: point.0,
                centroidYPixels: point.1,
                bbox: BBoxSnapshot(x: point.0 - 2.0, y: point.1 - 2.0, width: 4.0, height: 4.0),
                confidence: 0.95,
                lost: false,
                corrected: false,
                state: "tracking",
                failureReason: nil,
                source: "measured",
                isInferred: false,
                isInterpolated: false,
                debug: [:],
                trackID: trackID,
                trackName: trackName,
                trackKind: trackKind
            )
        }
        return NativeTrackFixture(
            trackID: trackID,
            trackName: trackName,
            trackKind: trackKind,
            observations: observations
        )
    }
}

private struct AnalyzerFixture {
    var name: String
    var analysisConfig: AnalysisConfigSnapshot
    var primaryTrack: NativeTrackFixture
    var secondaryTrack: NativeTrackFixture?
    var expectedModules: [ExpectedAnalyzer]
    var expectedClassification: ExpectedClassification
}

private struct NativeTrackFixture {
    var trackID: String
    var trackName: String
    var trackKind: String
    var observations: [NativeTrackingObservation]
}

private struct ExpectedAnalyzer {
    var analyzerID: String
    var title: String
    var confidence: Double
    var metrics: [ExpectedMetric]
    var notes: [String]
}

private struct ExpectedMetric {
    var key: String
    var value: Double
    var unitLabel: String
}

private struct ExpectedClassification {
    var classificationID: String
    var title: String
    var confidence: Double
    var summary: String
    var supportingAnalyzerIDs: [String]
}
