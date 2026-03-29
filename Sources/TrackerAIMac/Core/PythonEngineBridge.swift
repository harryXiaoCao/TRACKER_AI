import Foundation

enum PythonBridgeError: LocalizedError {
    case repositoryRootNotFound
    case commandFailed(String)
    case invalidCSV

    var errorDescription: String? {
        switch self {
        case .repositoryRootNotFound:
            return "Could not locate the Tracker AI repository root from the current working directory."
        case .commandFailed(let message):
            return message
        case .invalidCSV:
            return "The analysis CSV could not be parsed."
        }
    }
}

struct PythonEngineBridge {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("pyproject.toml").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                throw PythonBridgeError.repositoryRootNotFound
            }
            current = parent
        }
    }

    func loadSession(from url: URL) throws -> SessionSnapshot {
        let data = try Data(contentsOf: url)
        return try decoder.decode(SessionSnapshot.self, from: data)
    }

    func loadWorkspace(from url: URL) throws -> WorkspaceSnapshot {
        let data = try Data(contentsOf: url)
        return try decoder.decode(WorkspaceSnapshot.self, from: data)
    }

    func saveWorkspace(_ snapshot: WorkspaceSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(snapshot)
        try data.write(to: url)
    }

    func saveSession(_ snapshot: SessionSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(snapshot)
        try data.write(to: url)
    }

    func loadBundle(from directory: URL) throws -> AnalysisLoadResult {
        let trackDirectories = try discoverTrackDirectories(in: directory)
        if !trackDirectories.isEmpty {
            var trackBundles: [AnalysisTrackBundle] = []
            var session: SessionSnapshot?

            for trackDirectory in trackDirectories {
                let loaded = try loadTrackBundle(from: trackDirectory, fallbackTrackID: trackDirectory.lastPathComponent)
                trackBundles.append(loaded.bundle)
                session = session ?? loaded.session
            }

            let primaryBundle = trackBundles.first(where: { $0.trackID == "primary" }) ?? trackBundles[0]
            return AnalysisLoadResult(
                summary: primaryBundle.summary,
                quality: primaryBundle.quality,
                modules: primaryBundle.modules,
                analysisRows: primaryBundle.analysisRows,
                session: session,
                reportMarkdown: primaryBundle.reportMarkdown,
                exportDirectory: directory,
                trackBundles: trackBundles,
                pairwiseMetrics: []
            )
        }

        let loaded = try loadTrackBundle(from: directory, fallbackTrackID: "primary")
        return AnalysisLoadResult(
            summary: loaded.bundle.summary,
            quality: loaded.bundle.quality,
            modules: loaded.bundle.modules,
            analysisRows: loaded.bundle.analysisRows,
            session: loaded.session,
            reportMarkdown: loaded.bundle.reportMarkdown,
            exportDirectory: directory,
            trackBundles: [loaded.bundle],
            pairwiseMetrics: []
        )
    }

    func runAnalysis(config: NativeRunConfiguration) async throws -> AnalysisLoadResult {
        let root = try repositoryRoot()
        try FileManager.default.createDirectory(at: config.outputDirectory, withIntermediateDirectories: true)
        let trackingConfig = config.trackingConfig.resolved()

        var arguments = [
            "-m", "tracker_ai.cli",
            "analyze",
            "--video", config.videoURL.path,
            "--bbox", config.targetBox.x, config.targetBox.y, config.targetBox.width, config.targetBox.height,
            "--scale-points", config.scaleLine.x1, config.scaleLine.y1, config.scaleLine.x2, config.scaleLine.y2,
            "--reference-length", String(config.referenceLength),
            "--unit", config.unitLabel,
            "--output-dir", config.outputDirectory.path,
            "--start-frame", String(config.startFrame),
            "--window", String(config.smoothingWindow),
            "--polyorder", String(config.polyorder),
            "--tracking-profile", config.trackingProfile.rawValue,
            "--search-margin", String(trackingConfig.searchMargin ?? 2.4),
            "--expanded-search-margin", String(trackingConfig.expandedSearchMargin ?? 5.5),
            "--scale-factors",
        ]
        let scaleFactorArguments = (trackingConfig.scaleFactors ?? [0.9, 1.0, 1.1]).map { String($0) }
        arguments.append(contentsOf: scaleFactorArguments)
        arguments += ["--detection-threshold", String(trackingConfig.detectionThreshold ?? 0.50)]
        arguments += ["--low-confidence-threshold", String(trackingConfig.lowConfidenceThreshold ?? 0.36)]
        arguments += ["--reacquire-threshold", String(trackingConfig.reacquireThreshold ?? 0.56)]
        arguments += ["--suspect-after-frames", String(trackingConfig.suspectAfterFrames ?? 3)]
        arguments += ["--recovery-after-frames", String(trackingConfig.recoveryAfterFrames ?? 5)]
        arguments += ["--max-prediction-frames", String(trackingConfig.maxPredictionFrames ?? 8)]
        arguments += ["--template-update-rate", String(trackingConfig.templateUpdateRate ?? 0.10)]
        arguments += ["--stable-update-threshold", String(trackingConfig.stableUpdateThreshold ?? 0.66)]
        arguments += ["--marker-confidence-bias", String(trackingConfig.markerConfidenceBias ?? 0.58)]
        arguments += ["--auto-marker-min-ratio", String(trackingConfig.autoMarkerMinRatio ?? 0.12)]
        arguments += ["--max-interpolation-gap", String(trackingConfig.maxInterpolationGap ?? 3)]

        if let endFrame = config.endFrame {
            arguments += ["--end-frame", String(endFrame)]
        }
        if let referenceBox = config.referenceBox, referenceBox.isComplete {
            arguments += [
                "--reference-bbox",
                referenceBox.x,
                referenceBox.y,
                referenceBox.width,
                referenceBox.height,
            ]
        }
        if config.debugTracking {
            arguments.append("--debug-tracking")
        }
        if !(trackingConfig.robustRecovery ?? true) {
            arguments.append("--disable-robust-recovery")
        }
        if !(trackingConfig.bidirectionalRefinement ?? true) {
            arguments.append("--disable-bidirectional-refinement")
        }
        if !(trackingConfig.interpolateShortGaps ?? true) {
            arguments.append("--disable-interpolate-short-gaps")
        }
        if !config.includeOverlay {
            arguments.append("--skip-overlay")
        }
        if !config.includePlots {
            arguments.append("--skip-plots")
        }
        if !config.reportTemplate.isEmpty {
            arguments += ["--report-template", config.reportTemplate]
        }
        if !config.experimentLabel.isEmpty {
            arguments += ["--experiment-label", config.experimentLabel]
        }
        if !config.trialID.isEmpty {
            arguments += ["--trial-id", config.trialID]
        }
        if !config.operatorName.isEmpty {
            arguments += ["--operator", config.operatorName]
        }
        if !config.notes.isEmpty {
            arguments += ["--notes", config.notes]
        }
        if !config.tags.isEmpty {
            arguments.append("--tags")
            arguments.append(contentsOf: config.tags)
        }
        for object in config.additionalObjects where object.isComplete {
            arguments += [
                "--extra-object",
                object.trackID,
                object.name,
                object.x,
                object.y,
                object.width,
                object.height,
            ]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        let existingPythonPath = environment["PYTHONPATH"] ?? ""
        let repoPythonPath = root.appendingPathComponent("src").path
        environment["PYTHONPATH"] = existingPythonPath.isEmpty ? repoPythonPath : "\(repoPythonPath):\(existingPythonPath)"
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData, encoding: .utf8) ?? ""
        let errorText = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw PythonBridgeError.commandFailed(
                "Python analysis failed.\n\nStdout:\n\(outputText)\n\nStderr:\n\(errorText)"
            )
        }

        return try loadBundle(from: config.outputDirectory)
    }

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func discoverTrackDirectories(in directory: URL) throws -> [URL] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try entries
            .filter {
                let values = try $0.resourceValues(forKeys: [.isDirectoryKey])
                return values.isDirectory == true &&
                    FileManager.default.fileExists(atPath: $0.appendingPathComponent("analysis.csv").path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func loadTrackBundle(from directory: URL, fallbackTrackID: String) throws -> (bundle: AnalysisTrackBundle, session: SessionSnapshot?) {
        let session = try decodeIfPresent(SessionSnapshot.self, at: directory.appendingPathComponent("session.json"))
        let analysisRows = try parseAnalysisCSV(at: directory.appendingPathComponent("analysis.csv"))
        let descriptor = trackDescriptor(for: fallbackTrackID, session: session)

        return (
            AnalysisTrackBundle(
                trackID: fallbackTrackID,
                trackName: descriptor.name,
                trackKind: descriptor.kind,
                summary: nil,
                quality: nil,
                modules: [],
                analysisRows: analysisRows,
                reportMarkdown: "",
                exportDirectory: directory
            ),
            session
        )
    }

    private func trackDescriptor(for trackID: String, session: SessionSnapshot?) -> (name: String, kind: String) {
        if trackID == "primary" {
            return ("Primary Object", "primary")
        }
        if trackID == "reference" {
            return ("Reference Marker", "reference")
        }
        if let object = session?.additionalObjects?.first(where: { $0.trackID == trackID }) {
            return (object.name, object.kind ?? "secondary")
        }
        return (trackID.replacingOccurrences(of: "_", with: " ").capitalized, "secondary")
    }

    private func parseAnalysisCSV(at url: URL) throws -> [AnalysisRow] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else { return [] }
        let headers = headerLine.split(separator: ",").map(String.init)
        let headerIndex = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })

        func value(_ parts: [String], _ key: String) -> String {
            guard let index = headerIndex[key], index < parts.count else { return "" }
            return parts[index]
        }

        return try lines.dropFirst().map { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            func double(_ key: String) -> Double? {
                Double(value(parts, key))
            }

            func bool(_ key: String) -> Bool {
                let raw = value(parts, key).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return raw == "true" || raw == "1" || raw == "yes"
            }

            guard
                let frameIndex = Int(value(parts, "frame_index")),
                let time = Double(value(parts, "time_s")),
                let x = Double(value(parts, "x_units")),
                let y = Double(value(parts, "y_units")),
                let speed = Double(value(parts, "speed")),
                let acceleration = Double(value(parts, "acceleration_magnitude")),
                let trackerConfidence = Double(value(parts, "confidence")),
                let scientificConfidence = Double(value(parts, "scientific_confidence"))
            else {
                throw PythonBridgeError.invalidCSV
            }
            return AnalysisRow(
                frameIndex: frameIndex,
                timeSeconds: time,
                xUnits: x,
                yUnits: y,
                speed: speed,
                accelerationMagnitude: acceleration,
                trackerConfidence: trackerConfidence,
                scientificConfidence: scientificConfidence,
                xPixels: double("x_px"),
                yPixels: double("y_px"),
                rawXUnits: double("raw_x_units"),
                rawYUnits: double("raw_y_units"),
                xVelocity: double("vx"),
                yVelocity: double("vy"),
                xAcceleration: double("ax"),
                yAcceleration: double("ay"),
                angleDegrees: double("angle_deg"),
                positionUncertainty: double("position_uncertainty"),
                velocityUncertainty: double("velocity_uncertainty"),
                accelerationUncertainty: double("acceleration_uncertainty"),
                lost: bool("lost"),
                corrected: bool("corrected"),
                state: value(parts, "state"),
                failureReason: value(parts, "failure_reason")
            )
        }
    }
}
