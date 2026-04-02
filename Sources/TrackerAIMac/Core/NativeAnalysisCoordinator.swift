import Foundation

enum NativeAnalysisCoordinatorStage: Equatable {
    case preparingBundle
    case openingVideo
    case tracking
    case exportingBundle
    case reloadingBundle

    var progressFraction: Double {
        switch self {
        case .preparingBundle:
            return 0.1
        case .openingVideo:
            return 0.25
        case .tracking:
            return 0.6
        case .exportingBundle:
            return 0.85
        case .reloadingBundle:
            return 1.0
        }
    }

    var statusMessage: String {
        switch self {
        case .preparingBundle:
            return "Preparing native analysis bundle..."
        case .openingVideo:
            return "Opening source video for native tracking..."
        case .tracking:
            return "Running native tracking and scientific analysis..."
        case .exportingBundle:
            return "Exporting native research bundle..."
        case .reloadingBundle:
            return "Reloading exported bundle through the legacy importer..."
        }
    }
}

struct NativeAnalysisCoordinator {
    private let trackingRunner = NativeMultiObjectTrackingRunner()
    private let exporter = NativeResearchBundleExporter()
    private let legacyBridge = PythonEngineBridge()

    func run(
        config: NativeRunConfiguration,
        preservedSession: SessionSnapshot,
        progress: @escaping @Sendable (NativeAnalysisCoordinatorStage) async -> Void = { _ in }
    ) async throws -> AnalysisLoadResult {
        try Task.checkCancellation()
        await progress(.preparingBundle)
        try FileManager.default.createDirectory(at: config.outputDirectory, withIntermediateDirectories: true)

        try Task.checkCancellation()
        await progress(.openingVideo)
        let videoSource = try await NativeVideoSource.open(url: config.videoURL)

        try Task.checkCancellation()
        await progress(.tracking)
        let experiment = try trackingRunner.run(
            video: videoSource,
            session: preservedSession
        )
        let rawResult = experiment.asLoadResult(
            session: preservedSession,
            outputDirectory: config.outputDirectory
        )

        try Task.checkCancellation()
        await progress(.exportingBundle)
        try exportResearchBundle(
            result: rawResult,
            session: preservedSession,
            config: config
        )

        try Task.checkCancellation()
        await progress(.reloadingBundle)
        return try legacyBridge.loadBundle(from: config.outputDirectory)
    }

    private func exportResearchBundle(
        result: AnalysisLoadResult,
        session: SessionSnapshot,
        config: NativeRunConfiguration
    ) throws {
        let bundles = result.trackBundles.isEmpty
            ? [
                AnalysisTrackBundle(
                    trackID: "primary",
                    trackName: "Primary Object",
                    trackKind: "primary",
                    summary: result.summary,
                    quality: result.quality,
                    modules: result.modules,
                    analysisRows: result.analysisRows,
                    reportMarkdown: result.reportMarkdown,
                    exportDirectory: result.exportDirectory
                )
            ]
            : result.trackBundles

        try FileManager.default.createDirectory(at: result.exportDirectory, withIntermediateDirectories: true)
        try legacyBridge.saveSession(
            session,
            to: result.exportDirectory.appendingPathComponent("session.json")
        )

        for bundle in bundles {
            let payload = NativeResearchBundlePayload(
                session: session,
                trackID: bundle.trackID,
                trackName: bundle.trackName,
                analysisRows: bundle.analysisRows,
                pairwiseMetrics: result.pairwiseMetrics,
                eventMarkers: bundle.trackID == "primary" ? eventMarkers(from: session) : [],
                outputDirectory: bundle.exportDirectory,
                reportTemplate: session.exportPreferences?.reportTemplate ?? config.reportTemplate,
                trackingProfile: session.resolvedTrackingConfig.profile ?? config.trackingProfile,
                includeOverlay: session.exportPreferences?.includeOverlay ?? config.includeOverlay,
                includePlots: session.exportPreferences?.includePlots ?? config.includePlots,
                debugTracking: session.exportPreferences?.includeDebugTracking ?? config.debugTracking,
                summary: bundle.summary,
                quality: bundle.quality,
                modules: bundle.modules
            )
            _ = try exporter.export(payload)
        }

        try exporter.exportPairwiseMetrics(result.pairwiseMetrics, to: result.exportDirectory)
    }

    private func eventMarkers(from session: SessionSnapshot) -> [EventMarkerRecord] {
        (session.eventMarkers ?? []).compactMap {
            let origin = $0.origin ?? "derived"
            guard origin == "manual" else { return nil }
            return EventMarkerRecord(
                name: $0.name,
                frameIndex: $0.frameIndex,
                timeSeconds: $0.timeS,
                value: $0.value,
                unitLabel: $0.unitLabel,
                axis: $0.axis ?? "",
                note: $0.note ?? "",
                origin: origin
            )
        }
    }
}
