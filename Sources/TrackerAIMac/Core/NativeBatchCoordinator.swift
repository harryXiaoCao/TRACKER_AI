import Foundation

enum NativeBatchCoordinatorStage: Equatable {
    case preparingBatch(totalTrials: Int)
    case runningTrial(index: Int, totalTrials: Int, trialID: String, trialProgress: Double)
    case exportingAggregate(totalTrials: Int)
    case finished(totalTrials: Int)

    var progressFraction: Double {
        switch self {
        case let .preparingBatch(totalTrials):
            return totalTrials > 0 ? 0.02 : 0
        case let .runningTrial(index, totalTrials, _, trialProgress):
            guard totalTrials > 0 else { return 0 }
            let clampedTrialProgress = min(max(trialProgress, 0), 1)
            let completedBeforeCurrent = Double(index - 1) / Double(totalTrials)
            let currentSlice = clampedTrialProgress / Double(totalTrials)
            return min(0.95, completedBeforeCurrent + currentSlice)
        case .exportingAggregate:
            return 0.98
        case .finished:
            return 1.0
        }
    }

    var statusMessage: String {
        switch self {
        case let .preparingBatch(totalTrials):
            return "Preparing native batch coordinator for \(totalTrials) trial(s)..."
        case let .runningTrial(index, totalTrials, trialID, _):
            return "[\(index)/\(totalTrials)] Running native batch trial \(trialID)..."
        case let .exportingAggregate(totalTrials):
            return "Exporting native aggregate batch report for \(totalTrials) trial(s)..."
        case let .finished(totalTrials):
            return "Native workspace batch finished for \(totalTrials) trial(s)."
        }
    }
}

struct NativeBatchSessionEntry {
    var clip: WorkspaceClip
    var session: SessionSnapshot
}

struct NativeBatchCoordinatorResult {
    var aggregate: NativeBatchAggregateSnapshot
    var outputRoot: URL
    var trials: [NativeBatchTrialSnapshot]
    var trialDirectories: [String: URL]
}

struct NativeBatchCoordinator {
    private let analysisCoordinator = NativeAnalysisCoordinator()
    private let exporter = NativeResearchBundleExporter()

    func run(
        entries: [NativeBatchSessionEntry],
        outputRoot: URL,
        makeRunConfiguration: @escaping (NativeBatchSessionEntry, URL) async throws -> NativeRunConfiguration,
        postProcess: @escaping (AnalysisLoadResult, SessionSnapshot) async -> AnalysisLoadResult,
        progress: @escaping @Sendable (NativeBatchCoordinatorStage) async -> Void = { _ in }
    ) async throws -> NativeBatchCoordinatorResult {
        guard !entries.isEmpty else {
            throw NativeResearchExportError.emptyWorkspaceBatch
        }

        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        await progress(.preparingBatch(totalTrials: entries.count))

        var usedTrialNames = Set<String>()
        var batchTrials: [NativeBatchTrialSnapshot] = []
        var trialDirectories: [String: URL] = [:]

        for (offset, entry) in entries.enumerated() {
            let index = offset + 1
            let trialID = uniqueTrialID(for: entry.session, fallbackIndex: index, usedTrialNames: &usedTrialNames)
            let outputDirectory = outputRoot.appendingPathComponent(trialID, isDirectory: true)
            trialDirectories[trialID] = outputDirectory

            let config = try await makeRunConfiguration(entry, outputDirectory)
            let rawResult = try await analysisCoordinator.run(
                config: config,
                preservedSession: entry.session
            ) { stage in
                await progress(
                    .runningTrial(
                        index: index,
                        totalTrials: entries.count,
                        trialID: trialID,
                        trialProgress: stage.progressFraction
                    )
                )
            }
            let mergedResult = await postProcess(rawResult, entry.session)
            let mergedSession = mergedResult.session ?? entry.session
            let primaryBundle = mergedResult.trackBundles.first(where: { $0.trackID == "primary" }) ?? mergedResult.trackBundles.first

            let trial = exporter.buildBatchTrialReport(
                trialID: trialID,
                videoPath: mergedSession.videoPath,
                rows: mergedResult.analysisRows,
                session: mergedSession,
                trackID: primaryBundle?.trackID ?? "primary",
                trackName: primaryBundle?.trackName ?? "Primary Object",
                summary: mergedResult.summary,
                quality: mergedResult.quality,
                modules: mergedResult.modules,
                pairwiseMetrics: mergedResult.pairwiseMetrics
            )
            batchTrials.append(trial)
        }

        await progress(.exportingAggregate(totalTrials: entries.count))
        let aggregate = exporter.buildBatchAggregateReport(batchTrials)
        _ = try exporter.exportBatchAggregateReport(
            aggregate,
            to: outputRoot.appendingPathComponent("batch_summary.json")
        )
        await progress(.finished(totalTrials: entries.count))

        return NativeBatchCoordinatorResult(
            aggregate: aggregate,
            outputRoot: outputRoot,
            trials: batchTrials,
            trialDirectories: trialDirectories
        )
    }

    private func uniqueTrialID(
        for session: SessionSnapshot,
        fallbackIndex: Int,
        usedTrialNames: inout Set<String>
    ) -> String {
        let base = sanitizedTrialName(for: session, fallbackIndex: fallbackIndex)
        guard !usedTrialNames.contains(base) else {
            var counter = 2
            while true {
                let candidate = "\(base)_\(String(format: "%02d", counter))"
                if usedTrialNames.insert(candidate).inserted {
                    return candidate
                }
                counter += 1
            }
        }
        usedTrialNames.insert(base)
        return base
    }

    private func sanitizedTrialName(for session: SessionSnapshot, fallbackIndex: Int) -> String {
        let raw = session.metadata?.trialID?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? session.metadata?.experimentLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? URL(fileURLWithPath: session.videoPath).deletingPathExtension().lastPathComponent

        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return String(format: "trial_%02d", fallbackIndex)
        }
        return cleaned.replacingOccurrences(of: " ", with: "_")
    }
}
