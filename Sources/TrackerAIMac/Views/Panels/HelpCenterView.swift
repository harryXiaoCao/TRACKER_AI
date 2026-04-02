import SwiftUI

struct HelpCenterView: View {
    @Bindable var model: AppModel

    var body: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(text: "Commercialization Notes")
                Text("Tracker AI now runs its analysis bundle through a native macOS coordinator, while the Python bridge remains for legacy session and bundle compatibility.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TrackerTheme.ink)
                Text("""
                Native readiness in this package:
                • SwiftUI/AppKit shell for overview, setup, review, and results
                • Workspace/session loading from the existing Python JSON formats
                • Native tracking, scientific processing, and bundle export coordination
                • Legacy bundle reload through the compatibility bridge after native export
                • Charts, event journaling, reproducibility, and commercialization-oriented IA
                • Secondary-object, correction-anchor, and export-profile parity from the Python session model

                Still recommended before broad public launch:
                • Replace numeric target/scale entry with native video drawing tools
                • Port correction replay and the remaining review/setup parity items
                • Add signing, notarization, sandboxing, crash reporting, analytics, and onboarding
                • Finalize an Xcode-based release pipeline once the local Apple toolchain is healthy
                """)
                .font(.system(size: 14))
                .foregroundStyle(TrackerTheme.muted)
            }
        }
    }
}
