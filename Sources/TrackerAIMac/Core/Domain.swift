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
    case reference
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
    var id: String { "\(trackID)-\(frameIndex)-\(note)" }
    var trackID: String = "primary"
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
    var trackingConfig: TrackingConfigSnapshot
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
    var centerOfMassXUnits: Double? = nil
    var centerOfMassYUnits: Double? = nil

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
    var advancedMode: Bool?
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
    var invertX: Bool?
    var invertY: Bool?
    var homography: [Double]?
    var presetName: String?
}

struct AnalysisConfigSnapshot: Codable {
    var smoothingWindow: Int
    var smoothingPolyorder: Int
}

struct TrackingConfigSnapshot: Codable, Equatable {
    var profile: TrackingProfileOption? = nil
    var robustRecovery: Bool? = nil
    var bidirectionalRefinement: Bool? = nil
    var debugTracking: Bool? = nil
    var searchMargin: Double? = nil
    var expandedSearchMargin: Double? = nil
    var scaleFactors: [Double]? = nil
    var detectionThreshold: Double? = nil
    var lowConfidenceThreshold: Double? = nil
    var reacquireThreshold: Double? = nil
    var suspectAfterFrames: Int? = nil
    var recoveryAfterFrames: Int? = nil
    var maxPredictionFrames: Int? = nil
    var templateUpdateRate: Double? = nil
    var stableUpdateThreshold: Double? = nil
    var markerConfidenceBias: Double? = nil
    var autoMarkerMinRatio: Double? = nil
    var interpolateShortGaps: Bool? = nil
    var maxInterpolationGap: Int? = nil

    static let pythonDefaults = TrackingConfigSnapshot(
        profile: .auto,
        robustRecovery: true,
        bidirectionalRefinement: true,
        debugTracking: false,
        searchMargin: 2.4,
        expandedSearchMargin: 5.5,
        scaleFactors: [0.9, 1.0, 1.1],
        detectionThreshold: 0.50,
        lowConfidenceThreshold: 0.36,
        reacquireThreshold: 0.56,
        suspectAfterFrames: 3,
        recoveryAfterFrames: 5,
        maxPredictionFrames: 8,
        templateUpdateRate: 0.10,
        stableUpdateThreshold: 0.66,
        markerConfidenceBias: 0.58,
        autoMarkerMinRatio: 0.12,
        interpolateShortGaps: true,
        maxInterpolationGap: 3
    )

    func resolved() -> TrackingConfigSnapshot {
        let defaults = Self.pythonDefaults
        return TrackingConfigSnapshot(
            profile: profile ?? defaults.profile,
            robustRecovery: robustRecovery ?? defaults.robustRecovery,
            bidirectionalRefinement: bidirectionalRefinement ?? defaults.bidirectionalRefinement,
            debugTracking: debugTracking ?? defaults.debugTracking,
            searchMargin: searchMargin ?? defaults.searchMargin,
            expandedSearchMargin: expandedSearchMargin ?? defaults.expandedSearchMargin,
            scaleFactors: scaleFactors ?? defaults.scaleFactors,
            detectionThreshold: detectionThreshold ?? defaults.detectionThreshold,
            lowConfidenceThreshold: lowConfidenceThreshold ?? defaults.lowConfidenceThreshold,
            reacquireThreshold: reacquireThreshold ?? defaults.reacquireThreshold,
            suspectAfterFrames: suspectAfterFrames ?? defaults.suspectAfterFrames,
            recoveryAfterFrames: recoveryAfterFrames ?? defaults.recoveryAfterFrames,
            maxPredictionFrames: maxPredictionFrames ?? defaults.maxPredictionFrames,
            templateUpdateRate: templateUpdateRate ?? defaults.templateUpdateRate,
            stableUpdateThreshold: stableUpdateThreshold ?? defaults.stableUpdateThreshold,
            markerConfidenceBias: markerConfidenceBias ?? defaults.markerConfidenceBias,
            autoMarkerMinRatio: autoMarkerMinRatio ?? defaults.autoMarkerMinRatio,
            interpolateShortGaps: interpolateShortGaps ?? defaults.interpolateShortGaps,
            maxInterpolationGap: maxInterpolationGap ?? defaults.maxInterpolationGap
        )
    }
}

struct ExperimentMetadataSnapshot: Codable {
    var experimentLabel: String?
    var trialID: String?
    var operatorName: String?
    var notes: String?
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case experimentLabel = "experiment_label"
        case trialID = "trial_id"
        case operatorName = "operator_name"
        case notes
        case tags
    }

    enum LegacyCodingKeys: String, CodingKey {
        case experimentLabel
        case trialID
        case operatorName
        case notes
        case tags
    }

    enum AlternateCodingKeys: String, CodingKey {
        case experimentLabel
        case trialId
        case operatorName
        case notes
        case tags
    }

    init(
        experimentLabel: String?,
        trialID: String?,
        operatorName: String?,
        notes: String?,
        tags: [String]?
    ) {
        self.experimentLabel = experimentLabel
        self.trialID = trialID
        self.operatorName = operatorName
        self.notes = notes
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let alternate = try decoder.container(keyedBy: AlternateCodingKeys.self)
        experimentLabel = try container.decodeIfPresent(String.self, forKey: .experimentLabel)
            ?? legacy.decodeIfPresent(String.self, forKey: .experimentLabel)
            ?? alternate.decodeIfPresent(String.self, forKey: .experimentLabel)
        trialID = try container.decodeIfPresent(String.self, forKey: .trialID)
            ?? legacy.decodeIfPresent(String.self, forKey: .trialID)
            ?? alternate.decodeIfPresent(String.self, forKey: .trialId)
        operatorName = try container.decodeIfPresent(String.self, forKey: .operatorName)
            ?? legacy.decodeIfPresent(String.self, forKey: .operatorName)
            ?? alternate.decodeIfPresent(String.self, forKey: .operatorName)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
            ?? legacy.decodeIfPresent(String.self, forKey: .notes)
            ?? alternate.decodeIfPresent(String.self, forKey: .notes)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
            ?? legacy.decodeIfPresent([String].self, forKey: .tags)
            ?? alternate.decodeIfPresent([String].self, forKey: .tags)
    }
}

struct CorrectionSnapshot: Codable {
    var trackID: String?
    var frameIndex: Int
    var bbox: BBoxSnapshot
    var note: String?

    enum CodingKeys: String, CodingKey {
        case trackID = "track_id"
        case frameIndex = "frame_index"
        case bbox
        case note
    }

    enum LegacyCodingKeys: String, CodingKey {
        case trackID
        case frameIndex
        case bbox
        case note
    }

    enum AlternateCodingKeys: String, CodingKey {
        case trackId
        case frameIndex
        case bbox
        case note
    }

    init(trackID: String?, frameIndex: Int, bbox: BBoxSnapshot, note: String?) {
        self.trackID = trackID
        self.frameIndex = frameIndex
        self.bbox = bbox
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let alternate = try decoder.container(keyedBy: AlternateCodingKeys.self)
        trackID = try container.decodeIfPresent(String.self, forKey: .trackID)
            ?? legacy.decodeIfPresent(String.self, forKey: .trackID)
            ?? alternate.decodeIfPresent(String.self, forKey: .trackId)
        frameIndex = try container.decodeIfPresent(Int.self, forKey: .frameIndex)
            ?? legacy.decodeIfPresent(Int.self, forKey: .frameIndex)
            ?? alternate.decode(Int.self, forKey: .frameIndex)
        bbox = try container.decodeIfPresent(BBoxSnapshot.self, forKey: .bbox)
            ?? legacy.decodeIfPresent(BBoxSnapshot.self, forKey: .bbox)
            ?? alternate.decode(BBoxSnapshot.self, forKey: .bbox)
        note = try container.decodeIfPresent(String.self, forKey: .note)
            ?? legacy.decodeIfPresent(String.self, forKey: .note)
            ?? alternate.decodeIfPresent(String.self, forKey: .note)
    }
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

    enum CodingKeys: String, CodingKey {
        case name
        case frameIndex = "frame_index"
        case timeS = "time_s"
        case value
        case unitLabel = "unit_label"
        case axis
        case note
        case origin
    }

    enum LegacyCodingKeys: String, CodingKey {
        case name
        case frameIndex
        case timeS
        case value
        case unitLabel
        case axis
        case note
        case origin
    }

    init(
        name: String,
        frameIndex: Int,
        timeS: Double,
        value: Double,
        unitLabel: String,
        axis: String?,
        note: String?,
        origin: String?
    ) {
        self.name = name
        self.frameIndex = frameIndex
        self.timeS = timeS
        self.value = value
        self.unitLabel = unitLabel
        self.axis = axis
        self.note = note
        self.origin = origin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? legacy.decode(String.self, forKey: .name)
        frameIndex = try container.decodeIfPresent(Int.self, forKey: .frameIndex)
            ?? legacy.decode(Int.self, forKey: .frameIndex)
        timeS = try container.decodeIfPresent(Double.self, forKey: .timeS)
            ?? legacy.decode(Double.self, forKey: .timeS)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
            ?? legacy.decode(Double.self, forKey: .value)
        unitLabel = try container.decodeIfPresent(String.self, forKey: .unitLabel)
            ?? legacy.decode(String.self, forKey: .unitLabel)
        axis = try container.decodeIfPresent(String.self, forKey: .axis)
            ?? legacy.decodeIfPresent(String.self, forKey: .axis)
        note = try container.decodeIfPresent(String.self, forKey: .note)
            ?? legacy.decodeIfPresent(String.self, forKey: .note)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
            ?? legacy.decodeIfPresent(String.self, forKey: .origin)
    }
}

struct AdditionalObjectSnapshot: Codable {
    var trackID: String
    var name: String
    var kind: String?
    var bbox: BBoxSnapshot

    enum CodingKeys: String, CodingKey {
        case trackID = "track_id"
        case name
        case kind
        case bbox
    }

    enum LegacyCodingKeys: String, CodingKey {
        case trackID
        case name
        case kind
        case bbox
    }

    enum AlternateCodingKeys: String, CodingKey {
        case trackId
        case name
        case kind
        case bbox
    }

    init(trackID: String, name: String, kind: String?, bbox: BBoxSnapshot) {
        self.trackID = trackID
        self.name = name
        self.kind = kind
        self.bbox = bbox
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let alternate = try decoder.container(keyedBy: AlternateCodingKeys.self)
        trackID = try container.decodeIfPresent(String.self, forKey: .trackID)
            ?? legacy.decodeIfPresent(String.self, forKey: .trackID)
            ?? alternate.decode(String.self, forKey: .trackId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? legacy.decodeIfPresent(String.self, forKey: .name)
            ?? alternate.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
            ?? legacy.decodeIfPresent(String.self, forKey: .kind)
            ?? alternate.decodeIfPresent(String.self, forKey: .kind)
        bbox = try container.decodeIfPresent(BBoxSnapshot.self, forKey: .bbox)
            ?? legacy.decodeIfPresent(BBoxSnapshot.self, forKey: .bbox)
            ?? alternate.decode(BBoxSnapshot.self, forKey: .bbox)
    }
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

extension SessionSnapshot {
    var resolvedTrackingConfig: TrackingConfigSnapshot {
        (trackingConfig ?? .pythonDefaults).resolved()
    }
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
