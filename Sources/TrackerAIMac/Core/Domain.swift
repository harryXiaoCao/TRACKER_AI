import Foundation
import CoreGraphics

enum LabTab: String, CaseIterable, Identifiable {
    case overview
    case setup
    case review
    case results
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .setup: return "Setup"
        case .review: return "Review"
        case .results: return "Results"
        case .help: return "Help"
        }
    }
}

enum ResultsSubtab: String, CaseIterable, Identifiable {
    case insights
    case graphs
    case window
    case events
    case quality
    case pairwise
    case table
    case reproduce

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insights: return "Insights"
        case .graphs: return "Graphs"
        case .window: return "Window"
        case .events: return "Events"
        case .quality: return "Quality"
        case .pairwise: return "Pairwise"
        case .table: return "Table"
        case .reproduce: return "Reproduce"
        }
    }
}

enum ResultsTablePreset: String, CaseIterable, Identifiable {
    case core
    case velocity
    case acceleration
    case confidence
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core: return "Core Table"
        case .velocity: return "Velocity Focus"
        case .acceleration: return "Acceleration Focus"
        case .confidence: return "Confidence + QC"
        case .all: return "All Variables"
        }
    }
}

enum TrackingProfileOption: String, CaseIterable, Identifiable, Codable {
    case auto
    case template
    case marker

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}

enum AnnotationMode: String, Equatable {
    case idle
    case target
    case scale
    case correction
    case companion
}

struct ResearchPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let trackingProfile: TrackingProfileOption
    let smoothingWindow: Int
    let polyorder: Int
    let reportTemplate: String
    let reviewFocus: String
    let setupTip: String

    static let all: [ResearchPreset] = [
        ResearchPreset(
            id: "general",
            title: "General Motion Study",
            description: "Balanced defaults for everyday clips with one main target and moderate motion.",
            trackingProfile: .auto,
            smoothingWindow: 7,
            polyorder: 2,
            reportTemplate: "guided",
            reviewFocus: "Check suspect spans and confirm the calibration line before exporting.",
            setupTip: "Use this when you want a safe starting point before specializing for a specific apparatus."
        ),
        ResearchPreset(
            id: "projectile",
            title: "Projectile / Ballistics",
            description: "Fast events with strong interest in release, apex, impact, and acceleration peaks.",
            trackingProfile: .marker,
            smoothingWindow: 5,
            polyorder: 2,
            reportTemplate: "research",
            reviewFocus: "Keep smoothing tight and mark release, apex, and impact frames in the journal.",
            setupTip: "Best for launches, drops, trajectories, and short airtime experiments."
        ),
        ResearchPreset(
            id: "pendulum",
            title: "Pendulum / Oscillation",
            description: "Repeated motion where period, damping, and turning points matter more than one-off peaks.",
            trackingProfile: .template,
            smoothingWindow: 9,
            polyorder: 3,
            reportTemplate: "research",
            reviewFocus: "Track at least two full oscillations and mark release plus turning points for validation.",
            setupTip: "Use an axis-aware calibration when angular interpretation matters."
        ),
        ResearchPreset(
            id: "collision",
            title: "Collision / Multi-Object",
            description: "Two or more bodies interacting with pairwise distance and relative speed analysis.",
            trackingProfile: .marker,
            smoothingWindow: 5,
            polyorder: 2,
            reportTemplate: "research",
            reviewFocus: "Add each moving body before analysis and mark pre/post-contact frames.",
            setupTip: "Great for carts, beads, impacts, and separation timing studies."
        ),
        ResearchPreset(
            id: "rotation",
            title: "Rotation / Circular Motion",
            description: "Steady rotational or orbital motion where radius consistency and angular speed matter.",
            trackingProfile: .marker,
            smoothingWindow: 9,
            polyorder: 3,
            reportTemplate: "compact",
            reviewFocus: "Use a stable reference whenever the camera or apparatus may drift.",
            setupTip: "Helpful for turntables, rotors, and circular path experiments."
        ),
    ]
}

struct WorkspaceClip: Identifiable, Hashable, Codable {
    var label: String
    var videoPath: String
    var sessionPath: String = ""
    var notes: String = ""

    var id: String { videoPath }
}

struct BoundingBoxDraft: Hashable, Codable {
    var x: String = ""
    var y: String = ""
    var width: String = ""
    var height: String = ""

    var isComplete: Bool {
        [x, y, width, height].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var cgRect: CGRect? {
        guard
            let x = Double(x),
            let y = Double(y),
            let width = Double(width),
            let height = Double(height)
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct AdditionalObjectDraft: Identifiable, Hashable, Codable {
    var trackID: String = ""
    var name: String = ""
    var kind: String = "secondary"
    var x: String = ""
    var y: String = ""
    var width: String = ""
    var height: String = ""

    var id: String {
        let candidate = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty { return candidate }
        let fallback = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "\(x)-\(y)-\(width)-\(height)" : fallback
    }

    var isComplete: Bool {
        !trackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        [x, y, width, height].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct CorrectionRecord: Identifiable, Hashable, Codable {
    var id: String { "\(frameIndex)-\(note)" }
    var frameIndex: Int
    var note: String
    var bbox: BoundingBoxDraft
}

struct ScaleLineDraft: Hashable, Codable {
    var x1: String = ""
    var y1: String = ""
    var x2: String = ""
    var y2: String = ""

    var isComplete: Bool {
        [x1, y1, x2, y2].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var points: (CGPoint, CGPoint)? {
        guard
            let x1 = Double(x1),
            let y1 = Double(y1),
            let x2 = Double(x2),
            let y2 = Double(y2)
        else {
            return nil
        }
        return (CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2))
    }
}

struct EventMarkerRecord: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var frameIndex: Int
    var timeSeconds: Double
    var value: Double
    var unitLabel: String
    var axis: String = ""
    var note: String = ""
    var origin: String = "manual"
}

struct ReviewIssue: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var detail: String
    var frameIndex: Int
    var endFrame: Int?
    var severity: String
    var dismissible: Bool = true
}

struct MetricTile: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var value: String
}

struct AnalysisModuleSummary: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var confidence: Double
    var metrics: [String]
}

struct AnalysisRow: Identifiable, Hashable {
    var frameIndex: Int
    var timeSeconds: Double
    var xUnits: Double
    var yUnits: Double
    var speed: Double
    var accelerationMagnitude: Double
    var trackerConfidence: Double
    var scientificConfidence: Double
    var xPixels: Double?
    var yPixels: Double?
    var rawXUnits: Double?
    var rawYUnits: Double?
    var xVelocity: Double?
    var yVelocity: Double?
    var xAcceleration: Double?
    var yAcceleration: Double?
    var angleDegrees: Double?
    var positionUncertainty: Double?
    var velocityUncertainty: Double?
    var accelerationUncertainty: Double?
    var lost: Bool = false
    var corrected: Bool = false
    var state: String = ""
    var failureReason: String = ""

    var id: Int { frameIndex }
}

struct NativeRunConfiguration {
    var videoURL: URL
    var outputDirectory: URL
    var targetBox: BoundingBoxDraft
    var scaleLine: ScaleLineDraft
    var referenceBox: BoundingBoxDraft?
    var referenceLength: Double
    var unitLabel: String
    var startFrame: Int
    var endFrame: Int?
    var smoothingWindow: Int
    var polyorder: Int
    var trackingProfile: TrackingProfileOption
    var debugTracking: Bool
    var includeOverlay: Bool
    var includePlots: Bool
    var reportTemplate: String
    var experimentLabel: String
    var trialID: String
    var operatorName: String
    var notes: String
    var tags: [String]
    var additionalObjects: [AdditionalObjectDraft]
}

struct AnalysisTrackBundle: Identifiable {
    var trackID: String
    var trackName: String
    var trackKind: String
    var summary: SummarySnapshot?
    var quality: QualitySnapshot?
    var modules: [AnalyzerSnapshot]
    var analysisRows: [AnalysisRow]
    var reportMarkdown: String
    var exportDirectory: URL

    var id: String { trackID }
}

struct PairwiseMetricSampleSnapshot: Identifiable, Hashable {
    var frameIndex: Int
    var timeSeconds: Double
    var distanceUnits: Double
    var relativeSpeedUnitsPerSecond: Double
    var relativeDXUnits: Double
    var relativeDYUnits: Double

    var id: Int { frameIndex }
}

struct PairwiseMetricSnapshot: Identifiable, Hashable {
    var primaryTrackID: String
    var secondaryTrackID: String
    var samples: [PairwiseMetricSampleSnapshot]

    var id: String { "\(primaryTrackID)|\(secondaryTrackID)" }

    var minimumSeparation: Double { samples.map(\.distanceUnits).min() ?? 0 }
    var peakRelativeSpeed: Double { samples.map(\.relativeSpeedUnitsPerSecond).max() ?? 0 }
    var meanSeparation: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.distanceUnits).reduce(0, +) / Double(samples.count)
    }
    var meanRelativeSpeed: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.relativeSpeedUnitsPerSecond).reduce(0, +) / Double(samples.count)
    }
    var collisionFrame: Int? { samples.first(where: { $0.distanceUnits <= 0.05 })?.frameIndex }
}

struct WindowStatsSnapshot: Hashable {
    var startFrame: Int
    var endFrame: Int
    var durationSeconds: Double
    var displacement: Double
    var meanSpeed: Double
    var maxSpeed: Double
    var maxAcceleration: Double
}

struct ExperimentClassificationSnapshot: Codable, Hashable {
    var classificationID: String
    var title: String
    var confidence: Double
    var summary: String
    var supportingAnalyzerIDs: [String]
}

struct AnalysisLoadResult {
    var summary: SummarySnapshot?
    var quality: QualitySnapshot?
    var modules: [AnalyzerSnapshot]
    var analysisRows: [AnalysisRow]
    var session: SessionSnapshot?
    var reportMarkdown: String
    var exportDirectory: URL
    var trackBundles: [AnalysisTrackBundle] = []
    var pairwiseMetrics: [PairwiseMetricSnapshot] = []
}

struct NativeBatchTrialSnapshot: Codable, Identifiable, Hashable {
    var trialID: String
    var videoPath: String
    var qcBadge: String
    var peakSpeed: Double
    var peakAcceleration: Double
    var scientificConfidenceMean: Double
    var analyzerCount: Int
    var qualityIndex: Double = 0
    var eventCount: Int = 0
    var classificationID: String = "unclassified"
    var classificationTitle: String = "Unclassified"
    var classificationConfidence: Double = 0

    var id: String { trialID }
}

struct NativeBatchAggregateSnapshot: Codable, Hashable {
    var trialCount: Int
    var meanPeakSpeed: Double
    var meanPeakAcceleration: Double
    var meanScientificConfidence: Double
    var meanQualityIndex: Double = 0
    var meanEventCount: Double = 0
    var qcBadges: [String: Int]
    var classifications: [String: Int] = [:]
    var highestPeakSpeedTrialID: String? = nil
    var highestPeakAccelerationTrialID: String? = nil
    var bestQualityTrialID: String? = nil
    var trials: [NativeBatchTrialSnapshot]
}

struct WorkspaceSnapshot: Codable {
    var title: String
    var activeVideoPath: String
    var items: [WorkspaceClip]
}

struct SessionSnapshot: Codable {
    var videoPath: String
    var initialBbox: BBoxSnapshot
    var calibration: CalibrationSnapshot
    var analysisConfig: AnalysisConfigSnapshot
    var trackingConfig: TrackingConfigSnapshot?
    var metadata: ExperimentMetadataSnapshot?
    var selectedStartFrame: Int?
    var selectedEndFrame: Int?
    var scalePoints: [Double]?
    var referenceBbox: BBoxSnapshot?
    var corrections: [CorrectionSnapshot]?
    var reviewState: ReviewStateSnapshot?
    var eventMarkers: [EventMarkerSnapshot]?
    var additionalObjects: [AdditionalObjectSnapshot]?
    var trackQuality: TrackQualitySnapshot?
    var exportPreferences: ExportPreferencesSnapshot?
}

struct BBoxSnapshot: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct CalibrationSnapshot: Codable {
    var referenceLength: Double
    var unitLabel: String
    var pixelDistance: Double
    var mode: String?
    var originXPx: Double?
    var originYPx: Double?
    var axisAngleDeg: Double?
}

struct AnalysisConfigSnapshot: Codable {
    var smoothingWindow: Int
    var smoothingPolyorder: Int
}

struct TrackingConfigSnapshot: Codable {
    var profile: TrackingProfileOption?
    var robustRecovery: Bool?
    var bidirectionalRefinement: Bool?
    var debugTracking: Bool?
}

struct ExperimentMetadataSnapshot: Codable {
    var experimentLabel: String?
    var trialID: String?
    var operatorName: String?
    var notes: String?
    var tags: [String]?
}

struct CorrectionSnapshot: Codable {
    var frameIndex: Int
    var bbox: BBoxSnapshot
    var note: String?
}

struct ReviewStateSnapshot: Codable {
    var lastFrameIndex: Int?
    var selectedWindowStart: Int?
    var selectedWindowEnd: Int?
    var dismissedReviewFrames: [Int]?
}

struct EventMarkerSnapshot: Codable {
    var name: String
    var frameIndex: Int
    var timeS: Double
    var value: Double
    var unitLabel: String
    var axis: String?
    var note: String?
    var origin: String?
}

struct AdditionalObjectSnapshot: Codable {
    var trackID: String
    var name: String
    var kind: String?
    var bbox: BBoxSnapshot
}

struct TrackSpanSnapshot: Codable {
    var startFrame: Int
    var endFrame: Int
    var reason: String
}

struct TrackQualitySnapshot: Codable {
    var lostSpans: [TrackSpanSnapshot]?
    var suspectSpans: [TrackSpanSnapshot]?
    var correctedSpans: [TrackSpanSnapshot]?
    var reacquisitionCount: Int?
    var reviewRecommended: Bool?
}

struct ExportPreferencesSnapshot: Codable {
    var includeOverlay: Bool?
    var includeDebugTracking: Bool?
    var includePlots: Bool?
    var reportTemplate: String?
}

struct SummarySnapshot: Codable {
    var frameCount: Int?
    var durationSeconds: Double?
    var startFrame: Int?
    var endFrame: Int?
    var averageConfidence: Double?
    var lowConfidenceFrameCount: Int?
    var suspectSpanCount: Int?
    var xRangeUnits: Double?
    var yRangeUnits: Double?
    var peakSpeed: Double?
    var meanSpeed: Double?
    var peakAcceleration: Double?
    var meanAcceleration: Double?
    var totalPathLength: Double?
    var netDisplacement: Double?
    var scientificConfidenceMean: Double?
    var qcBadge: String?
    var eventCount: Int?
    var unitLabel: String?
    var reacquisitionCount: Int?
    var lostFrameCount: Int?
    var correctedFrameCount: Int?
    var reviewRecommended: Bool?
    var peakPositionUncertainty: Double?
    var peakVelocityUncertainty: Double?
    var classification: ExperimentClassificationSnapshot? = nil
}

struct QualitySnapshot: Codable {
    var qcBadge: String?
    var trackerConfidenceMean: Double?
    var scientificConfidenceMean: Double?
    var calibrationConfidence: Double?
    var driftSensitivity: Double?
    var lowConfidenceFrames: Int?
    var lostFrameCount: Int?
    var correctedFrameCount: Int?
    var interpolatedBurdenRatio: Double?
    var peakPositionUncertainty: Double?
    var peakVelocityUncertainty: Double?
    var reviewRecommended: Bool?
    var notes: [String]?
    var qualityIndex: Double? = nil
    var anomalies: [QualityAnomalySnapshot]? = nil
    var spanScores: [QualitySpanScoreSnapshot]? = nil
}

struct AnalyzerSnapshot: Codable, Identifiable {
    var analyzerID: String
    var title: String
    var confidence: Double
    var metrics: [AnalyzerMetricSnapshot]
    var notes: [String]?

    var id: String { "\(analyzerID)|\(title)" }
}

struct AnalyzerMetricSnapshot: Codable {
    var key: String
    var value: Double
    var unitLabel: String
    var note: String?
}

struct QualityAnomalySnapshot: Codable, Hashable, Identifiable {
    var anomalyID: String
    var title: String
    var severity: String
    var startFrame: Int
    var endFrame: Int?
    var score: Double
    var summary: String
    var recommendedAction: String?

    var id: String { "\(anomalyID)|\(startFrame)|\(endFrame ?? startFrame)" }
}

struct QualitySpanScoreSnapshot: Codable, Hashable, Identifiable {
    var category: String
    var reason: String
    var startFrame: Int
    var endFrame: Int
    var durationFrames: Int
    var severityScore: Double
    var averageTrackerConfidence: Double
    var scientificConfidenceMean: Double
    var dominantFailureReason: String?
    var recommendedAction: String?

    var id: String { "\(category)|\(startFrame)|\(endFrame)|\(reason)" }
}

enum EngineState: String {
    case ready = "Ready"
    case running = "Running Analysis"
    case unavailable = "Engine Unavailable"
}
