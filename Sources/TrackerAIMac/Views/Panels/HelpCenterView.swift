import SwiftUI

struct HelpCenterView: View {
    @Bindable var model: AppModel
    let showsHero: Bool

    init(model: AppModel, showsHero: Bool = true) {
        self.model = model
        self.showsHero = showsHero
    }

    var body: some View {
        VStack(spacing: TrackerTheme.Spacing.sm) {
            if showsHero {
                HeroPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.sm - 2) {
                        PanelSectionHeader(
                            eyebrow: "Help Center",
                            title: "Guidance for setup, review, and export",
                            detail: "Use this panel as a quick reference while staying inside the active workspace.",
                            titleColor: .white,
                            detailColor: Color.white.opacity(0.82)
                        )

                        HStack(spacing: TrackerTheme.Spacing.xs) {
                            StatusPill(text: model.currentVideoURL == nil ? "Import first" : model.workflowState.title, style: .inverse)
                            StatusPill(text: model.hasActiveAnalysisResults ? "Results loaded" : "No results yet", style: .inverse)
                        }
                    }
                }
            }

            TrackerPanel {
                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                    PanelSectionHeader(
                        eyebrow: "Quick Start",
                        title: "Recommended workflow",
                        detail: "Follow these steps for the clearest first pass through Tracker AI."
                    )

                    helpStep(title: "1. Import a clip", detail: "Open a video or saved session so the workspace can attach setup, review, and export state to a real source.")
                    helpStep(title: "2. Calibrate the scene", detail: "Draw the scale line and confirm the physical unit before measuring motion.")
                    helpStep(title: "3. Confirm the target", detail: "Draw the primary tracking box, then run the preview check if the object is small, fast, or near an edge.")
                    helpStep(title: "4. Run analysis", detail: "Choose the frame range, launch analysis, then move into Review and Results when the run finishes.")
                }
            }

            VStack(spacing: TrackerTheme.Spacing.sm) {
                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Scientific Terms",
                            title: "What the core controls mean",
                            detail: "Short explanations for the concepts most likely to matter during first use."
                        )

                        glossaryRow(term: "Calibration", detail: "Maps pixel distances to real-world units so graphs, CSV files, and reports use physical measurements.")
                        glossaryRow(term: "Reference marker", detail: "Optional stable object used to spot or compensate for drift in the camera or apparatus.")
                        glossaryRow(term: "Review queue", detail: "Frames and spans that need attention because confidence dropped, tracking was lost, or an event was marked.")
                        glossaryRow(term: "Pairwise metrics", detail: "Relative distance and speed measurements between two tracked objects.")
                    }
                }

                TrackerPanel {
                    VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                        PanelSectionHeader(
                            eyebrow: "Build Status",
                            title: "What this build already supports",
                            detail: "This summary reflects the native macOS app workflow rather than internal development language."
                        )

                        Text("• Unified overview, setup, review, and results workspaces")
                            .trackerText(.body)
                        Text("• Native tracking, scientific processing, charts, event journaling, and CSV/report export")
                            .trackerText(.body)
                        Text("• Saved sessions, workspace clips, additional objects, and reproducibility metadata")
                            .trackerText(.body)
                        Text("• Secure access to user-selected files and folders in the signed app flow")
                            .trackerText(.body)

                        Divider()

                        Text("Commercial readiness work still focused on final accessibility, resize polish, and release services.")
                            .trackerText(.caption, color: TrackerTheme.muted)
                    }
                }
            }
        }
    }

    private func helpStep(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
            Text(title)
                .trackerText(.cardTitle)
                .frame(width: 140, alignment: .leading)
            Text(detail)
                .trackerText(.body, color: TrackerTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func glossaryRow(term: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
            Text(term)
                .trackerText(.cardTitle)
            Text(detail)
                .trackerText(.body, color: TrackerTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TrackerTheme.Spacing.xs)
        .background(TrackerTheme.steel.opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }
}
