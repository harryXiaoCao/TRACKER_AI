import Foundation

enum NativeResearchExportError: LocalizedError {
    case missingVideoPath
    case emptyWorkspaceBatch

    var errorDescription: String? {
        switch self {
        case .missingVideoPath:
            return "A video must be loaded before exporting a native research package."
        case .emptyWorkspaceBatch:
            return "Add or save at least one session-backed workspace clip before running a native batch export."
        }
    }
}

struct NativeResearchBundlePayload {
    var session: SessionSnapshot
    var trackID: String
    var trackName: String
    var analysisRows: [AnalysisRow]
    var pairwiseMetrics: [PairwiseMetricSnapshot]
    var eventMarkers: [EventMarkerRecord]
    var outputDirectory: URL
    var reportTemplate: String
    var trackingProfile: TrackingProfileOption
    var includeOverlay: Bool
    var includePlots: Bool
    var debugTracking: Bool
    var summary: SummarySnapshot?
    var quality: QualitySnapshot?
    var modules: [AnalyzerSnapshot]
}

struct NativeWindowSummary: Codable {
    var startFrame: Int
    var endFrame: Int
    var durationSeconds: Double
    var displacement: Double
    var meanSpeed: Double
    var maxSpeed: Double
    var maxAcceleration: Double
}

struct NativeExperimentManifest: Codable {
    var sessionVersion: Int
    var videoPath: String
    var trackID: String
    var trackName: String
    var trackingProfile: String
    var referenceLength: Double
    var unitLabel: String
    var selectedStartFrame: Int?
    var selectedEndFrame: Int?
    var additionalObjects: [String]
    var eventCount: Int
    var reportTemplate: String
    var reproduceCommand: String
}

struct NativeBatchComparisonSnapshot: Codable {
    var generatedAt: String
    var trialCount: Int
    var classifications: [String: Int]
    var qcBadges: [String: Int]
    var rankings: [String: [String]]
}

struct NativeScientificProcessor {
    func process(
        observations: [NativeTrackingObservation],
        calibration: CalibrationProfile,
        config: AnalysisConfigSnapshot
    ) -> [AnalysisRow] {
        guard !observations.isEmpty else { return [] }

        let times = observations.map(\.timeSeconds)
        let xPixels = observations.map(\.centroidXPixels)
        let yPixels = observations.map(\.centroidYPixels)
        let confidence = observations.map(\.confidence)
        let correctedFlags = observations.map(\.corrected)
        let lostFlags = observations.map(\.lost)

        let rawCoordinates = zip(xPixels, yPixels).map { calibration.transformPoint(xPx: $0, yPx: $1) }
        let rawX = rawCoordinates.map(\.0)
        let rawY = rawCoordinates.map(\.1)
        let xUnits = smoothSeries(rawX, config: config)
        let yUnits = smoothSeries(rawY, config: config)
        let positionUncertainty = zip(xUnits, yUnits).enumerated().map { index, values in
            let deltaX = values.0 - rawX[index]
            let deltaY = values.1 - rawY[index]
            return sqrt((deltaX * deltaX) + (deltaY * deltaY))
        }
        let referenceLength = max(calibration.referenceLength, 1e-6)

        let xVelocity: [Double]
        let yVelocity: [Double]
        let xAcceleration: [Double]
        let yAcceleration: [Double]
        let speed: [Double]
        let accelerationMagnitude: [Double]
        let angleDegrees: [Double]
        let velocityUncertainty: [Double]
        let accelerationUncertainty: [Double]

        if observations.count < 2 {
            let zeros = Array(repeating: 0.0, count: observations.count)
            xVelocity = zeros
            yVelocity = zeros
            xAcceleration = zeros
            yAcceleration = zeros
            speed = zeros
            accelerationMagnitude = zeros
            angleDegrees = zeros
            velocityUncertainty = zeros
            accelerationUncertainty = zeros
        } else {
            xVelocity = gradient(values: xUnits, coordinates: times)
            yVelocity = gradient(values: yUnits, coordinates: times)
            xAcceleration = gradient(values: xVelocity, coordinates: times)
            yAcceleration = gradient(values: yVelocity, coordinates: times)
            speed = zip(xVelocity, yVelocity).map { sqrt(($0 * $0) + ($1 * $1)) }
            accelerationMagnitude = zip(xAcceleration, yAcceleration).map { sqrt(($0 * $0) + ($1 * $1)) }
            angleDegrees = zip(yVelocity, xVelocity).map { atan2($0, $1) * 180 / .pi }
            velocityUncertainty = gradient(values: positionUncertainty, coordinates: times).map(abs)
            accelerationUncertainty = gradient(values: velocityUncertainty, coordinates: times).map(abs)
        }

        let scientificConfidence = confidence.enumerated().map { index, trackerConfidence in
            let uncertaintyPenalty = min((positionUncertainty[safe: index] ?? 0) / referenceLength, 0.35)
            let correctedPenalty = correctedFlags[safe: index] == true ? 0.10 : 0.0
            let lostPenalty = lostFlags[safe: index] == true ? 0.18 : 0.0
            return clamp(trackerConfidence - uncertaintyPenalty - correctedPenalty - lostPenalty)
        }

        return observations.enumerated().map { index, observation in
            AnalysisRow(
                frameIndex: observation.frameIndex,
                timeSeconds: observation.timeSeconds,
                xUnits: xUnits[safe: index] ?? rawX[index],
                yUnits: yUnits[safe: index] ?? rawY[index],
                speed: speed[safe: index] ?? 0,
                accelerationMagnitude: accelerationMagnitude[safe: index] ?? 0,
                trackerConfidence: observation.confidence,
                scientificConfidence: scientificConfidence[safe: index] ?? observation.confidence,
                xPixels: observation.centroidXPixels,
                yPixels: observation.centroidYPixels,
                rawXUnits: rawX[safe: index],
                rawYUnits: rawY[safe: index],
                xVelocity: xVelocity[safe: index],
                yVelocity: yVelocity[safe: index],
                xAcceleration: xAcceleration[safe: index],
                yAcceleration: yAcceleration[safe: index],
                angleDegrees: angleDegrees[safe: index],
                positionUncertainty: positionUncertainty[safe: index],
                velocityUncertainty: velocityUncertainty[safe: index],
                accelerationUncertainty: accelerationUncertainty[safe: index],
                lost: observation.lost,
                corrected: observation.corrected,
                state: observation.state,
                failureReason: observation.failureReason ?? ""
            )
        }
    }

    func process(rows: [AnalysisRow], session: SessionSnapshot) -> [AnalysisRow] {
        guard !rows.isEmpty else { return [] }

        let calibrationProfile = try? session.calibration.makeCalibrationProfile()
        guard let calibrationProfile else { return rows }

        if rows.allSatisfy({ $0.xPixels != nil && $0.yPixels != nil }) {
            let observations = rows.map { row in
                let xPixels = row.xPixels ?? 0
                let yPixels = row.yPixels ?? 0
                return NativeTrackingObservation(
                    frameIndex: row.frameIndex,
                    timeSeconds: row.timeSeconds,
                    centroidXPixels: xPixels,
                    centroidYPixels: yPixels,
                    bbox: BBoxSnapshot(x: xPixels, y: yPixels, width: 1, height: 1),
                    confidence: row.trackerConfidence,
                    lost: row.lost,
                    corrected: row.corrected,
                    state: row.state,
                    failureReason: row.failureReason.isEmpty ? nil : row.failureReason,
                    source: row.lost ? "predicted" : (row.corrected ? "manual_correction" : "measured"),
                    isInferred: row.lost,
                    isInterpolated: false
                )
            }

            let processed = process(
                observations: observations,
                calibration: calibrationProfile,
                config: session.analysisConfig
            )

            return processed.enumerated().map { index, processedRow in
                let originalRow = rows[index]
                return AnalysisRow(
                    frameIndex: processedRow.frameIndex,
                    timeSeconds: processedRow.timeSeconds,
                    xUnits: processedRow.xUnits,
                    yUnits: processedRow.yUnits,
                    speed: processedRow.speed,
                    accelerationMagnitude: processedRow.accelerationMagnitude,
                    trackerConfidence: processedRow.trackerConfidence,
                    scientificConfidence: processedRow.scientificConfidence,
                    xPixels: originalRow.xPixels ?? processedRow.xPixels,
                    yPixels: originalRow.yPixels ?? processedRow.yPixels,
                    rawXUnits: originalRow.rawXUnits ?? processedRow.rawXUnits,
                    rawYUnits: originalRow.rawYUnits ?? processedRow.rawYUnits,
                    xVelocity: processedRow.xVelocity,
                    yVelocity: processedRow.yVelocity,
                    xAcceleration: processedRow.xAcceleration,
                    yAcceleration: processedRow.yAcceleration,
                    angleDegrees: processedRow.angleDegrees,
                    positionUncertainty: processedRow.positionUncertainty,
                    velocityUncertainty: processedRow.velocityUncertainty,
                    accelerationUncertainty: processedRow.accelerationUncertainty,
                    lost: processedRow.lost,
                    corrected: processedRow.corrected,
                    state: processedRow.state,
                    failureReason: processedRow.failureReason
                )
            }
        }

        let rawCoordinates = rows.map { row -> (Double, Double) in
            if let rawXUnits = row.rawXUnits, let rawYUnits = row.rawYUnits {
                return (rawXUnits, rawYUnits)
            }
            if let xPixels = row.xPixels, let yPixels = row.yPixels {
                return calibrationProfile.transformPoint(xPx: xPixels, yPx: yPixels)
            }
            return (row.xUnits, row.yUnits)
        }
        let rawX = rawCoordinates.map(\.0)
        let rawY = rawCoordinates.map(\.1)
        let xUnits = smoothSeries(rawX, config: session.analysisConfig)
        let yUnits = smoothSeries(rawY, config: session.analysisConfig)
        let times = rows.map(\.timeSeconds)
        let positionUncertainty = zip(xUnits, yUnits).enumerated().map { index, values in
            let deltaX = values.0 - rawX[index]
            let deltaY = values.1 - rawY[index]
            return sqrt((deltaX * deltaX) + (deltaY * deltaY))
        }

        let xVelocity = rows.count < 2 ? Array(repeating: 0.0, count: rows.count) : gradient(values: xUnits, coordinates: times)
        let yVelocity = rows.count < 2 ? Array(repeating: 0.0, count: rows.count) : gradient(values: yUnits, coordinates: times)
        let xAcceleration = rows.count < 2 ? Array(repeating: 0.0, count: rows.count) : gradient(values: xVelocity, coordinates: times)
        let yAcceleration = rows.count < 2 ? Array(repeating: 0.0, count: rows.count) : gradient(values: yVelocity, coordinates: times)
        let speed = zip(xVelocity, yVelocity).map { sqrt(($0 * $0) + ($1 * $1)) }
        let accelerationMagnitude = zip(xAcceleration, yAcceleration).map { sqrt(($0 * $0) + ($1 * $1)) }
        let angleDegrees = zip(yVelocity, xVelocity).map { atan2($0, $1) * 180 / .pi }
        let velocityUncertainty = rows.count < 2 ? Array(repeating: 0.0, count: rows.count) : gradient(values: positionUncertainty, coordinates: times).map(abs)
        let accelerationUncertainty = rows.count < 2 ? Array(repeating: 0.0, count: rows.count) : gradient(values: velocityUncertainty, coordinates: times).map(abs)
        let referenceLength = max(calibrationProfile.referenceLength, 1e-6)

        return rows.enumerated().map { index, originalRow in
            let uncertaintyPenalty = min((positionUncertainty[safe: index] ?? 0) / referenceLength, 0.35)
            let correctedPenalty = originalRow.corrected ? 0.10 : 0.0
            let lostPenalty = originalRow.lost ? 0.18 : 0.0
            return AnalysisRow(
                frameIndex: originalRow.frameIndex,
                timeSeconds: originalRow.timeSeconds,
                xUnits: xUnits[safe: index] ?? originalRow.xUnits,
                yUnits: yUnits[safe: index] ?? originalRow.yUnits,
                speed: speed[safe: index] ?? originalRow.speed,
                accelerationMagnitude: accelerationMagnitude[safe: index] ?? originalRow.accelerationMagnitude,
                trackerConfidence: originalRow.trackerConfidence,
                scientificConfidence: clamp(originalRow.trackerConfidence - uncertaintyPenalty - correctedPenalty - lostPenalty),
                xPixels: originalRow.xPixels,
                yPixels: originalRow.yPixels,
                rawXUnits: originalRow.rawXUnits ?? rawX[safe: index],
                rawYUnits: originalRow.rawYUnits ?? rawY[safe: index],
                xVelocity: xVelocity[safe: index],
                yVelocity: yVelocity[safe: index],
                xAcceleration: xAcceleration[safe: index],
                yAcceleration: yAcceleration[safe: index],
                angleDegrees: angleDegrees[safe: index],
                positionUncertainty: positionUncertainty[safe: index],
                velocityUncertainty: velocityUncertainty[safe: index],
                accelerationUncertainty: accelerationUncertainty[safe: index],
                lost: originalRow.lost,
                corrected: originalRow.corrected,
                state: originalRow.state,
                failureReason: originalRow.failureReason
            )
        }
    }

    func buildDerivedEvents(rows: [AnalysisRow], unitLabel: String) -> [EventMarkerRecord] {
        guard !rows.isEmpty else { return [] }
        var events: [EventMarkerRecord] = []

        func peakEvent(
            keyPath: KeyPath<AnalysisRow, Double>,
            name: String,
            unit: String,
            axis: String = "",
            note: String
        ) {
            guard let row = rows.max(by: { $0[keyPath: keyPath] < $1[keyPath: keyPath] }) else { return }
            events.append(
                EventMarkerRecord(
                    name: name,
                    frameIndex: row.frameIndex,
                    timeSeconds: row.timeSeconds,
                    value: row[keyPath: keyPath],
                    unitLabel: unit,
                    axis: axis,
                    note: note,
                    origin: "derived"
                )
            )
        }

        peakEvent(keyPath: \.speed, name: "peak_speed", unit: "\(unitLabel)/s", note: "Maximum speed")
        peakEvent(keyPath: \.accelerationMagnitude, name: "peak_acceleration", unit: "\(unitLabel)/s^2", note: "Maximum acceleration")
        peakEvent(keyPath: \.yUnits, name: "apex", unit: unitLabel, axis: "y", note: "Maximum vertical position")
        peakEvent(keyPath: \.xUnits, name: "furthest_x", unit: unitLabel, axis: "x", note: "Maximum horizontal position")

        events.append(contentsOf: zeroCrossingEvents(rows: rows, keyPath: \.yVelocity, name: "vy_zero_crossing", unitLabel: "\(unitLabel)/s", axis: "y"))
        events.append(contentsOf: zeroCrossingEvents(rows: rows, keyPath: \.xVelocity, name: "vx_zero_crossing", unitLabel: "\(unitLabel)/s", axis: "x"))

        return deduplicateEvents(events, preferManual: false)
    }

    func summarizeWindow(rows: [AnalysisRow], startFrame: Int?, endFrame: Int?) -> NativeWindowSummary? {
        guard !rows.isEmpty else { return nil }
        let firstFrame = rows.first?.frameIndex ?? 0
        let lastFrame = rows.last?.frameIndex ?? 0
        let boundedStart = max(min(startFrame ?? firstFrame, endFrame ?? lastFrame), firstFrame)
        let boundedEnd = min(max(startFrame ?? firstFrame, endFrame ?? lastFrame), lastFrame)
        guard boundedEnd > boundedStart else { return nil }

        let windowRows = rows.filter { $0.frameIndex >= boundedStart && $0.frameIndex <= boundedEnd }
        guard let first = windowRows.first, let last = windowRows.last, windowRows.count > 1 else { return nil }

        let dx = last.xUnits - first.xUnits
        let dy = last.yUnits - first.yUnits
        return NativeWindowSummary(
            startFrame: boundedStart,
            endFrame: boundedEnd,
            durationSeconds: max(last.timeSeconds - first.timeSeconds, 0),
            displacement: sqrt((dx * dx) + (dy * dy)),
            meanSpeed: windowRows.map(\.speed).mean(),
            maxSpeed: windowRows.map(\.speed).max() ?? 0,
            maxAcceleration: windowRows.map(\.accelerationMagnitude).max() ?? 0
        )
    }

    private func smoothSeries(_ values: [Double], config: AnalysisConfigSnapshot) -> [Double] {
        guard values.count >= 5 else { return values }
        let cappedWindow = min(config.smoothingWindow, values.count.isMultiple(of: 2) ? values.count - 1 : values.count)
        guard cappedWindow >= 3 else { return values }
        let localOrder = min(config.smoothingPolyorder, cappedWindow - 1)
        return polyfitSmooth(values: values, window: cappedWindow, polyorder: localOrder)
    }

    private func polyfitSmooth(values: [Double], window: Int, polyorder: Int) -> [Double] {
        let halfWindow = window / 2
        let xs = values.indices.map(Double.init)
        return values.indices.map { index in
            let start = max(0, index - halfWindow)
            let end = min(values.count, index + halfWindow + 1)
            let localX = Array(xs[start..<end])
            let localY = Array(values[start..<end])
            let localOrder = min(polyorder, localX.count - 1)
            guard localOrder > 0, let coefficients = polynomialFit(x: localX, y: localY, order: localOrder) else {
                return localY.mean()
            }
            return evaluatePolynomial(coefficients, at: xs[index])
        }
    }

    private func polynomialFit(x: [Double], y: [Double], order: Int) -> [Double]? {
        let size = order + 1
        var matrix = Array(repeating: Array(repeating: 0.0, count: size + 1), count: size)

        for row in 0..<size {
            for column in 0..<size {
                matrix[row][column] = x.map { pow($0, Double(row + column)) }.reduce(0, +)
            }
            matrix[row][size] = zip(x, y).map { pow($0, Double(row)) * $1 }.reduce(0, +)
        }

        for pivot in 0..<size {
            var maxRow = pivot
            for row in pivot..<size where abs(matrix[row][pivot]) > abs(matrix[maxRow][pivot]) {
                maxRow = row
            }
            guard abs(matrix[maxRow][pivot]) > 1e-9 else { return nil }
            if maxRow != pivot {
                matrix.swapAt(maxRow, pivot)
            }
            let divisor = matrix[pivot][pivot]
            for column in pivot...size {
                matrix[pivot][column] /= divisor
            }
            for row in 0..<size where row != pivot {
                let factor = matrix[row][pivot]
                for column in pivot...size {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
            }
        }

        return (0..<size).map { matrix[$0][size] }
    }

    private func evaluatePolynomial(_ coefficients: [Double], at x: Double) -> Double {
        coefficients.enumerated().reduce(0.0) { partial, element in
            partial + (element.element * pow(x, Double(element.offset)))
        }
    }

    private func gradient(values: [Double], coordinates: [Double]) -> [Double] {
        guard values.count == coordinates.count, !values.isEmpty else { return [] }
        guard values.count > 1 else { return [0] }

        if values.count == 2 {
            let step = max(coordinates[1] - coordinates[0], 1e-9)
            let slope = (values[1] - values[0]) / step
            return [slope, slope]
        }

        var result = Array(repeating: 0.0, count: values.count)
        let leadingStep = max(coordinates[1] - coordinates[0], 1e-9)
        result[0] = (values[1] - values[0]) / leadingStep

        let trailingStep = max(coordinates[values.count - 1] - coordinates[values.count - 2], 1e-9)
        result[values.count - 1] = (values[values.count - 1] - values[values.count - 2]) / trailingStep

        for index in 1..<(values.count - 1) {
            let leftStep = max(coordinates[index] - coordinates[index - 1], 1e-9)
            let rightStep = max(coordinates[index + 1] - coordinates[index], 1e-9)
            let leftWeight = -rightStep / (leftStep * (leftStep + rightStep))
            let centerWeight = (rightStep - leftStep) / (leftStep * rightStep)
            let rightWeight = leftStep / (rightStep * (leftStep + rightStep))
            result[index] = (leftWeight * values[index - 1]) + (centerWeight * values[index]) + (rightWeight * values[index + 1])
        }
        return result
    }

    private func clamp(_ value: Double, min minimum: Double = 0.0, max maximum: Double = 1.0) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    private func zeroCrossingEvents(
        rows: [AnalysisRow],
        keyPath: KeyPath<AnalysisRow, Double?>,
        name: String,
        unitLabel: String,
        axis: String
    ) -> [EventMarkerRecord] {
        guard rows.count >= 2 else { return [] }
        var events: [EventMarkerRecord] = []
        var previous = sign(of: rows[0][keyPath: keyPath] ?? 0)
        for row in rows.dropFirst() {
            let current = sign(of: row[keyPath: keyPath] ?? 0)
            if current == 0 || previous == 0 {
                previous = current
                continue
            }
            if current != previous {
                events.append(
                    EventMarkerRecord(
                        name: name,
                        frameIndex: row.frameIndex,
                        timeSeconds: row.timeSeconds,
                        value: row[keyPath: keyPath] ?? 0,
                        unitLabel: unitLabel,
                        axis: axis,
                        note: "Zero crossing",
                        origin: "derived"
                    )
                )
            }
            previous = current
        }
        return events
    }

    private func sign(of value: Double) -> Int {
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return 0
    }

    private func deduplicateEvents(_ events: [EventMarkerRecord], preferManual: Bool) -> [EventMarkerRecord] {
        var seen = Set<String>()
        let ordered = events.sorted { lhs, rhs in
            let lhsPriority = preferManual && lhs.origin == "manual" ? 0 : 1
            let rhsPriority = preferManual && rhs.origin == "manual" ? 0 : 1
            return (lhs.frameIndex, lhs.name, lhs.axis, lhsPriority, lhs.origin) < (rhs.frameIndex, rhs.name, rhs.axis, rhsPriority, rhs.origin)
        }

        var filtered: [EventMarkerRecord] = []
        for event in ordered {
            let key = "\(event.name)|\(event.frameIndex)|\(event.axis)"
            if seen.insert(key).inserted {
                filtered.append(event)
            }
        }
        return filtered
    }
}

struct NativeTrackingObservation {
    var frameIndex: Int
    var timeSeconds: Double
    var centroidXPixels: Double
    var centroidYPixels: Double
    var bbox: BBoxSnapshot
    var confidence: Double
    var lost: Bool
    var corrected: Bool
    var state: String
    var failureReason: String?
    var source: String
    var isInferred: Bool
    var isInterpolated: Bool
    var debug: [String: String] = [:]
    var trackID: String = "primary"
    var trackName: String = "Primary Object"
    var trackKind: String = "primary"
}

struct NativeTrackReconstruction {
    var trackID: String
    var trackName: String
    var trackKind: String
    var observations: [NativeTrackingObservation]
    var quality: TrackQualitySnapshot
    var averageConfidence: Double

    var observationByFrame: [Int: NativeTrackingObservation] {
        Dictionary(uniqueKeysWithValues: observations.map { ($0.frameIndex, $0) })
    }
}

struct NativeTrackingPipeline {
    func reconstructTrack(bundle: AnalysisTrackBundle, session: SessionSnapshot) -> NativeTrackReconstruction? {
        let seedBox = seedBox(for: bundle, session: session)
        guard !bundle.analysisRows.isEmpty else {
            return NativeTrackReconstruction(
                trackID: bundle.trackID,
                trackName: bundle.trackName,
                trackKind: bundle.trackKind,
                observations: [],
                quality: NativeTrackRuntimeDerivation.emptyQuality(),
                averageConfidence: 0
            )
        }

        let observations = bundle.analysisRows.map { row in
            let centroidXPixels = row.xPixels ?? (seedBox.x + (seedBox.width / 2))
            let centroidYPixels = row.yPixels ?? (seedBox.y + (seedBox.height / 2))
            let bbox = BBoxSnapshot(
                x: centroidXPixels - (seedBox.width / 2),
                y: centroidYPixels - (seedBox.height / 2),
                width: seedBox.width,
                height: seedBox.height
            )
            return NativeTrackingObservation(
                frameIndex: row.frameIndex,
                timeSeconds: row.timeSeconds,
                centroidXPixels: centroidXPixels,
                centroidYPixels: centroidYPixels,
                bbox: bbox,
                confidence: row.trackerConfidence,
                lost: row.lost,
                corrected: row.corrected,
                state: normalizedState(row.state, lost: row.lost),
                failureReason: row.failureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : row.failureReason,
                source: row.lost ? "predicted" : (row.corrected ? "manual_correction" : "measured"),
                isInferred: row.lost,
                isInterpolated: false
            )
        }

        let interpolated = NativeTrackRuntimeDerivation.interpolateShortGaps(
            observations,
            config: session.resolvedTrackingConfig
        )
        let quality = NativeTrackRuntimeDerivation.computeQualityMetadata(observations: interpolated)
        let averageConfidence = interpolated.map(\.confidence).mean()
        return NativeTrackReconstruction(
            trackID: bundle.trackID,
            trackName: bundle.trackName,
            trackKind: bundle.trackKind,
            observations: interpolated,
            quality: quality,
            averageConfidence: averageConfidence
        )
    }

    func deriveTrackQuality(from reconstruction: NativeTrackReconstruction) -> TrackQualitySnapshot {
        reconstruction.quality
    }

    func deriveTrackQuality(for bundle: AnalysisTrackBundle, session: SessionSnapshot) -> TrackQualitySnapshot? {
        reconstructTrack(bundle: bundle, session: session).map(\.quality)
    }

    func rebuildPairwiseMetrics(
        tracks: [NativeTrackReconstruction],
        analysesByTrackID: [String: [AnalysisRow]]
    ) -> [PairwiseMetricSnapshot] {
        let eligibleTracks = tracks
            .filter { $0.trackKind != "reference" && !$0.observations.isEmpty }
            .sorted { $0.trackID < $1.trackID }

        guard eligibleTracks.count >= 2 else { return [] }

        var metrics: [PairwiseMetricSnapshot] = []
        for index in eligibleTracks.indices {
            let primaryTrack = eligibleTracks[index]
            guard index + 1 < eligibleTracks.count else { continue }
            let primaryRowsByFrame = Dictionary(uniqueKeysWithValues: (analysesByTrackID[primaryTrack.trackID] ?? []).map { ($0.frameIndex, $0) })

            for secondaryTrack in eligibleTracks[(index + 1)...] {
                let secondaryRowsByFrame = Dictionary(uniqueKeysWithValues: (analysesByTrackID[secondaryTrack.trackID] ?? []).map { ($0.frameIndex, $0) })
                let commonFrames = Array(Set(primaryTrack.observationByFrame.keys).intersection(secondaryTrack.observationByFrame.keys)).sorted()

                let samples = commonFrames.compactMap { frameIndex -> PairwiseMetricSampleSnapshot? in
                    guard
                        let primaryRow = primaryRowsByFrame[frameIndex],
                        let secondaryRow = secondaryRowsByFrame[frameIndex]
                    else {
                        return nil
                    }

                    let relativeDXUnits = secondaryRow.xUnits - primaryRow.xUnits
                    let relativeDYUnits = secondaryRow.yUnits - primaryRow.yUnits
                    let relativeVX = (secondaryRow.xVelocity ?? 0) - (primaryRow.xVelocity ?? 0)
                    let relativeVY = (secondaryRow.yVelocity ?? 0) - (primaryRow.yVelocity ?? 0)
                    return PairwiseMetricSampleSnapshot(
                        frameIndex: frameIndex,
                        timeSeconds: secondaryRow.timeSeconds,
                        distanceUnits: sqrt((relativeDXUnits * relativeDXUnits) + (relativeDYUnits * relativeDYUnits)),
                        relativeSpeedUnitsPerSecond: sqrt((relativeVX * relativeVX) + (relativeVY * relativeVY)),
                        relativeDXUnits: relativeDXUnits,
                        relativeDYUnits: relativeDYUnits,
                        centerOfMassXUnits: (primaryRow.xUnits + secondaryRow.xUnits) / 2.0,
                        centerOfMassYUnits: (primaryRow.yUnits + secondaryRow.yUnits) / 2.0
                    )
                }

                guard !samples.isEmpty else { continue }
                metrics.append(
                    PairwiseMetricSnapshot(
                        primaryTrackID: primaryTrack.trackID,
                        secondaryTrackID: secondaryTrack.trackID,
                        samples: samples
                    )
                )
            }
        }

        return metrics.sorted { $0.id < $1.id }
    }

    private func seedBox(for bundle: AnalysisTrackBundle, session: SessionSnapshot) -> BBoxSnapshot {
        if bundle.trackID == "primary" {
            return session.initialBbox
        }
        if bundle.trackID == "reference", let reference = session.referenceBbox {
            return reference
        }
        if let object = session.additionalObjects?.first(where: { $0.trackID == bundle.trackID }) {
            return object.bbox
        }
        return session.initialBbox
    }

    private func normalizedState(_ state: String, lost: Bool) -> String {
        let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            return trimmed
        }
        return lost ? "lost" : "tracking"
    }
}

struct NativeResearchBundleExporter {
    private let scientificProcessor = NativeScientificProcessor()

    func exportPairwiseMetrics(_ metrics: [PairwiseMetricSnapshot], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pairwiseURL = directory.appendingPathComponent("pairwise_metrics.csv")
        try buildPairwiseMetricsCSV(metrics).write(to: pairwiseURL, atomically: true, encoding: .utf8)
    }

    func export(_ payload: NativeResearchBundlePayload) throws -> [String: URL] {
        let directory = payload.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let reporter = NativeResearchReporter()
        let quality = reporter.buildQuality(session: payload.session, rows: payload.analysisRows, trackID: payload.trackID)
        let nativeModules = reporter.buildAnalyzers(
            session: payload.session,
            rows: payload.analysisRows,
            trackID: payload.trackID,
            pairwiseMetrics: payload.pairwiseMetrics
        )
        let modules = nativeModules.isEmpty ? payload.modules : nativeModules
        let classification = reporter.buildClassification(
            session: payload.session,
            rows: payload.analysisRows,
            modules: modules,
            trackID: payload.trackID
        )
        let derivedEvents = reporter.buildDerivedEvents(
            session: payload.session,
            rows: payload.analysisRows,
            classification: classification
        )
        let mergedEvents = reporter.mergeEventMarkers(payload.eventMarkers, withDerived: derivedEvents)
        let summary = reporter.buildSummary(
            session: payload.session,
            rows: payload.analysisRows,
            quality: quality,
            eventCount: mergedEvents.count,
            trackID: payload.trackID,
            classification: classification
        )
        let reproduceCommand = buildReproduceCommand(
            session: payload.session,
            trackingProfile: payload.trackingProfile,
            includeOverlay: payload.includeOverlay,
            includePlots: payload.includePlots,
            debugTracking: payload.debugTracking
        )
        let reportMarkdown = reporter.buildReport(
            session: payload.session,
            rows: payload.analysisRows,
            trackID: payload.trackID,
            trackName: payload.trackName,
            summary: summary,
            quality: quality,
            classification: classification,
            modules: modules,
            pairwiseMetrics: payload.pairwiseMetrics,
            eventMarkers: mergedEvents,
            reproduceCommand: reproduceCommand
        )

        let sessionWithNativeScience = reporter.sessionByUpdatingDerivedArtifacts(
            payload.session,
            derivedEvents: mergedEvents,
            trackQuality: reporter.resolvedTrackQuality(session: payload.session, rows: payload.analysisRows, trackID: payload.trackID)
        )
        let sessionURL = directory.appendingPathComponent("session.json")
        let manifestURL = directory.appendingPathComponent("experiment_manifest.json")
        let eventsURL = directory.appendingPathComponent("events.csv")
        let derivedEventsURL = directory.appendingPathComponent("derived_events.json")
        let classificationURL = directory.appendingPathComponent("classification.json")
        let summaryURL = directory.appendingPathComponent("summary.json")
        let qualityURL = directory.appendingPathComponent("quality_report.json")
        let modulesURL = directory.appendingPathComponent("analysis_modules.json")
        let windowURL = directory.appendingPathComponent("selected_window_summary.json")
        let analysisURL = directory.appendingPathComponent("analysis.csv")
        let pairwiseURL = directory.appendingPathComponent("pairwise_metrics.csv")
        let reportURL = directory.appendingPathComponent("report.md")
        let reproduceURL = directory.appendingPathComponent("reproduce_command.sh")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        try encoder.encode(sessionWithNativeScience).write(to: sessionURL)
        try encoder.encode(mergedEvents).write(to: derivedEventsURL)
        try encoder.encode(classification).write(to: classificationURL)
        try encoder.encode(summary).write(to: summaryURL)
        try encoder.encode(quality).write(to: qualityURL)
        try encoder.encode(modules).write(to: modulesURL)
        try buildEventsCSV(mergedEvents).write(to: eventsURL, atomically: true, encoding: .utf8)
        try buildAnalysisSnapshotCSV(payload.analysisRows).write(to: analysisURL, atomically: true, encoding: .utf8)
        try buildPairwiseMetricsCSV(payload.pairwiseMetrics).write(to: pairwiseURL, atomically: true, encoding: .utf8)
        try reportMarkdown.write(to: reportURL, atomically: true, encoding: .utf8)
        try (reproduceCommand + "\n").write(to: reproduceURL, atomically: true, encoding: .utf8)

        if let window = scientificProcessor.summarizeWindow(
            rows: payload.analysisRows,
            startFrame: payload.session.reviewState?.selectedWindowStart ?? payload.session.selectedStartFrame,
            endFrame: payload.session.reviewState?.selectedWindowEnd ?? payload.session.selectedEndFrame
        ) {
            try encoder.encode(window).write(to: windowURL)
        }

        let manifest = NativeExperimentManifest(
            sessionVersion: 3,
            videoPath: payload.session.videoPath,
            trackID: payload.trackID,
            trackName: payload.trackName,
            trackingProfile: payload.trackingProfile.rawValue,
            referenceLength: payload.session.calibration.referenceLength,
            unitLabel: payload.session.calibration.unitLabel,
            selectedStartFrame: payload.session.selectedStartFrame,
            selectedEndFrame: payload.session.selectedEndFrame,
            additionalObjects: (payload.session.additionalObjects ?? []).map(\.name),
            eventCount: mergedEvents.count,
            reportTemplate: payload.reportTemplate,
            reproduceCommand: reproduceCommand
        )
        try encoder.encode(manifest).write(to: manifestURL)

        return [
            "session": sessionURL,
            "manifest": manifestURL,
            "events": eventsURL,
            "derived_events": derivedEventsURL,
            "classification": classificationURL,
            "analysis": analysisURL,
            "summary": summaryURL,
            "quality": qualityURL,
            "modules": modulesURL,
            "pairwise": pairwiseURL,
            "report": reportURL,
            "reproduce": reproduceURL,
            "window_summary": windowURL,
        ]
    }

    func buildBatchTrialReport(
        trialID: String,
        videoPath: String,
        rows: [AnalysisRow],
        session: SessionSnapshot,
        trackID: String,
        trackName: String,
        summary: SummarySnapshot?,
        quality: QualitySnapshot?,
        modules: [AnalyzerSnapshot],
        pairwiseMetrics: [PairwiseMetricSnapshot]
    ) -> NativeBatchTrialSnapshot {
        let reporter = NativeResearchReporter()
        let resolvedQuality = reporter.buildQuality(session: session, rows: rows, trackID: trackID)
        let resolvedModules = reporter.buildAnalyzers(
            session: session,
            rows: rows,
            trackID: trackID,
            pairwiseMetrics: pairwiseMetrics
        )
        let classification = reporter.buildClassification(
            session: session,
            rows: rows,
            modules: resolvedModules.isEmpty ? modules : resolvedModules,
            trackID: trackID
        )
        let derivedEvents = reporter.buildDerivedEvents(
            session: session,
            rows: rows,
            classification: classification
        )
        let resolvedSummary = reporter.buildSummary(
            session: session,
            rows: rows,
            quality: resolvedQuality,
            eventCount: derivedEvents.count + (session.eventMarkers ?? []).filter { ($0.origin ?? "derived") == "manual" }.count,
            trackID: trackID,
            classification: classification
        )
        return NativeBatchTrialSnapshot(
            trialID: trialID,
            videoPath: videoPath,
            qcBadge: resolvedQuality.qcBadge ?? "review_needed",
            peakSpeed: resolvedSummary.peakSpeed ?? 0,
            peakAcceleration: resolvedSummary.peakAcceleration ?? 0,
            scientificConfidenceMean: resolvedQuality.scientificConfidenceMean ?? resolvedSummary.scientificConfidenceMean ?? 0,
            analyzerCount: (resolvedModules.isEmpty ? modules : resolvedModules).count,
            qualityIndex: resolvedQuality.qualityIndex ?? 0,
            eventCount: derivedEvents.count,
            classificationID: classification.classificationID,
            classificationTitle: classification.title,
            classificationConfidence: classification.confidence
        )
    }

    func buildBatchAggregateReport(_ trials: [NativeBatchTrialSnapshot]) -> NativeBatchAggregateSnapshot {
        guard !trials.isEmpty else {
            return NativeBatchAggregateSnapshot(
                trialCount: 0,
                meanPeakSpeed: 0,
                meanPeakAcceleration: 0,
                meanScientificConfidence: 0,
                meanQualityIndex: 0,
                meanEventCount: 0,
                qcBadges: [:],
                classifications: [:],
                highestPeakSpeedTrialID: nil,
                highestPeakAccelerationTrialID: nil,
                bestQualityTrialID: nil,
                trials: []
            )
        }

        var badgeCounts: [String: Int] = [:]
        var classificationCounts: [String: Int] = [:]
        for trial in trials {
            badgeCounts[trial.qcBadge, default: 0] += 1
            classificationCounts[trial.classificationTitle, default: 0] += 1
        }

        return NativeBatchAggregateSnapshot(
            trialCount: trials.count,
            meanPeakSpeed: trials.map(\.peakSpeed).mean(),
            meanPeakAcceleration: trials.map(\.peakAcceleration).mean(),
            meanScientificConfidence: trials.map(\.scientificConfidenceMean).mean(),
            meanQualityIndex: trials.map(\.qualityIndex).mean(),
            meanEventCount: trials.map { Double($0.eventCount) }.mean(),
            qcBadges: badgeCounts,
            classifications: classificationCounts,
            highestPeakSpeedTrialID: trials.max(by: { $0.peakSpeed < $1.peakSpeed })?.trialID,
            highestPeakAccelerationTrialID: trials.max(by: { $0.peakAcceleration < $1.peakAcceleration })?.trialID,
            bestQualityTrialID: trials.max(by: { $0.qualityIndex < $1.qualityIndex })?.trialID,
            trials: trials
        )
    }

    func exportBatchAggregateReport(_ report: NativeBatchAggregateSnapshot, to outputURL: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        try encoder.encode(report).write(to: outputURL)
        let comparison = buildBatchComparisonSnapshot(report)
        let comparisonURL = outputURL.deletingLastPathComponent().appendingPathComponent("batch_comparison.json")
        try encoder.encode(comparison).write(to: comparisonURL)
        let markdownURL = outputURL.deletingLastPathComponent().appendingPathComponent("batch_report.md")
        try buildBatchComparisonMarkdown(report, comparison: comparison).write(to: markdownURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func buildBatchComparisonSnapshot(_ report: NativeBatchAggregateSnapshot) -> NativeBatchComparisonSnapshot {
        let speedRanking = report.trials.sorted { $0.peakSpeed > $1.peakSpeed }.prefix(5).map(\.trialID)
        let accelerationRanking = report.trials.sorted { $0.peakAcceleration > $1.peakAcceleration }.prefix(5).map(\.trialID)
        let qualityRanking = report.trials.sorted { $0.qualityIndex > $1.qualityIndex }.prefix(5).map(\.trialID)
        return NativeBatchComparisonSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            trialCount: report.trialCount,
            classifications: report.classifications,
            qcBadges: report.qcBadges,
            rankings: [
                "peak_speed": speedRanking,
                "peak_acceleration": accelerationRanking,
                "quality_index": qualityRanking,
            ]
        )
    }

    private func buildBatchComparisonMarkdown(_ report: NativeBatchAggregateSnapshot, comparison: NativeBatchComparisonSnapshot) -> String {
        """
        # Tracker AI Batch Comparison

        - Trials: `\(report.trialCount)`
        - Mean peak speed: `\(String(format: "%.4f", report.meanPeakSpeed))`
        - Mean peak acceleration: `\(String(format: "%.4f", report.meanPeakAcceleration))`
        - Mean scientific confidence: `\(String(format: "%.4f", report.meanScientificConfidence))`
        - Mean quality index: `\(String(format: "%.4f", report.meanQualityIndex))`
        - Mean event count: `\(String(format: "%.2f", report.meanEventCount))`
        - Highest peak-speed trial: `\(report.highestPeakSpeedTrialID ?? "n/a")`
        - Highest peak-acceleration trial: `\(report.highestPeakAccelerationTrialID ?? "n/a")`
        - Best-quality trial: `\(report.bestQualityTrialID ?? "n/a")`

        ## Classification Distribution

        \(report.classifications.isEmpty ? "- No classifications available." : report.classifications.map { "- \($0.key): \($0.value)" }.sorted().joined(separator: "\n"))

        ## QC Badge Distribution

        \(report.qcBadges.isEmpty ? "- No QC badges available." : report.qcBadges.map { "- \($0.key): \($0.value)" }.sorted().joined(separator: "\n"))

        ## Rankings

        - Peak speed: `\(comparison.rankings["peak_speed"]?.joined(separator: ", ") ?? "n/a")`
        - Peak acceleration: `\(comparison.rankings["peak_acceleration"]?.joined(separator: ", ") ?? "n/a")`
        - Quality index: `\(comparison.rankings["quality_index"]?.joined(separator: ", ") ?? "n/a")`
        """
    }

    private func summarizeWindow(rows: [AnalysisRow], startFrame: Int?, endFrame: Int?) -> NativeWindowSummary? {
        scientificProcessor.summarizeWindow(rows: rows, startFrame: startFrame, endFrame: endFrame)
    }

    private func buildReproduceCommand(
        session: SessionSnapshot,
        trackingProfile: TrackingProfileOption,
        includeOverlay: Bool,
        includePlots: Bool,
        debugTracking: Bool
    ) -> String {
        let points = (session.scalePoints ?? [0, 0, session.calibration.pixelDistance, 0])
            .map { String(format: "%g", $0) }
            .joined(separator: " ")
        let bbox = session.initialBbox
        var command = [
            "tracker-ai",
            "analyze",
            "--video \"\(session.videoPath)\"",
            "--bbox \(format(bbox.x)) \(format(bbox.y)) \(format(bbox.width)) \(format(bbox.height))",
            "--scale-points \(points)",
            "--reference-length \(format(session.calibration.referenceLength))",
            "--unit \(session.calibration.unitLabel)",
            "--start-frame \(session.selectedStartFrame ?? 0)",
            "--window \(session.analysisConfig.smoothingWindow)",
            "--polyorder \(session.analysisConfig.smoothingPolyorder)",
            "--tracking-profile \(trackingProfile.rawValue)",
            "--report-template \(session.exportPreferences?.reportTemplate ?? "research")",
        ]

        if let end = session.selectedEndFrame {
            command.append("--end-frame \(end)")
        }
        if let referenceBox = session.referenceBbox {
            command.append("--reference-bbox \(format(referenceBox.x)) \(format(referenceBox.y)) \(format(referenceBox.width)) \(format(referenceBox.height))")
        }
        if !includeOverlay {
            command.append("--skip-overlay")
        }
        if !includePlots {
            command.append("--skip-plots")
        }
        if debugTracking {
            command.append("--debug-tracking")
        }
        if let metadata = session.metadata {
            if let label = metadata.experimentLabel, !label.isEmpty {
                command.append("--experiment-label \"\(escapeShell(label))\"")
            }
            if let trialID = metadata.trialID, !trialID.isEmpty {
                command.append("--trial-id \"\(escapeShell(trialID))\"")
            }
            if let operatorName = metadata.operatorName, !operatorName.isEmpty {
                command.append("--operator \"\(escapeShell(operatorName))\"")
            }
            if let notes = metadata.notes, !notes.isEmpty {
                command.append("--notes \"\(escapeShell(notes))\"")
            }
            if let tags = metadata.tags, !tags.isEmpty {
                command.append("--tags " + tags.map { "\"\(escapeShell($0))\"" }.joined(separator: " "))
            }
        }
        for object in session.additionalObjects ?? [] {
            command.append(
                "--extra-object \(object.trackID) \"\(escapeShell(object.name))\" \(format(object.bbox.x)) \(format(object.bbox.y)) \(format(object.bbox.width)) \(format(object.bbox.height))"
            )
        }
        command.append("--output-dir <output-dir>")
        return command.joined(separator: " \\\n  ")
    }

    private func buildEventsCSV(_ events: [EventMarkerRecord]) -> String {
        var lines = ["name,frame_index,time_s,value,unit_label,axis,note,origin"]
        lines.append(contentsOf: events.map {
            [
                csv($0.name),
                String($0.frameIndex),
                format($0.timeSeconds),
                format($0.value),
                csv($0.unitLabel),
                csv($0.axis),
                csv($0.note),
                csv($0.origin),
            ].joined(separator: ",")
        })
        return lines.joined(separator: "\n") + "\n"
    }

    private func buildAnalysisSnapshotCSV(_ rows: [AnalysisRow]) -> String {
        let header = [
            "frame_index", "time_s", "x_px", "y_px", "raw_x_units", "raw_y_units",
            "x_units", "y_units", "vx", "vy", "ax", "ay", "speed",
            "acceleration_magnitude", "angle_deg", "confidence", "scientific_confidence",
            "position_uncertainty", "velocity_uncertainty", "acceleration_uncertainty",
            "lost", "corrected", "state", "failure_reason",
        ]
        var lines = [header.joined(separator: ",")]
        lines.append(contentsOf: rows.map { row in
            [
                String(row.frameIndex),
                format(row.timeSeconds),
                formatOptional(row.xPixels),
                formatOptional(row.yPixels),
                formatOptional(row.rawXUnits),
                formatOptional(row.rawYUnits),
                format(row.xUnits),
                format(row.yUnits),
                formatOptional(row.xVelocity),
                formatOptional(row.yVelocity),
                formatOptional(row.xAcceleration),
                formatOptional(row.yAcceleration),
                format(row.speed),
                format(row.accelerationMagnitude),
                formatOptional(row.angleDegrees),
                format(row.trackerConfidence),
                format(row.scientificConfidence),
                formatOptional(row.positionUncertainty),
                formatOptional(row.velocityUncertainty),
                formatOptional(row.accelerationUncertainty),
                row.lost ? "true" : "false",
                row.corrected ? "true" : "false",
                csv(row.state),
                csv(row.failureReason),
            ].joined(separator: ",")
        })
        return lines.joined(separator: "\n") + "\n"
    }

    private func buildPairwiseMetricsCSV(_ metrics: [PairwiseMetricSnapshot]) -> String {
        let header = [
            "primary_track_id", "secondary_track_id", "frame_index", "time_s",
            "distance_units", "relative_speed_units_s", "relative_dx_units", "relative_dy_units",
            "center_of_mass_x_units", "center_of_mass_y_units",
        ]
        var lines = [header.joined(separator: ",")]
        for metric in metrics.sorted(by: { $0.id < $1.id }) {
            lines.append(contentsOf: metric.samples.sorted(by: { $0.frameIndex < $1.frameIndex }).map { sample in
                [
                    csv(metric.primaryTrackID),
                    csv(metric.secondaryTrackID),
                    String(sample.frameIndex),
                    format(sample.timeSeconds),
                    format(sample.distanceUnits),
                    format(sample.relativeSpeedUnitsPerSecond),
                    format(sample.relativeDXUnits),
                    format(sample.relativeDYUnits),
                    formatOptional(sample.centerOfMassXUnits),
                    formatOptional(sample.centerOfMassYUnits),
                ].joined(separator: ",")
            })
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func csv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func format(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private func formatOptional(_ value: Double?) -> String {
        guard let value else { return "" }
        return format(value)
    }

    private func escapeShell(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct NativeResearchReporter {
    private let scientificProcessor = NativeScientificProcessor()

    func rebuildPairwiseMetrics(trackBundles: [AnalysisTrackBundle]) -> [PairwiseMetricSnapshot] {
        let eligibleBundles = trackBundles
            .filter { $0.trackKind != "reference" && !$0.analysisRows.isEmpty }
            .sorted { $0.trackID < $1.trackID }

        guard eligibleBundles.count >= 2 else { return [] }

        var metrics: [PairwiseMetricSnapshot] = []
        for index in eligibleBundles.indices {
            let primaryBundle = eligibleBundles[index]
            let primaryRows = Dictionary(uniqueKeysWithValues: primaryBundle.analysisRows.map { ($0.frameIndex, $0) })
            guard index + 1 < eligibleBundles.count else { continue }
            for secondaryBundle in eligibleBundles[(index + 1)...] {
                let samples = secondaryBundle.analysisRows.compactMap { secondaryRow -> PairwiseMetricSampleSnapshot? in
                    guard let primaryRow = primaryRows[secondaryRow.frameIndex] else { return nil }
                    let relativeDXUnits = secondaryRow.xUnits - primaryRow.xUnits
                    let relativeDYUnits = secondaryRow.yUnits - primaryRow.yUnits
                    let relativeVX = (secondaryRow.xVelocity ?? 0) - (primaryRow.xVelocity ?? 0)
                    let relativeVY = (secondaryRow.yVelocity ?? 0) - (primaryRow.yVelocity ?? 0)
                    return PairwiseMetricSampleSnapshot(
                        frameIndex: secondaryRow.frameIndex,
                        timeSeconds: secondaryRow.timeSeconds,
                        distanceUnits: sqrt((relativeDXUnits * relativeDXUnits) + (relativeDYUnits * relativeDYUnits)),
                        relativeSpeedUnitsPerSecond: sqrt((relativeVX * relativeVX) + (relativeVY * relativeVY)),
                        relativeDXUnits: relativeDXUnits,
                        relativeDYUnits: relativeDYUnits,
                        centerOfMassXUnits: (primaryRow.xUnits + secondaryRow.xUnits) / 2.0,
                        centerOfMassYUnits: (primaryRow.yUnits + secondaryRow.yUnits) / 2.0
                    )
                }
                guard !samples.isEmpty else { continue }
                metrics.append(
                    PairwiseMetricSnapshot(
                        primaryTrackID: primaryBundle.trackID,
                        secondaryTrackID: secondaryBundle.trackID,
                        samples: samples.sorted { $0.frameIndex < $1.frameIndex }
                    )
                )
            }
        }

        return metrics.sorted { $0.id < $1.id }
    }

    func buildSummary(
        session: SessionSnapshot,
        rows: [AnalysisRow],
        quality: QualitySnapshot,
        eventCount: Int,
        trackID: String,
        classification: ExperimentClassificationSnapshot
    ) -> SummarySnapshot {
        let frameCount = rows.count
        let startFrame = session.selectedStartFrame ?? rows.first?.frameIndex
        let endFrame = session.selectedEndFrame ?? rows.last?.frameIndex
        let xValues = rows.map(\.xUnits)
        let yValues = rows.map(\.yUnits)
        let speedValues = rows.map(\.speed)
        let accelerationValues = rows.map(\.accelerationMagnitude)
        let duration = rows.count > 1 ? max((rows.last?.timeSeconds ?? 0) - (rows.first?.timeSeconds ?? 0), 0) : 0
        var pathLength = 0.0
        if rows.count > 1 {
            for index in 1..<rows.count {
                let previous = rows[index - 1]
                let current = rows[index]
                let dx = current.xUnits - previous.xUnits
                let dy = current.yUnits - previous.yUnits
                pathLength += sqrt((dx * dx) + (dy * dy))
            }
        }

        let netDisplacement: Double = {
            guard let first = rows.first, let last = rows.last else { return 0 }
            let dx = last.xUnits - first.xUnits
            let dy = last.yUnits - first.yUnits
            return sqrt((dx * dx) + (dy * dy))
        }()

        let lostFrameCount = rows.filter(\.lost).count
        let correctedFrameCount = rows.filter(\.corrected).count
        let trackQuality = resolvedTrackQuality(session: session, rows: rows, trackID: trackID)
        let suspectSpanCount = trackQuality.suspectSpans?.count ?? 0

        return SummarySnapshot(
            frameCount: frameCount,
            durationSeconds: duration,
            startFrame: startFrame,
            endFrame: endFrame,
            averageConfidence: rows.map(\.trackerConfidence).mean(),
            lowConfidenceFrameCount: rows.filter { $0.trackerConfidence < 0.35 }.count,
            suspectSpanCount: suspectSpanCount,
            xRangeUnits: xValues.rangeSpan(),
            yRangeUnits: yValues.rangeSpan(),
            peakSpeed: speedValues.max(),
            meanSpeed: speedValues.mean(),
            peakAcceleration: accelerationValues.max(),
            meanAcceleration: accelerationValues.mean(),
            totalPathLength: pathLength,
            netDisplacement: netDisplacement,
            scientificConfidenceMean: quality.scientificConfidenceMean,
            qcBadge: quality.qcBadge,
            eventCount: eventCount,
            unitLabel: session.calibration.unitLabel,
            reacquisitionCount: trackQuality.reacquisitionCount,
            lostFrameCount: lostFrameCount,
            correctedFrameCount: correctedFrameCount,
            reviewRecommended: quality.reviewRecommended ?? trackQuality.reviewRecommended,
            peakPositionUncertainty: quality.peakPositionUncertainty,
            peakVelocityUncertainty: quality.peakVelocityUncertainty,
            classification: classification
        )
    }

    func buildQuality(session: SessionSnapshot, rows: [AnalysisRow], trackID: String) -> QualitySnapshot {
        let trackerMean = rows.map(\.trackerConfidence).mean()
        let scientificMean = rows.map(\.scientificConfidence).mean()
        let lostCount = rows.filter(\.lost).count
        let correctedCount = rows.filter(\.corrected).count
        let lowConfidenceCount = rows.filter { $0.trackerConfidence < 0.35 }.count
        let rowCount = max(rows.count, 1)
        let peakPositionUncertainty = rows.compactMap(\.positionUncertainty).max() ?? 0
        let peakVelocityUncertainty = rows.compactMap(\.velocityUncertainty).max() ?? 0
        let referenceLength = max(session.calibration.referenceLength, 1e-6)
        let trackQuality = resolvedTrackQuality(session: session, rows: rows, trackID: trackID)
        let spanScores = buildSpanScores(session: session, rows: rows, trackQuality: trackQuality)
        let anomalies = buildAnomalies(session: session, rows: rows, spanScores: spanScores)
        let qualityIndex = buildQualityIndex(
            rowCount: rowCount,
            lowConfidenceCount: lowConfidenceCount,
            lostCount: lostCount,
            correctedCount: correctedCount,
            spanScores: spanScores,
            anomalies: anomalies
        )
        let calibrationConfidence: Double

        switch session.calibration.mode ?? "single_line" {
        case "marker_size":
            calibrationConfidence = 0.82
        case "two_axis":
            calibrationConfidence = 0.90
        case "homography":
            calibrationConfidence = 0.94
        default:
            calibrationConfidence = 0.82
        }

        let qcBadge = qcBadge(
            rows: rows,
            scientificConfidenceMean: scientificMean,
            peakPositionUncertainty: peakPositionUncertainty,
            referenceLength: referenceLength,
            qualityIndex: qualityIndex,
            anomalies: anomalies
        )

        var notes: [String] = []
        if lostCount > 0 {
            notes.append("Lost frames detected; review reacquisition spans before publication use.")
        }
        if correctedCount > 0 || !(session.corrections ?? []).isEmpty {
            notes.append("Manual corrections were applied; keep the session file with the exported run.")
        }
        if let eventCount = session.eventMarkers?.count, eventCount > 0 {
            notes.append("\(eventCount) event markers are attached to this session and should travel with exports.")
        }
        if lowConfidenceCount > 0 {
            notes.append("Low-confidence frames were detected; verify the selected window before publication reporting.")
        }
        let elevatedCount = anomalies.filter { $0.score >= 0.65 }.count
        if elevatedCount > 0 {
            notes.append("Native QC flagged \(elevatedCount) elevated anomaly \(elevatedCount == 1 ? "cluster" : "clusters"); inspect the anomaly register before publication use.")
        }
        if let dominantSpan = spanScores.sorted(by: { $0.severityScore > $1.severityScore }).first, dominantSpan.severityScore >= 0.60 {
            notes.append("The highest-severity review span is \(dominantSpan.category) across frames \(dominantSpan.startFrame)-\(dominantSpan.endFrame).")
        }
        if notes.isEmpty {
            notes.append("No major QC warnings were detected.")
        }

        let reviewRecommended = trackQuality.reviewRecommended ?? (qcBadge != "good_for_publication" || lowConfidenceCount > 0 || !anomalies.isEmpty)

        return QualitySnapshot(
            qcBadge: qcBadge,
            trackerConfidenceMean: trackerMean,
            scientificConfidenceMean: scientificMean,
            calibrationConfidence: calibrationConfidence,
            driftSensitivity: peakPositionUncertainty / referenceLength,
            lowConfidenceFrames: lowConfidenceCount,
            lostFrameCount: lostCount,
            correctedFrameCount: correctedCount,
            interpolatedBurdenRatio: Double(lostCount + correctedCount) / Double(rowCount),
            peakPositionUncertainty: peakPositionUncertainty,
            peakVelocityUncertainty: peakVelocityUncertainty,
            reviewRecommended: reviewRecommended,
            notes: notes,
            qualityIndex: qualityIndex,
            anomalies: anomalies,
            spanScores: spanScores
        )
    }

    func buildAnalyzers(
        session: SessionSnapshot,
        rows: [AnalysisRow],
        trackID: String,
        pairwiseMetrics: [PairwiseMetricSnapshot] = []
    ) -> [AnalyzerSnapshot] {
        guard rows.count >= 3 else { return [] }

        let times = rows.map(\.timeSeconds)
        let x = rows.map(\.xUnits)
        let y = rows.map(\.yUnits)
        let vx = velocityComponent(rows: rows, keyPath: \.xVelocity, source: x, times: times)
        let vy = velocityComponent(rows: rows, keyPath: \.yVelocity, source: y, times: times)
        let ax = velocityComponent(rows: rows, keyPath: \.xAcceleration, source: vx, times: times)
        let ay = velocityComponent(rows: rows, keyPath: \.yAcceleration, source: vy, times: times)
        let angle = rows.map { row in
            row.angleDegrees ?? atan2(row.yUnits - y.mean(), row.xUnits - x.mean()) * 180 / .pi
        }
        let unitLabel = session.calibration.unitLabel
        var results: [AnalyzerSnapshot] = []

        if rows.count >= 5, y.rangeSpan() > session.calibration.referenceLength * 0.1, let quadratic = quadraticFit(x: times, y: y) {
            let launchIndex = firstReliableIndex(rows: rows)
            let launchAngle = atan2(vy[safe: launchIndex] ?? 0, (vx[safe: launchIndex] ?? 0) + 1e-9) * 180 / .pi
            results.append(
                AnalyzerSnapshot(
                    analyzerID: "projectile",
                    title: "Projectile Motion",
                    confidence: rows.map(\.scientificConfidence).mean(),
                    metrics: [
                        AnalyzerMetricSnapshot(key: "launch_angle_deg", value: launchAngle, unitLabel: "deg", note: nil),
                        AnalyzerMetricSnapshot(key: "gravity_fit", value: 2 * quadratic.a, unitLabel: "\(unitLabel)/s^2", note: nil),
                        AnalyzerMetricSnapshot(key: "flight_time", value: max((times.last ?? 0) - (times.first ?? 0), 0), unitLabel: "s", note: nil),
                    ],
                    notes: ["Estimated from a quadratic fit of vertical displacement over time."]
                )
            )
        }

        let centeredX = x.map { abs($0 - x.mean()) }
        let pendulumPeaks = peakIndices(centeredX)
        if pendulumPeaks.count >= 2 {
            let periods = zip(pendulumPeaks, pendulumPeaks.dropFirst()).map { times[$1] - times[$0] }.map { $0 * 2 }
            let amplitudes = pendulumPeaks.map { centeredX[$0] }
            let damping = log(max(amplitudes.first ?? 1e-9, 1e-9) / max(amplitudes.last ?? 1e-9, 1e-9)) / Double(max(amplitudes.count - 1, 1))
            results.append(
                AnalyzerSnapshot(
                    analyzerID: "pendulum",
                    title: "Pendulum Motion",
                    confidence: rows.map(\.scientificConfidence).mean(),
                    metrics: [
                        AnalyzerMetricSnapshot(key: "period", value: periods.mean(), unitLabel: "s", note: nil),
                        AnalyzerMetricSnapshot(key: "damping_ratio", value: max(damping, 0), unitLabel: "", note: nil),
                        AnalyzerMetricSnapshot(key: "peak_angle", value: angle.map(abs).max() ?? 0, unitLabel: "deg", note: nil),
                    ],
                    notes: ["Detected from repeated lateral turning points in the track."]
                )
            )
        }

        let centerX = x.mean()
        let centerY = y.mean()
        let radius = zip(x, y).map { sqrt(pow($0 - centerX, 2) + pow($1 - centerY, 2)) }
        let meanRadius = radius.mean()
        let circularity = meanRadius > 1e-6 ? 1 - min(radius.standardDeviation() / meanRadius, 1) : 0
        if circularity >= 0.55 {
            let unwrappedAngles = unwrap(angle.map { $0 * .pi / 180 })
            let angularVelocity = finiteDifferences(values: unwrappedAngles, times: times).map(abs)
            results.append(
                AnalyzerSnapshot(
                    analyzerID: "circular",
                    title: "Circular Motion",
                    confidence: min(rows.map(\.scientificConfidence).mean(), circularity),
                    metrics: [
                        AnalyzerMetricSnapshot(key: "mean_radius", value: meanRadius, unitLabel: unitLabel, note: nil),
                        AnalyzerMetricSnapshot(key: "angular_velocity", value: angularVelocity.mean(), unitLabel: "rad/s", note: nil),
                        AnalyzerMetricSnapshot(key: "circularity", value: circularity, unitLabel: "", note: nil),
                    ],
                    notes: ["Center estimated from the mean track position."]
                )
            )
        }

        if let line = linearFit(x: x, y: y), x.rangeSpan() > 1e-6 {
            let residuals = zip(x, y).map { $1 - (line.slope * $0 + line.intercept) }
            if residuals.standardDeviation() <= max(session.calibration.referenceLength * 0.15, 1e-6) {
                let trackAngle = atan(line.slope) * 180 / .pi
                let alongTrackAcceleration = zip(ax, ay).map {
                    cos(trackAngle * .pi / 180) * $0 + sin(trackAngle * .pi / 180) * $1
                }.mean()
                results.append(
                    AnalyzerSnapshot(
                        analyzerID: "incline",
                        title: "Incline Motion",
                        confidence: rows.map(\.scientificConfidence).mean(),
                        metrics: [
                            AnalyzerMetricSnapshot(key: "track_angle_deg", value: trackAngle, unitLabel: "deg", note: nil),
                            AnalyzerMetricSnapshot(key: "along_track_acceleration", value: alongTrackAcceleration, unitLabel: "\(unitLabel)/s^2", note: nil),
                            AnalyzerMetricSnapshot(key: "line_residual_std", value: residuals.standardDeviation(), unitLabel: unitLabel, note: nil),
                        ],
                        notes: ["Estimated from a line fit through the smoothed path."]
                    )
                )
            }
        }

        let dominant = x.rangeSpan() >= y.rangeSpan() ? x : y
        let springPeaks = peakIndices(dominant.map { abs($0 - dominant.mean()) })
        if springPeaks.count >= 3 {
            let periods = zip(springPeaks, springPeaks.dropFirst()).map { times[$1] - times[$0] }.map { $0 * 2 }
            let amplitudes = springPeaks.map { abs(dominant[$0] - dominant.mean()) }
            let damping = log(max(amplitudes.first ?? 1e-9, 1e-9) / max(amplitudes.last ?? 1e-9, 1e-9)) / Double(max(amplitudes.count - 1, 1))
            let period = periods.mean()
            results.append(
                AnalyzerSnapshot(
                    analyzerID: "spring",
                    title: "Spring Oscillation",
                    confidence: rows.map(\.scientificConfidence).mean(),
                    metrics: [
                        AnalyzerMetricSnapshot(key: "period", value: period, unitLabel: "s", note: nil),
                        AnalyzerMetricSnapshot(key: "frequency", value: period > 0 ? 1 / period : 0, unitLabel: "Hz", note: nil),
                        AnalyzerMetricSnapshot(key: "damping_ratio", value: max(damping, 0), unitLabel: "", note: nil),
                    ],
                    notes: ["Dominant oscillation axis selected automatically from the larger path span."]
                )
            )
        }

        let relevantPairwiseMetrics = pairwiseMetrics.filter {
            $0.primaryTrackID == trackID || $0.secondaryTrackID == trackID
        }
        for metric in relevantPairwiseMetrics {
            guard let collisionFrame = metric.collisionFrame else { continue }
            let collisionIndex = metric.samples.firstIndex(where: { $0.frameIndex == collisionFrame }) ?? 0
            let preWindow = Array(metric.samples[max(0, collisionIndex - 2)..<max(collisionIndex, 1)])
            let postStart = min(metric.samples.count, collisionIndex + 1)
            let postEnd = min(metric.samples.count, collisionIndex + 3)
            let postWindow = postStart < postEnd ? Array(metric.samples[postStart..<postEnd]) : []
            let preSpeed = preWindow.map(\.relativeSpeedUnitsPerSecond).mean()
            let postSpeed = postWindow.map(\.relativeSpeedUnitsPerSecond).mean()
            let restitution = postSpeed / max(preSpeed, 1e-9)
            let otherTrackID = metric.primaryTrackID == trackID ? metric.secondaryTrackID : metric.primaryTrackID
            results.append(
                AnalyzerSnapshot(
                    analyzerID: "collision",
                    title: "Collision Pair: \(trackID) vs \(otherTrackID)",
                    confidence: rows.map(\.scientificConfidence).mean(),
                    metrics: [
                        AnalyzerMetricSnapshot(key: "minimum_separation", value: metric.minimumSeparation, unitLabel: unitLabel, note: nil),
                        AnalyzerMetricSnapshot(key: "peak_relative_speed", value: metric.peakRelativeSpeed, unitLabel: "\(unitLabel)/s", note: nil),
                        AnalyzerMetricSnapshot(key: "coefficient_of_restitution", value: restitution, unitLabel: "", note: nil),
                    ],
                    notes: ["Collision frame detected at \(collisionFrame)."]
                )
            )
        }

        return results
    }

    func buildClassification(
        session: SessionSnapshot,
        rows: [AnalysisRow],
        modules: [AnalyzerSnapshot],
        trackID: String
    ) -> ExperimentClassificationSnapshot {
        if let strongest = modules.max(by: { $0.confidence < $1.confidence }) {
            let summary = strongest.notes?.first
                ?? "Native classification selected \(strongest.title.lowercased()) as the best explanation for this track."
            return ExperimentClassificationSnapshot(
                classificationID: strongest.analyzerID,
                title: strongest.title,
                confidence: strongest.confidence,
                summary: summary,
                supportingAnalyzerIDs: modules.map(\.analyzerID)
            )
        }

        let pathSpan = max(rows.map(\.xUnits).rangeSpan(), rows.map(\.yUnits).rangeSpan())
        let motionTitle = pathSpan > session.calibration.referenceLength * 0.2 ? "General Motion Study" : "Static / Calibration Hold"
        return ExperimentClassificationSnapshot(
            classificationID: pathSpan > session.calibration.referenceLength * 0.2 ? "general_motion" : "static_hold",
            title: motionTitle,
            confidence: rows.map(\.scientificConfidence).mean(),
            summary: "No specialized native analyzer dominated this track, so the classification falls back to a general motion assessment.",
            supportingAnalyzerIDs: modules.map(\.analyzerID)
        )
    }

    func buildDerivedEvents(
        session: SessionSnapshot,
        rows: [AnalysisRow],
        classification: ExperimentClassificationSnapshot
    ) -> [EventMarkerRecord] {
        _ = classification
        return scientificProcessor.buildDerivedEvents(rows: rows, unitLabel: session.calibration.unitLabel)
    }

    func mergeEventMarkers(_ eventMarkers: [EventMarkerRecord], withDerived derivedEvents: [EventMarkerRecord]) -> [EventMarkerRecord] {
        let manual = eventMarkers.filter { $0.origin == "manual" }
        return deduplicateEvents(manual + derivedEvents, preferManual: true)
    }

    func sessionByUpdatingDerivedArtifacts(
        _ session: SessionSnapshot,
        derivedEvents: [EventMarkerRecord],
        trackQuality: TrackQualitySnapshot
    ) -> SessionSnapshot {
        let eventSnapshots = derivedEvents.map {
            EventMarkerSnapshot(
                name: $0.name,
                frameIndex: $0.frameIndex,
                timeS: $0.timeSeconds,
                value: $0.value,
                unitLabel: $0.unitLabel,
                axis: $0.axis.isEmpty ? nil : $0.axis,
                note: $0.note.isEmpty ? nil : $0.note,
                origin: $0.origin
            )
        }
        return SessionSnapshot(
            videoPath: session.videoPath,
            initialBbox: session.initialBbox,
            calibration: session.calibration,
            analysisConfig: session.analysisConfig,
            trackingConfig: session.trackingConfig,
            metadata: session.metadata,
            selectedStartFrame: session.selectedStartFrame,
            selectedEndFrame: session.selectedEndFrame,
            scalePoints: session.scalePoints,
            referenceBbox: session.referenceBbox,
            corrections: session.corrections,
            reviewState: session.reviewState,
            eventMarkers: eventSnapshots,
            additionalObjects: session.additionalObjects,
            trackQuality: trackQuality,
            exportPreferences: session.exportPreferences
        )
    }

    private func deduplicateEvents(_ events: [EventMarkerRecord], preferManual: Bool) -> [EventMarkerRecord] {
        var seen = Set<String>()
        let ordered = events.sorted { lhs, rhs in
            let lhsPriority = preferManual && lhs.origin == "manual" ? 0 : 1
            let rhsPriority = preferManual && rhs.origin == "manual" ? 0 : 1
            return (lhs.frameIndex, lhs.name, lhs.axis, lhsPriority, lhs.origin) < (rhs.frameIndex, rhs.name, rhs.axis, rhsPriority, rhs.origin)
        }

        var filtered: [EventMarkerRecord] = []
        for event in ordered {
            let key = "\(event.name)|\(event.frameIndex)|\(event.axis)"
            if seen.insert(key).inserted {
                filtered.append(event)
            }
        }
        return filtered
    }

    func buildReport(
        session: SessionSnapshot,
        rows: [AnalysisRow],
        trackID: String,
        trackName: String,
        summary: SummarySnapshot,
        quality: QualitySnapshot,
        classification: ExperimentClassificationSnapshot,
        modules: [AnalyzerSnapshot],
        pairwiseMetrics: [PairwiseMetricSnapshot],
        eventMarkers: [EventMarkerRecord],
        reproduceCommand: String
    ) -> String {
        let metadata = session.metadata
        let baseSummary = """
        # Tracker AI Experiment Report

        - Experiment label: `\((metadata?.experimentLabel).nilIfEmpty ?? "unspecified")`
        - Trial ID: `\((metadata?.trialID).nilIfEmpty ?? "unspecified")`
        - Operator: `\((metadata?.operatorName).nilIfEmpty ?? "unspecified")`
        - Video: `\(session.videoPath)`
        - Active track: `\(trackName)` [\(trackID)]
        - Frame range: `\(summary.startFrame ?? session.selectedStartFrame ?? 0)` to `\(summary.endFrame ?? session.selectedEndFrame ?? 0)`
        - Reference length: `\(format(summaryValue: session.calibration.referenceLength)) \(session.calibration.unitLabel)`
        - Reference marker enabled: `\(session.referenceBbox != nil)`
        - Smoothing window: `\(session.analysisConfig.smoothingWindow)` polyorder `\(session.analysisConfig.smoothingPolyorder)`
        - Tracking profile: `\(session.trackingConfig?.profile?.rawValue ?? "auto")`
        - Robust recovery: `\(session.trackingConfig?.robustRecovery ?? true)`
        - Bidirectional refinement: `\(session.trackingConfig?.bidirectionalRefinement ?? true)`
        - Tags: `\((metadata?.tags?.joined(separator: ", ")).nilIfEmpty ?? "none")`
        - Notes: `\((metadata?.notes).nilIfEmpty ?? "none")`
        - Frames analyzed: `\(summary.frameCount ?? 0)`
        - Average confidence: `\(format(summaryValue: summary.averageConfidence))`
        - Low-confidence frames: `\(summary.lowConfidenceFrameCount ?? 0)`
        - Suspect spans: `\(summary.suspectSpanCount ?? 0)`
        - Lost frames: `\(summary.lostFrameCount ?? 0)`
        - Corrected frames: `\(summary.correctedFrameCount ?? 0)`
        - Reacquisitions: `\(summary.reacquisitionCount ?? 0)`
        - Total path length: `\(format(summaryValue: summary.totalPathLength)) \(session.calibration.unitLabel)`
        - Net displacement: `\(format(summaryValue: summary.netDisplacement)) \(session.calibration.unitLabel)`
        - Peak speed: `\(format(summaryValue: summary.peakSpeed)) \(session.calibration.unitLabel)/s`
        - Mean speed: `\(format(summaryValue: summary.meanSpeed)) \(session.calibration.unitLabel)/s`
        - Peak acceleration: `\(format(summaryValue: summary.peakAcceleration)) \(session.calibration.unitLabel)/s^2`
        - Mean acceleration: `\(format(summaryValue: summary.meanAcceleration)) \(session.calibration.unitLabel)/s^2`
        - Review recommended: `\(summary.reviewRecommended ?? quality.reviewRecommended ?? false)`
        - Scientific confidence mean: `\(format(summaryValue: summary.scientificConfidenceMean))`
        - QC badge: `\(summary.qcBadge ?? quality.qcBadge ?? "review_needed")`
        - Quality index: `\(format(summaryValue: quality.qualityIndex))`
        - Classification: `\(classification.title)` (`\(format(summaryValue: classification.confidence))`)
        - Peak position uncertainty: `\(format(summaryValue: summary.peakPositionUncertainty)) \(session.calibration.unitLabel)`
        - Peak velocity uncertainty: `\(format(summaryValue: summary.peakVelocityUncertainty)) \(session.calibration.unitLabel)/s`
        - Events detected: `\(summary.eventCount ?? eventMarkers.count)`
        """

        let reproduceSection = """

        ## Reproduce This Run

        ```bash
        \(reproduceCommand)
        ```
        """

        let qualitySection = """

        ## Quality Notes

        - Quality index: `\(format(summaryValue: quality.qualityIndex))`
        - Calibration confidence: `\(format(summaryValue: quality.calibrationConfidence))`
        - Drift sensitivity: `\(format(summaryValue: quality.driftSensitivity))`
        - Interpolated burden ratio: `\(format(summaryValue: quality.interpolatedBurdenRatio))`

        \(quality.notes?.map { "- \($0)" }.joined(separator: "\n") ?? "- No major QC warnings were detected.")
        """

        let classificationSection = """

        ## Experiment Classification

        - Classification: `\(classification.title)`
        - Confidence: `\(format(summaryValue: classification.confidence))`
        - Summary: \(classification.summary)
        - Supporting analyzers: `\((classification.supportingAnalyzerIDs.joined(separator: ", ").isEmpty ? "none" : classification.supportingAnalyzerIDs.joined(separator: ", ")))`
        """

        let windowSection: String = {
            guard
                let start = session.reviewState?.selectedWindowStart,
                let end = session.reviewState?.selectedWindowEnd,
                let window = summarizeWindow(rows: rows, startFrame: start, endFrame: end)
            else {
                return ""
            }
            let dismissedCount = session.reviewState?.dismissedReviewFrames?.count ?? 0
            return """

            ## Selected Review Window

            - Window frames: `\(window.startFrame)` to `\(window.endFrame)`
            - Duration: `\(format(summaryValue: window.durationSeconds)) s`
            - Displacement: `\(format(summaryValue: window.displacement)) \(session.calibration.unitLabel)`
            - Mean speed: `\(format(summaryValue: window.meanSpeed)) \(session.calibration.unitLabel)/s`
            - Max speed: `\(format(summaryValue: window.maxSpeed)) \(session.calibration.unitLabel)/s`
            - Max acceleration: `\(format(summaryValue: window.maxAcceleration)) \(session.calibration.unitLabel)/s^2`
            - Dismissed review frames: `\(dismissedCount)`
            """
        }()

        let analyzerSection = modules.isEmpty ? "" : """

        ## Experiment Modules

        \(modules.map { module in
            let metrics = module.metrics.map { "\($0.key)=\(format(summaryValue: $0.value)) \($0.unitLabel)".trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
            return "- `\(module.title)` (\(format(summaryValue: module.confidence))): \(metrics)"
        }.joined(separator: "\n"))
        """

        let eventsSection = eventMarkers.isEmpty ? "" : """

        ## Event Journal

        \(eventMarkers.map { event in
            let note = event.note.isEmpty ? "" : " - \(event.note)"
            return "- `\(event.name)` [\(event.origin)] at frame `\(event.frameIndex)` (`\(format(summaryValue: event.timeSeconds))` s): `\(format(summaryValue: event.value)) \(event.unitLabel)`\(note)"
        }.joined(separator: "\n"))
        """

        let anomalySection = (quality.anomalies?.isEmpty == false) ? """

        ## Native QC Anomaly Register

        \(quality.anomalies?.map { anomaly in
            let frameLabel: String = {
                if let endFrame = anomaly.endFrame, endFrame != anomaly.startFrame {
                    return "\(anomaly.startFrame)-\(endFrame)"
                }
                return "\(anomaly.startFrame)"
            }()
            let action = anomaly.recommendedAction.map { " Action: \($0)" } ?? ""
            return "- [\(anomaly.severity.uppercased())] `\(anomaly.title)` at frame(s) `\(frameLabel)` score `\(format(summaryValue: anomaly.score))`: \(anomaly.summary)\(action)"
        }.joined(separator: "\n") ?? "")
        """ : ""

        let pairwiseSection: String = {
            let relevantMetrics = pairwiseMetrics
                .filter { $0.primaryTrackID == trackID || $0.secondaryTrackID == trackID }
                .sorted { $0.minimumSeparation < $1.minimumSeparation }
            guard !relevantMetrics.isEmpty else { return "" }
            return """

            ## Pairwise Metrics

            \(relevantMetrics.map { metric in
                let counterpart = metric.primaryTrackID == trackID ? metric.secondaryTrackID : metric.primaryTrackID
                let collision = metric.collisionFrame.map(String.init) ?? "none"
                return "- `\(trackID)` vs `\(counterpart)`: min separation `\(format(summaryValue: metric.minimumSeparation)) \(session.calibration.unitLabel)`, mean separation `\(format(summaryValue: metric.meanSeparation)) \(session.calibration.unitLabel)`, peak relative speed `\(format(summaryValue: metric.peakRelativeSpeed)) \(session.calibration.unitLabel)/s`, collision frame `\(collision)`"
            }.joined(separator: "\n"))
            """
        }()

        let spanSection = (quality.spanScores?.isEmpty == false) ? """

        ## Native Span Severity Ledger

        \(quality.spanScores?
            .sorted(by: { $0.severityScore > $1.severityScore })
            .prefix(8)
            .map { span in
                let action = span.recommendedAction.map { " Action: \($0)" } ?? ""
                let failure = span.dominantFailureReason.map { " Failure: \($0)." } ?? ""
                return "- `\(span.category)` frames `\(span.startFrame)-\(span.endFrame)` score `\(format(summaryValue: span.severityScore))` tracker `\(format(summaryValue: span.averageTrackerConfidence))` scientific `\(format(summaryValue: span.scientificConfidenceMean))`: \(span.reason).\(failure)\(action)"
            }
            .joined(separator: "\n") ?? "")
        """ : ""

        switch session.exportPreferences?.reportTemplate ?? "research" {
        case "compact":
            return baseSummary + classificationSection + windowSection + qualitySection + pairwiseSection + anomalySection
        case "guided":
            return baseSummary
            + """

            ## Lab Guidance

            - Review suspect and lost spans before using acceleration values in a report.
            - Compare the raw and smoothed tracks if the peak values look physically implausible.
            """
            + reproduceSection
            + classificationSection
            + windowSection
            + qualitySection
            + pairwiseSection
            + anomalySection
            + spanSection
            + analyzerSection
            + eventsSection
        default:
            return baseSummary + reproduceSection + classificationSection + windowSection + qualitySection + pairwiseSection + anomalySection + spanSection + analyzerSection + eventsSection
        }
    }

    private func summarizeWindow(rows: [AnalysisRow], startFrame: Int?, endFrame: Int?) -> NativeWindowSummary? {
        scientificProcessor.summarizeWindow(rows: rows, startFrame: startFrame, endFrame: endFrame)
    }

    private func qcBadge(
        rows: [AnalysisRow],
        scientificConfidenceMean: Double,
        peakPositionUncertainty: Double,
        referenceLength: Double,
        qualityIndex: Double,
        anomalies: [QualityAnomalySnapshot]
    ) -> String {
        guard !rows.isEmpty else { return "review_needed" }
        let lostRatio = Double(rows.filter(\.lost).count) / Double(max(rows.count, 1))
        let highSeverityAnomalies = anomalies.filter { $0.score >= 0.75 }.count
        if scientificConfidenceMean >= 0.88, lostRatio == 0, qualityIndex >= 0.85, highSeverityAnomalies == 0 {
            return "good_for_publication"
        }
        if lostRatio > 0.18 || qualityIndex < 0.45 {
            return "too_much_interpolation"
        }
        if peakPositionUncertainty > max(referenceLength, 1) * 0.10 {
            return "insufficient_calibration"
        }
        return "review_needed"
    }

    func resolvedTrackQuality(session: SessionSnapshot, rows: [AnalysisRow], trackID: String) -> TrackQualitySnapshot {
        if trackID == "primary", let trackQuality = session.trackQuality {
            return trackQuality
        }
        return deriveTrackQuality(rows: rows)
    }

    func deriveTrackQuality(rows: [AnalysisRow]) -> TrackQualitySnapshot {
        let lostSpans = buildTrackSpans(rows: rows, category: "lost_tracking") { $0.lost }
        let suspectSpans = buildTrackSpans(rows: rows, category: "suspect_tracking") {
            $0.state.lowercased() != "tracking"
            || $0.trackerConfidence < 0.35
            || !$0.failureReason.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        }
        let correctedSpans = buildTrackSpans(rows: rows, category: "manual_correction") { $0.corrected }
        let reacquisitionCount = zip(rows, rows.dropFirst()).reduce(into: 0) { count, pair in
            if pair.0.lost && !pair.1.lost {
                count += 1
            }
        }
        let reviewRecommended = !lostSpans.isEmpty || !suspectSpans.isEmpty || rows.contains(where: { $0.trackerConfidence < 0.35 })

        return TrackQualitySnapshot(
            lostSpans: lostSpans,
            suspectSpans: suspectSpans,
            correctedSpans: correctedSpans,
            reacquisitionCount: reacquisitionCount,
            reviewRecommended: reviewRecommended
        )
    }

    private func buildSpanScores(
        session: SessionSnapshot,
        rows: [AnalysisRow],
        trackQuality: TrackQualitySnapshot
    ) -> [QualitySpanScoreSnapshot] {
        let spans: [(String, [TrackSpanSnapshot]?)] = [
            ("lost_tracking", trackQuality.lostSpans),
            ("suspect_tracking", trackQuality.suspectSpans),
            ("manual_correction", trackQuality.correctedSpans),
        ]

        return spans.flatMap { category, snapshots in
            (snapshots ?? []).map { snapshot in
                let coveredRows = rows.filter { $0.frameIndex >= snapshot.startFrame && $0.frameIndex <= snapshot.endFrame }
                let durationFrames = max(snapshot.endFrame - snapshot.startFrame + 1, 1)
                let averageTrackerConfidence = coveredRows.map(\.trackerConfidence).mean()
                let scientificConfidenceMean = coveredRows.map(\.scientificConfidence).mean()
                let peakUncertainty = coveredRows.compactMap(\.positionUncertainty).max() ?? 0
                let dominantFailureReason = coveredRows
                    .map { $0.failureReason.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .mostCommon
                let severityBase: Double = {
                    switch category {
                    case "lost_tracking":
                        return 0.72
                    case "suspect_tracking":
                        return 0.56
                    default:
                        return 0.42
                    }
                }()
                let durationPenalty = min(Double(durationFrames) / 12.0, 0.18)
                let confidencePenalty = min(max(0, 0.55 - averageTrackerConfidence) * 0.7 + max(0, 0.60 - scientificConfidenceMean) * 0.55, 0.28)
                let uncertaintyPenalty = min(peakUncertainty / max(session.calibration.referenceLength * 0.08, 1e-6), 0.20)
                let severityScore = clamp(severityBase + durationPenalty + confidencePenalty + uncertaintyPenalty)
                return QualitySpanScoreSnapshot(
                    category: category,
                    reason: snapshot.reason,
                    startFrame: snapshot.startFrame,
                    endFrame: snapshot.endFrame,
                    durationFrames: durationFrames,
                    severityScore: severityScore,
                    averageTrackerConfidence: averageTrackerConfidence,
                    scientificConfidenceMean: scientificConfidenceMean,
                    dominantFailureReason: dominantFailureReason,
                    recommendedAction: recommendedAction(forSpanCategory: category)
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.severityScore == rhs.severityScore {
                return lhs.startFrame < rhs.startFrame
            }
            return lhs.severityScore > rhs.severityScore
        }
    }

    private func buildAnomalies(
        session: SessionSnapshot,
        rows: [AnalysisRow],
        spanScores: [QualitySpanScoreSnapshot]
    ) -> [QualityAnomalySnapshot] {
        var anomalies: [QualityAnomalySnapshot] = []

        anomalies.append(contentsOf: spanScores.filter { $0.severityScore >= 0.45 }.map { span in
            QualityAnomalySnapshot(
                anomalyID: span.category,
                title: anomalyTitle(forSpanCategory: span.category),
                severity: severityLabel(for: span.severityScore),
                startFrame: span.startFrame,
                endFrame: span.endFrame,
                score: span.severityScore,
                summary: "Reason: \(span.reason). Tracker confidence \(format(summaryValue: span.averageTrackerConfidence)); scientific confidence \(format(summaryValue: span.scientificConfidenceMean)).",
                recommendedAction: span.recommendedAction
            )
        })

        let accelerationValues = rows.map(\.accelerationMagnitude)
        let accelerationThreshold = accelerationValues.mean() + (accelerationValues.standardDeviation() * 2.5)
        let accelerationSpikeSpans = buildTrackSpans(rows: rows, category: "acceleration_spike") { row in
            row.accelerationMagnitude >= accelerationThreshold && row.scientificConfidence < 0.90
        }
        anomalies.append(contentsOf: accelerationSpikeSpans.compactMap { span in
            let coveredRows = rows.filter { $0.frameIndex >= span.startFrame && $0.frameIndex <= span.endFrame }
            let peakAcceleration = coveredRows.map(\.accelerationMagnitude).max() ?? 0
            guard peakAcceleration > accelerationThreshold, coveredRows.count > 0 else { return nil }
            let score = clamp(0.50 + min((peakAcceleration - accelerationThreshold) / max(accelerationThreshold, 1e-6), 0.35))
            return QualityAnomalySnapshot(
                anomalyID: "acceleration_spike",
                title: "Acceleration Spike",
                severity: severityLabel(for: score),
                startFrame: span.startFrame,
                endFrame: span.endFrame,
                score: score,
                summary: "Peak acceleration \(format(summaryValue: peakAcceleration)) \(session.calibration.unitLabel)/s^2 exceeds the native spike threshold.",
                recommendedAction: "Compare the raw and smoothed tracks around this frame before using peak acceleration in a report."
            )
        })

        let uncertaintyThreshold = max(session.calibration.referenceLength * 0.08, 1e-6)
        let uncertaintySpans = buildTrackSpans(rows: rows, category: "uncertainty_spike") { row in
            (row.positionUncertainty ?? 0) >= uncertaintyThreshold
        }
        anomalies.append(contentsOf: uncertaintySpans.compactMap { span in
            let coveredRows = rows.filter { $0.frameIndex >= span.startFrame && $0.frameIndex <= span.endFrame }
            let peakUncertainty = coveredRows.compactMap(\.positionUncertainty).max() ?? 0
            guard peakUncertainty >= uncertaintyThreshold else { return nil }
            let score = clamp(0.48 + min(peakUncertainty / max(uncertaintyThreshold * 2.0, 1e-6), 0.32))
            return QualityAnomalySnapshot(
                anomalyID: "uncertainty_spike",
                title: "Position Uncertainty Spike",
                severity: severityLabel(for: score),
                startFrame: span.startFrame,
                endFrame: span.endFrame,
                score: score,
                summary: "Position uncertainty reached \(format(summaryValue: peakUncertainty)) \(session.calibration.unitLabel), suggesting a drift-sensitive region.",
                recommendedAction: "Re-check calibration coverage and confirm the target box remains tight across this span."
            )
        })

        return Array(Set(anomalies)).sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.startFrame < rhs.startFrame
            }
            return lhs.score > rhs.score
        }
    }

    private func buildQualityIndex(
        rowCount: Int,
        lowConfidenceCount: Int,
        lostCount: Int,
        correctedCount: Int,
        spanScores: [QualitySpanScoreSnapshot],
        anomalies: [QualityAnomalySnapshot]
    ) -> Double {
        let rowScale = Double(max(rowCount, 1))
        let lowConfidenceRatio = Double(lowConfidenceCount) / rowScale
        let lostRatio = Double(lostCount) / rowScale
        let correctedRatio = Double(correctedCount) / rowScale
        let spanPressure = spanScores.prefix(3).map(\.severityScore).mean()
        let anomalyPressure = anomalies.prefix(3).map(\.score).mean()
        return clamp(1.0 - (lowConfidenceRatio * 0.22) - (lostRatio * 0.36) - (correctedRatio * 0.12) - (spanPressure * 0.22) - (anomalyPressure * 0.18))
    }

    private func buildTrackSpans(
        rows: [AnalysisRow],
        category: String,
        predicate: (AnalysisRow) -> Bool
    ) -> [TrackSpanSnapshot] {
        guard !rows.isEmpty else { return [] }
        var spans: [TrackSpanSnapshot] = []
        var startFrame: Int?

        for row in rows {
            if predicate(row) {
                if startFrame == nil {
                    startFrame = row.frameIndex
                }
            } else if let spanStart = startFrame {
                spans.append(TrackSpanSnapshot(startFrame: spanStart, endFrame: row.frameIndex - 1, reason: category))
                startFrame = nil
            }
        }

        if let startFrame, let lastFrame = rows.last?.frameIndex {
            spans.append(TrackSpanSnapshot(startFrame: startFrame, endFrame: lastFrame, reason: category))
        }
        return spans
    }

    private func anomalyTitle(forSpanCategory category: String) -> String {
        switch category {
        case "lost_tracking":
            return "Lost Tracking Span"
        case "suspect_tracking":
            return "Suspect Tracking Span"
        default:
            return "Manual Correction Span"
        }
    }

    private func recommendedAction(forSpanCategory category: String) -> String {
        switch category {
        case "lost_tracking":
            return "Inspect reacquisition behavior and verify interpolation before publication reporting."
        case "suspect_tracking":
            return "Review this segment frame-by-frame and confirm the target box before exporting."
        default:
            return "Keep the native session file with the export so manual interventions remain reproducible."
        }
    }

    private func severityLabel(for score: Double) -> String {
        switch score {
        case 0.75...:
            return "high"
        case 0.55...:
            return "medium"
        default:
            return "low"
        }
    }

    private func clamp(_ value: Double, min minimum: Double = 0.0, max maximum: Double = 1.0) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    private func firstReliableIndex(rows: [AnalysisRow]) -> Int {
        for (index, row) in rows.enumerated() where !row.lost && row.trackerConfidence >= 0.35 {
            return index
        }
        return 0
    }

    private func velocityComponent(
        rows: [AnalysisRow],
        keyPath: KeyPath<AnalysisRow, Double?>,
        source: [Double],
        times: [Double]
    ) -> [Double] {
        let explicit = rows.compactMap { $0[keyPath: keyPath] }
        if explicit.count == rows.count {
            return explicit
        }
        return finiteDifferences(values: source, times: times)
    }

    private func finiteDifferences(values: [Double], times: [Double]) -> [Double] {
        guard values.count == times.count, !values.isEmpty else { return [] }
        guard values.count > 1 else { return [0] }

        var result = Array(repeating: 0.0, count: values.count)
        for index in values.indices {
            if index == 0 {
                let dt = max(times[1] - times[0], 1e-9)
                result[index] = (values[1] - values[0]) / dt
            } else if index == values.count - 1 {
                let dt = max(times[index] - times[index - 1], 1e-9)
                result[index] = (values[index] - values[index - 1]) / dt
            } else {
                let dt = max(times[index + 1] - times[index - 1], 1e-9)
                result[index] = (values[index + 1] - values[index - 1]) / dt
            }
        }
        return result
    }

    private func peakIndices(_ values: [Double]) -> [Int] {
        guard values.count >= 3 else { return [] }
        var peaks: [Int] = []
        for index in 1..<(values.count - 1) where values[index] >= values[index - 1] && values[index] >= values[index + 1] {
            peaks.append(index)
        }
        return peaks
    }

    private func linearFit(x: [Double], y: [Double]) -> (slope: Double, intercept: Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let meanX = x.mean()
        let meanY = y.mean()
        let numerator = zip(x, y).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let denominator = x.map { pow($0 - meanX, 2) }.reduce(0, +)
        guard denominator > 1e-9 else { return nil }
        let slope = numerator / denominator
        let intercept = meanY - slope * meanX
        return (slope, intercept)
    }

    private func quadraticFit(x: [Double], y: [Double]) -> (a: Double, b: Double, c: Double)? {
        guard x.count == y.count, x.count >= 3 else { return nil }

        let n = Double(x.count)
        let sx = x.reduce(0, +)
        let sx2 = x.map { $0 * $0 }.reduce(0, +)
        let sx3 = x.map { $0 * $0 * $0 }.reduce(0, +)
        let sx4 = x.map { $0 * $0 * $0 * $0 }.reduce(0, +)
        let sy = y.reduce(0, +)
        let sxy = zip(x, y).map { $0 * $1 }.reduce(0, +)
        let sx2y = zip(x, y).map { ($0 * $0) * $1 }.reduce(0, +)

        var matrix = [
            [sx4, sx3, sx2, sx2y],
            [sx3, sx2, sx, sxy],
            [sx2, sx, n, sy],
        ]

        for pivot in 0..<3 {
            var maxRow = pivot
            for row in pivot..<3 where abs(matrix[row][pivot]) > abs(matrix[maxRow][pivot]) {
                maxRow = row
            }
            guard abs(matrix[maxRow][pivot]) > 1e-9 else { return nil }
            if maxRow != pivot {
                matrix.swapAt(maxRow, pivot)
            }
            let divisor = matrix[pivot][pivot]
            for column in pivot..<4 {
                matrix[pivot][column] /= divisor
            }
            for row in 0..<3 where row != pivot {
                let factor = matrix[row][pivot]
                for column in pivot..<4 {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
            }
        }

        return (matrix[0][3], matrix[1][3], matrix[2][3])
    }

    private func unwrap(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        var output = [values[0]]
        var offset = 0.0
        for index in 1..<values.count {
            let delta = values[index] - values[index - 1]
            if delta > .pi {
                offset -= 2 * .pi
            } else if delta < -.pi {
                offset += 2 * .pi
            }
            output.append(values[index] + offset)
        }
        return output
    }

    private func format(summaryValue: Double?) -> String {
        guard let summaryValue else { return "0.0000" }
        return String(format: "%.4f", summaryValue)
    }
}

private extension Array where Element == Double {
    func mean() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    func standardDeviation() -> Double {
        guard count > 1 else { return 0 }
        let meanValue = mean()
        let variance = map { pow($0 - meanValue, 2) }.reduce(0, +) / Double(count)
        return sqrt(variance)
    }

    func rangeSpan() -> Double {
        guard let minimum = self.min(), let maximum = self.max() else { return 0 }
        return maximum - minimum
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element: Hashable {
    var mostCommon: Element? {
        guard !isEmpty else { return nil }
        let counts = reduce(into: [Element: Int]()) { result, value in
            result[value, default: 0] += 1
        }
        return counts.max { lhs, rhs in
            if lhs.value == rhs.value {
                return String(describing: lhs.key) > String(describing: rhs.key)
            }
            return lhs.value < rhs.value
        }?.key
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
