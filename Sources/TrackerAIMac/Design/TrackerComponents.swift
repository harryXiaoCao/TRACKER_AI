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
            .padding(padded ? TrackerTheme.Spacing.md : 0)
            .background(TrackerTheme.panelElevated)
            .overlay(panelBorder)
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel, style: .continuous))
            .shadow(color: TrackerTheme.panelShadow, radius: 18, x: 0, y: 10)
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel, style: .continuous)
            .strokeBorder(TrackerTheme.panelStroke.opacity(0.72), lineWidth: 1)
    }
}

struct HeroPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(TrackerTheme.Spacing.md)
            .background(TrackerTheme.heroGradient)
            .overlay(
                RoundedRectangle(cornerRadius: TrackerTheme.Radius.workspace, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.workspace, style: .continuous))
            .shadow(color: TrackerTheme.navy.opacity(0.18), radius: 24, x: 0, y: 14)
    }
}

struct PanelSectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String
    var titleColor: Color = TrackerTheme.ink
    var detailColor: Color = TrackerTheme.muted
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: TrackerTheme.Spacing.xxxs + 2) {
            SectionEyebrow(text: eyebrow)
            Text(title)
                .trackerText(.sectionTitle, color: titleColor)
            Text(detail)
                .trackerText(.body, color: detailColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InlineEmptyState: View {
    let eyebrow: String
    let title: String
    let detail: String
    let symbolName: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: TrackerTheme.Spacing.sm) {
            Image(systemName: symbolName)
                .trackerText(.cardTitle, color: TrackerTheme.scienceBlue)
                .frame(width: 34, height: 34)
                .background(TrackerTheme.scienceBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxs) {
                SectionEyebrow(text: eyebrow)
                Text(title)
                    .trackerText(.cardTitle)
                Text(detail)
                    .trackerText(.body, color: TrackerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TrackerTheme.Spacing.sm)
        .background(Color.white.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.62), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
    }
}

struct NavChipButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .trackerText(.caption, color: selected ? .white : TrackerTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TrackerTheme.Spacing.xxs + 2)
        }
        .buttonStyle(TrackerSelectableChipButtonStyle(selected: selected))
    }
}

struct TrackerPageHeader: View {
    let eyebrow: String
    let title: String
    let summary: String
    let detail: String
    let statusText: String
    let statusTone: TrackerTheme.Status
    let actions: AnyView

    init(
        eyebrow: String,
        title: String,
        summary: String,
        detail: String,
        statusText: String,
        statusTone: TrackerTheme.Status,
        @ViewBuilder actions: () -> some View = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.summary = summary
        self.detail = detail
        self.statusText = statusText
        self.statusTone = statusTone
        self.actions = AnyView(actions())
    }

    var body: some View {
        HStack(alignment: .top, spacing: TrackerTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
                SectionEyebrow(text: eyebrow)

                HStack(alignment: .firstTextBaseline, spacing: TrackerTheme.Spacing.xs) {
                    Text(title)
                        .trackerText(.appTitle)
                        .lineLimit(1)

                    StatusPill(text: statusText, style: statusTone)
                }

                Text(summary)
                    .trackerText(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .trackerText(.caption, color: TrackerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: TrackerTheme.Spacing.md)

            actions
        }
    }
}

struct TrackerShellNavigationButton: View {
    let title: String
    let symbolName: String
    let stepNumber: Int?
    let state: ShellNavigationState
    let statusText: String
    let statusTone: TrackerTheme.Status
    let summary: String
    let accessoryText: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? TrackerTheme.scienceBlue : Color.clear)
                    .frame(width: 3)

                HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
                    iconToken

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(title)
                                .trackerText(.bodyStrong, color: titleColor)
                                .lineLimit(1)

                            if let accessoryText {
                                Text(accessoryText)
                                    .trackerText(.helper, color: accessoryColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(accessoryFill)
                                    .clipShape(Capsule())
                            }
                        }

                        StatusPill(text: statusText, style: statusTone)
                            .fixedSize()

                        Text(summary)
                            .trackerText(.helper, color: detailColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)

                        if let detail = stateDetail {
                            Text(detail)
                                .trackerText(.helper, color: secondaryDetailColor)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(.horizontal, TrackerTheme.Spacing.xs)
            .padding(.vertical, TrackerTheme.Spacing.xs + 1)
            .background(backgroundFill)
            .overlay(selectionBorder)
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state.isLocked)
        .help(state.lockReason ?? title)
    }

    private var titleColor: Color {
        switch state {
        case .locked:
            return TrackerTheme.tertiaryText
        case .active:
            return TrackerTheme.navy
        default:
            return TrackerTheme.ink
        }
    }

    private var detailColor: Color {
        state.isLocked ? TrackerTheme.tertiaryText : TrackerTheme.muted
    }

    private var secondaryDetailColor: Color {
        state.isLocked ? TrackerTheme.tertiaryText.opacity(0.9) : TrackerTheme.tertiaryText
    }

    private var iconColor: Color {
        switch state {
        case .locked:
            return TrackerTheme.tertiaryText
        case .active:
            return TrackerTheme.navy
        case .complete:
            return TrackerTheme.success
        case .available:
            return TrackerTheme.scienceBlue
        }
    }

    private var stateDetail: String? {
        switch state {
        case .available:
            return nil
        case .active:
            return "Current page"
        case .complete:
            return "Milestone satisfied"
        case let .locked(reason):
            return reason
        }
    }

    @ViewBuilder
    private var iconToken: some View {
        if let stepNumber {
            Text("\(stepNumber)")
                .trackerText(.caption, color: iconColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(iconBackground)
                )
                .overlay(
                    Circle()
                        .strokeBorder(iconStroke, lineWidth: 1)
                )
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(iconStroke, lineWidth: 1)
                )
        }
    }

    private var iconBackground: Color {
        switch state {
        case .locked:
            return TrackerTheme.disabledFill
        case .complete:
            return TrackerTheme.success.opacity(0.12)
        case .active:
            return TrackerTheme.scienceBlue.opacity(0.14)
        case .available:
            return Color.white.opacity(0.84)
        }
    }

    private var iconStroke: Color {
        switch state {
        case .locked:
            return TrackerTheme.panelStroke.opacity(0.52)
        case .complete:
            return TrackerTheme.success.opacity(0.32)
        case .active:
            return TrackerTheme.scienceBlue.opacity(0.30)
        case .available:
            return TrackerTheme.panelStroke.opacity(0.56)
        }
    }

    private var accessoryColor: Color {
        state.isLocked ? TrackerTheme.tertiaryText : TrackerTheme.scienceBlue
    }

    private var accessoryFill: Color {
        state.isLocked ? TrackerTheme.disabledFill : TrackerTheme.scienceBlue.opacity(0.10)
    }

    private var backgroundFill: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 6, style: .continuous)
            .fill(isSelected ? TrackerTheme.steel.opacity(0.78) : Color.white.opacity(0.66))
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 6, style: .continuous)
            .strokeBorder(
                isSelected ? TrackerTheme.selectionRing : TrackerTheme.panelStroke.opacity(0.38),
                lineWidth: isSelected ? 1.5 : 1
            )
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrackerButtonStyle(variant: .primary).makeBody(configuration: configuration)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrackerButtonStyle(variant: .secondary).makeBody(configuration: configuration)
    }
}

struct TertiaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrackerButtonStyle(variant: .tertiary).makeBody(configuration: configuration)
    }
}

struct DestructiveActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrackerButtonStyle(variant: .destructive).makeBody(configuration: configuration)
    }
}

struct SuccessActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrackerButtonStyle(variant: .success).makeBody(configuration: configuration)
    }
}

struct GhostActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrackerButtonStyle(variant: .secondary).makeBody(configuration: configuration)
    }
}

struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .trackerText(.eyebrow, color: TrackerTheme.tertiaryText)
    }
}

struct MetricTileView: View {
    let tile: MetricTile

    var body: some View {
        TrackerPanel {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxs) {
                Text(tile.value)
                    .trackerText(.metric)
                Text(tile.title.uppercased())
                    .trackerText(.eyebrow, color: TrackerTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CurrentTrialStatusCard: View {
    let title: String
    let value: String
    var tone: Color = TrackerTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .trackerText(.monoCaption, color: TrackerTheme.tertiaryText)

            Text(value)
                .trackerText(.cardTitle, color: tone)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TrackerTheme.Spacing.xs)
        .padding(.vertical, TrackerTheme.Spacing.xs - 2)
        .background(Color.white.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.68), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
    }
}

struct WorkspaceControlCard<Content: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var content: Content

    init(title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xs) {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                Text(title)
                    .trackerText(.cardTitle)
                if let detail {
                    Text(detail)
                        .trackerText(.body, color: TrackerTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TrackerTheme.Spacing.sm)
        .background(Color.white.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous)
                .strokeBorder(TrackerTheme.panelStroke.opacity(0.74), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
    }
}

struct StatusPill: View {
    let text: String
    private let tint: Color
    private let useInverseForeground: Bool

    init(text: String, tone: Color) {
        self.text = text
        self.tint = tone
        self.useInverseForeground = false
    }

    init(text: String, style: TrackerTheme.Status) {
        self.text = text
        self.tint = style.tint
        self.useInverseForeground = style == .inverse
    }

    var body: some View {
        Text(text)
            .trackerText(.caption, color: useInverseForeground ? TrackerTheme.navy : tint)
            .padding(.horizontal, TrackerTheme.Spacing.xs)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(useInverseForeground ? Color.white.opacity(0.92) : tint.opacity(0.13))
            )
            .overlay(
                Capsule()
                    .strokeBorder(useInverseForeground ? Color.white.opacity(0.18) : tint.opacity(0.22), lineWidth: 1)
            )
    }
}

struct CompletionBanner: View {
    let milestone: CompletionMilestone

    var body: some View {
        HStack(alignment: .top, spacing: TrackerTheme.Spacing.xs) {
            Image(systemName: milestone.symbolName)
                .trackerText(.caption, color: TrackerTheme.success)
                .frame(width: 30, height: 30)
                .background(TrackerTheme.success.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                Text(milestone.title)
                    .trackerText(.cardTitle)
                Text(milestone.detail)
                    .trackerText(.body, color: TrackerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            StatusPill(text: "Complete", style: .complete)
        }
        .padding(TrackerTheme.Spacing.sm - 2)
        .background(TrackerTheme.success.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous)
                .strokeBorder(TrackerTheme.success.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
    }
}

struct WorkflowStepCard: View {
    enum Tone {
        case completed
        case current
        case next
        case blocked
    }

    let index: Int
    let title: String
    let detail: String
    let tone: Tone
    let action: () -> Void
    @State private var isHovered = false

    private var tint: Color {
        switch tone {
        case .completed: return TrackerTheme.success
        case .current: return TrackerTheme.scienceBlue
        case .next: return TrackerTheme.accent
        case .blocked: return TrackerTheme.panelStroke
        }
    }

    private var titleColor: Color {
        tone == .blocked ? TrackerTheme.muted : TrackerTheme.ink
    }

    private var statusText: String {
        switch tone {
        case .completed: return "Complete"
        case .current: return "Current"
        case .next: return "Next"
        case .blocked: return "Blocked"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxs + 2) {
                HStack {
                    Text("\(index)")
                        .trackerText(.caption, color: tone == .blocked ? TrackerTheme.muted : .white)
                        .frame(width: 24, height: 24)
                        .background(tone == .blocked ? TrackerTheme.steel : tint)
                        .clipShape(Circle())

                    Spacer()

                    StatusPill(text: statusText, tone: tint)
                }

                Text(title)
                    .trackerText(.cardTitle, color: titleColor)

                Text(detail)
                    .trackerText(.body, color: TrackerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TrackerTheme.Spacing.sm - 2)
            .background(backgroundFill)
            .overlay(
                RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.panel - 4, style: .continuous))
            .scaleEffect(isHovered && tone != .blocked ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .disabled(tone == .blocked)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var backgroundFill: Color {
        if tone == .blocked {
            return TrackerTheme.disabledFill
        }
        return isHovered ? TrackerTheme.hoverFill : Color.white.opacity(0.82)
    }

    private var borderColor: Color {
        tint.opacity(tone == .blocked ? 0.42 : (isHovered ? 0.94 : 0.74))
    }
}

private struct TrackerSelectableChipButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TrackerSelectableChipButtonBody(configuration: configuration, selected: selected)
    }
}

private struct TrackerSelectableChipButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.6)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
            .fill(backgroundColor)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.button, style: .continuous)
            .strokeBorder(borderColor, lineWidth: 1)
    }

    private var backgroundColor: Color {
        if !isEnabled { return TrackerTheme.disabledFill }
        if selected { return configuration.isPressed ? TrackerTheme.navy.opacity(0.86) : TrackerTheme.navy }
        if configuration.isPressed { return TrackerTheme.steel.opacity(0.96) }
        return isHovered ? TrackerTheme.hoverFill : Color.white.opacity(0.74)
    }

    private var borderColor: Color {
        if selected { return TrackerTheme.selectionRing }
        return isHovered ? TrackerTheme.scienceBlue.opacity(0.34) : TrackerTheme.panelStroke.opacity(0.8)
    }
}

struct TrackerButtonStyle: ButtonStyle {
    let variant: TrackerTheme.ButtonVariant

    func makeBody(configuration: Configuration) -> some View {
        TrackerButtonBody(configuration: configuration, variant: variant)
    }
}

private struct TrackerButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: TrackerTheme.ButtonVariant
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .trackerText(.caption, color: foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: shadowColor, radius: isHovered ? 14 : 8, x: 0, y: isHovered ? 8 : 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.56)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(backgroundColor)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: 1)
    }

    private var horizontalPadding: CGFloat {
        variant == .tertiary ? TrackerTheme.Spacing.xs : TrackerTheme.Spacing.sm
    }

    private var verticalPadding: CGFloat {
        variant == .stage ? TrackerTheme.Spacing.xxs + 1 : TrackerTheme.Spacing.xxs + 2
    }

    private var cornerRadius: CGFloat {
        variant == .stage ? TrackerTheme.Radius.field : TrackerTheme.Radius.button
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .destructive, .success, .stage:
            return .white
        case .secondary, .tertiary:
            return TrackerTheme.ink
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return TrackerTheme.disabledFill }
        switch variant {
        case .primary:
            return configuration.isPressed ? TrackerTheme.scienceBlue.opacity(0.92) : (isHovered ? TrackerTheme.scienceBlue : TrackerTheme.navy)
        case .secondary:
            if configuration.isPressed { return TrackerTheme.steel.opacity(0.96) }
            return isHovered ? TrackerTheme.hoverFill : Color.white.opacity(0.86)
        case .tertiary:
            return isHovered ? TrackerTheme.steel.opacity(configuration.isPressed ? 0.82 : 0.52) : Color.clear
        case .destructive:
            return configuration.isPressed ? TrackerTheme.critical.opacity(0.9) : (isHovered ? TrackerTheme.critical : TrackerTheme.critical.opacity(0.94))
        case .success:
            return configuration.isPressed ? TrackerTheme.success.opacity(0.9) : (isHovered ? TrackerTheme.ready : TrackerTheme.success)
        case .stage:
            return Color.black.opacity(configuration.isPressed ? 0.40 : (isHovered ? 0.34 : 0.26))
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return TrackerTheme.panelStroke.opacity(0.32) }
        switch variant {
        case .primary:
            return isHovered ? TrackerTheme.focusRing : TrackerTheme.navy.opacity(0.14)
        case .secondary:
            return isHovered ? TrackerTheme.selectionRing : TrackerTheme.panelStroke.opacity(0.82)
        case .tertiary:
            return isHovered ? TrackerTheme.selectionRing : .clear
        case .destructive:
            return TrackerTheme.critical.opacity(isHovered ? 0.48 : 0.26)
        case .success:
            return TrackerTheme.success.opacity(isHovered ? 0.44 : 0.22)
        case .stage:
            return Color.white.opacity(isHovered ? 0.22 : 0.14)
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .primary:
            return TrackerTheme.navy.opacity(isHovered ? 0.18 : 0.10)
        case .destructive:
            return TrackerTheme.critical.opacity(isHovered ? 0.16 : 0.08)
        case .success:
            return TrackerTheme.success.opacity(isHovered ? 0.16 : 0.08)
        case .secondary, .tertiary, .stage:
            return Color.black.opacity(isHovered ? 0.08 : 0.03)
        }
    }
}
