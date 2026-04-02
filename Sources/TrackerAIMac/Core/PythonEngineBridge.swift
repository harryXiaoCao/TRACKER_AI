import Foundation

enum PythonBridgeError: LocalizedError {
    case invalidCSV

    var errorDescription: String? {
        switch self {
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
        let pairwiseMetrics = try parsePairwiseMetricsCSV(at: directory.appendingPathComponent("pairwise_metrics.csv"))
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
                pairwiseMetrics: pairwiseMetrics
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
            pairwiseMetrics: pairwiseMetrics
        )
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

    private func parsePairwiseMetricsCSV(at url: URL) throws -> [PairwiseMetricSnapshot] {
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

        var groupedSamples: [String: (primaryTrackID: String, secondaryTrackID: String, samples: [PairwiseMetricSampleSnapshot])] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard !parts.allSatisfy(\.isEmpty) else { continue }

            func double(_ key: String) -> Double? {
                let raw = value(parts, key)
                return raw.isEmpty ? nil : Double(raw)
            }

            guard
                let frameIndex = Int(value(parts, "frame_index")),
                let timeSeconds = Double(value(parts, "time_s")),
                let distanceUnits = Double(value(parts, "distance_units")),
                let relativeSpeedUnitsPerSecond = Double(value(parts, "relative_speed_units_s")),
                let relativeDXUnits = Double(value(parts, "relative_dx_units")),
                let relativeDYUnits = Double(value(parts, "relative_dy_units"))
            else {
                throw PythonBridgeError.invalidCSV
            }

            let quoteSet = CharacterSet(charactersIn: "\"")
            let primaryTrackID = value(parts, "primary_track_id").trimmingCharacters(in: quoteSet)
            let secondaryTrackID = value(parts, "secondary_track_id").trimmingCharacters(in: quoteSet)
            let id = "\(primaryTrackID)|\(secondaryTrackID)"
            let sample = PairwiseMetricSampleSnapshot(
                frameIndex: frameIndex,
                timeSeconds: timeSeconds,
                distanceUnits: distanceUnits,
                relativeSpeedUnitsPerSecond: relativeSpeedUnitsPerSecond,
                relativeDXUnits: relativeDXUnits,
                relativeDYUnits: relativeDYUnits,
                centerOfMassXUnits: double("center_of_mass_x_units"),
                centerOfMassYUnits: double("center_of_mass_y_units")
            )

            if groupedSamples[id] == nil {
                groupedSamples[id] = (primaryTrackID, secondaryTrackID, [])
            }
            groupedSamples[id]?.samples.append(sample)
        }

        return groupedSamples.values
            .map {
                PairwiseMetricSnapshot(
                    primaryTrackID: $0.primaryTrackID,
                    secondaryTrackID: $0.secondaryTrackID,
                    samples: $0.samples.sorted { $0.frameIndex < $1.frameIndex }
                )
            }
            .sorted { $0.id < $1.id }
    }
}
