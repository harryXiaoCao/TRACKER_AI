import SwiftUI

struct TrackerPanel<Content: View>: View {
    let padded: Bool
    @ViewBuilder var content: Content

    init(padded: Bool = true, @ViewBuilder content: () -> Content) {
        self.padded = padded
        self.content = content()
    }

    var body: some View {
        content
            .padding(padded ? 20 : 0)
            .background(TrackerTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TrackerTheme.panelStroke.opacity(0.9), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct HeroPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(24)
            .background(TrackerTheme.heroGradient)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct NavChipButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.white : TrackerTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(selected ? TrackerTheme.navy : Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? TrackerTheme.navy.opacity(0.9) : TrackerTheme.navy)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GhostActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(TrackerTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(configuration.isPressed ? 0.95 : 0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TrackerTheme.panelStroke.opacity(0.85), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(TrackerTheme.muted)
            .tracking(1.0)
    }
}

struct MetricTileView: View {
    let tile: MetricTile

    var body: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(tile.value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TrackerTheme.ink)
                Text(tile.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TrackerTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatusPill: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tone.opacity(0.12))
            .clipShape(Capsule())
    }
}
