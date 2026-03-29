import SwiftUI

struct HelpCenterView: View {
    @Bindable var model: AppModel

    var body: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(text: "Commercialization Notes")
                Text("Tracker AI is now split into a native macOS product shell and a transitional Python analysis engine.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TrackerTheme.ink)
                Text("""
                Native readiness in this package:
                • SwiftUI/AppKit shell for overview, setup, review, and results
                • Workspace/session loading from the existing Python JSON formats
                • Python CLI bridge for running exports from the native app
                • Charts, event journaling, reproducibility, and commercialization-oriented IA
                • Secondary-object, correction-anchor, and export-profile parity from the Python session model

                Still recommended before broad public launch:
                • Replace numeric target/scale entry with native video drawing tools
                • Move tracking/runtime code from Python into native modules or a hardened embedded service
                • Add signing, notarization, sandboxing, crash reporting, analytics, and onboarding
                • Finalize an Xcode-based release pipeline once the local Apple toolchain is healthy
                """)
                .font(.system(size: 14))
                .foregroundStyle(TrackerTheme.muted)
            }
        }
    }
}
