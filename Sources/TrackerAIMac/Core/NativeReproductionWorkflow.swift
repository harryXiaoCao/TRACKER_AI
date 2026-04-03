import Foundation

enum NativeReproductionWorkflow {
    static func build(
        session: SessionSnapshot,
        outputDirectory: URL,
        trackingProfile: TrackingProfileOption,
        includeOverlay: Bool,
        includePlots: Bool,
        debugTracking: Bool
    ) -> String {
        _ = outputDirectory
        var lines = [
            "# Native TrackerAI reproduction workflow",
            "# 1. Launch TrackerAI.app.",
            "# 2. Load the bundled session file shown below.",
            "# 3. Confirm the source video resolves in the Setup workspace.",
            "# 4. Run analysis or export a fresh research bundle to a new directory.",
            "#",
            "# Session file: ./session.json",
            "# Source video: \(session.videoPath)",
            "# Tracking profile: \(trackingProfile.rawValue)",
            "# Smoothing: window \(session.analysisConfig.smoothingWindow), polyorder \(session.analysisConfig.smoothingPolyorder)",
            "# Include overlay: \(includeOverlay)",
            "# Include plots: \(includePlots)",
            "# Debug tracking: \(debugTracking)",
        ]

        if let referenceBox = session.referenceBbox {
            lines.append(
                "# Reference marker bbox: \(format(referenceBox.x)) \(format(referenceBox.y)) \(format(referenceBox.width)) \(format(referenceBox.height))"
            )
        }

        if let metadata = session.metadata {
            if let label = metadata.experimentLabel, !label.isEmpty {
                lines.append("# Experiment label: \(label)")
            }
            if let trialID = metadata.trialID, !trialID.isEmpty {
                lines.append("# Trial ID: \(trialID)")
            }
        }

        lines.append("open -a TrackerAI")
        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}
