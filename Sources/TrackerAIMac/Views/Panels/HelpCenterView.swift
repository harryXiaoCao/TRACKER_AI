import SwiftUI

struct HelpCenterView: View {
    @Bindable var model: AppModel

    var body: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(text: "Commercialization Notes")
                Text("Tracker AI now ships its analysis flow as a native macOS workflow, while the compatibility bridge remains limited to legacy session and bundle formats.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TrackerTheme.ink)
                Text("""
                Native readiness in this package:
                • SwiftUI/AppKit shell for overview, setup, review, and results
                • Workspace/session loading from the existing research JSON formats
                • Native tracking, scientific processing, and bundle export coordination
                • Legacy bundle reload through the compatibility bridge after native export
                • Security-scoped file access aligned with App Sandbox user-selected documents
                • Release validation for plist metadata, entitlements, archive handoff, and app-icon completeness
                • Charts, event journaling, reproducibility, and commercialization-oriented IA
                • Secondary-object, correction-anchor, and export-profile parity from the established session model

                Remaining external launch integrations:
                • Continue polish on setup/review UX and document-based reopening flows
                • Connect Apple signing/notarization credentials for archive export and distribution
                • Choose and wire the final update, crash-reporting, and licensing providers for the release channel
                """)
                .font(.system(size: 14))
                .foregroundStyle(TrackerTheme.muted)
            }
        }
    }
}
