import SwiftUI

struct TrackerValidationMessage {
    enum Tone {
        case neutral
        case warning
        case error
        case success

        var color: Color {
            switch self {
            case .neutral: return TrackerTheme.muted
            case .warning: return TrackerTheme.warning
            case .error: return TrackerTheme.critical
            case .success: return TrackerTheme.success
            }
        }

        var status: TrackerTheme.Status {
            switch self {
            case .neutral: return .neutral
            case .warning: return .warning
            case .error: return .error
            case .success: return .complete
            }
        }
    }

    let text: String
    let tone: Tone
}

enum TrackerFieldTone {
    case normal
    case selected
    case success
    case warning
    case error

    var strokeColor: Color {
        switch self {
        case .normal: return TrackerTheme.panelStroke.opacity(0.86)
        case .selected: return TrackerTheme.scienceBlue.opacity(0.44)
        case .success: return TrackerTheme.success.opacity(0.38)
        case .warning: return TrackerTheme.warning.opacity(0.42)
        case .error: return TrackerTheme.critical.opacity(0.44)
        }
    }

    var fillColor: Color {
        switch self {
        case .normal: return Color.white.opacity(0.94)
        case .selected: return Color.white
        case .success: return TrackerTheme.success.opacity(0.06)
        case .warning: return TrackerTheme.warning.opacity(0.08)
        case .error: return TrackerTheme.critical.opacity(0.08)
        }
    }
}

struct ReadinessRow: View {
    let title: String
    let complete: Bool

    var body: some View {
        HStack(spacing: TrackerTheme.Spacing.xxs) {
            Circle()
                .fill(complete ? TrackerTheme.success : TrackerTheme.panelStroke)
                .frame(width: 10, height: 10)
            Text(title)
                .trackerText(.bodyStrong)
            Spacer()
            StatusPill(text: complete ? "Complete" : "Waiting", style: complete ? .complete : .neutral)
        }
    }
}

struct MacFormRow<Content: View>: View {
    let label: String
    let helper: String?
    let validation: TrackerValidationMessage?
    let controlWidth: CGFloat?
    @ViewBuilder var content: Content

    init(
        label: String,
        helper: String? = nil,
        validation: TrackerValidationMessage? = nil,
        controlWidth: CGFloat? = 300,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.helper = helper
        self.validation = validation
        self.controlWidth = controlWidth
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs + 2) {
            HStack(alignment: .top, spacing: TrackerTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs) {
                    Text(label)
                        .trackerText(.caption)
                        .frame(width: 132, alignment: .leading)

                    if let helper {
                        Text(helper)
                            .trackerText(.helper, color: TrackerTheme.tertiaryText)
                            .frame(width: 132, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: TrackerTheme.Spacing.xxxs + 2) {
                    content
                        .frame(maxWidth: controlWidth, alignment: .leading)

                    if let validation {
                        HStack(spacing: 6) {
                            Image(systemName: validationIcon(for: validation.tone))
                                .trackerText(.helper, color: validation.tone.color)
                            Text(validation.text)
                                .trackerText(.helper, color: validation.tone.color)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func validationIcon(for tone: TrackerValidationMessage.Tone) -> String {
        switch tone {
        case .neutral: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
}

struct TrackerTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: Int? = nil
    var fieldTone: TrackerFieldTone = .normal
    var width: CGFloat? = 300

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Group {
            if let lineLimit {
                TextField(placeholder, text: $text, axis: axis)
                    .lineLimit(lineLimit, reservesSpace: true)
            } else {
                TextField(placeholder, text: $text, axis: axis)
            }
        }
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, TrackerTheme.Spacing.xs)
            .padding(.vertical, axis == .vertical ? TrackerTheme.Spacing.xs - 2 : TrackerTheme.Spacing.xxs + 2)
            .frame(maxWidth: width, alignment: .leading)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.field, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var effectiveTone: TrackerFieldTone {
        if isFocused {
            return .selected
        }
        return fieldTone
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.field, style: .continuous)
            .fill(isHovered ? TrackerTheme.hoverFill : effectiveTone.fillColor)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.field, style: .continuous)
            .strokeBorder(effectiveTone.strokeColor, lineWidth: isFocused ? 1.6 : 1)
            .shadow(color: isFocused ? TrackerTheme.focusRing : .clear, radius: 0, x: 0, y: 0)
    }
}

struct TrackerControlSurface<Content: View>: View {
    let tone: TrackerFieldTone
    let width: CGFloat?
    @ViewBuilder var content: Content

    @State private var isHovered = false

    init(tone: TrackerFieldTone = .normal, width: CGFloat? = 300, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.width = width
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, TrackerTheme.Spacing.xs)
            .padding(.vertical, TrackerTheme.Spacing.xxs + 2)
            .frame(maxWidth: width, alignment: .leading)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: TrackerTheme.Radius.field, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.field, style: .continuous)
            .fill(isHovered ? TrackerTheme.hoverFill : tone.fillColor)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: TrackerTheme.Radius.field, style: .continuous)
            .strokeBorder(tone.strokeColor, lineWidth: 1)
    }
}

struct NumericGrid: View {
    @Binding var box: BoundingBoxDraft
    @Binding var scale: ScaleLineDraft
    private let mode: String

    init(box: Binding<BoundingBoxDraft>) {
        _box = box
        _scale = .constant(ScaleLineDraft())
        mode = "box"
    }

    init(scale: Binding<ScaleLineDraft>) {
        _scale = scale
        _box = .constant(BoundingBoxDraft())
        mode = "scale"
    }

    var body: some View {
        Grid(horizontalSpacing: TrackerTheme.Spacing.xxs, verticalSpacing: TrackerTheme.Spacing.xxs) {
            if mode == "box" {
                GridRow {
                    TrackerTextField(placeholder: "x", text: $box.x, width: 132)
                    TrackerTextField(placeholder: "y", text: $box.y, width: 132)
                }
                GridRow {
                    TrackerTextField(placeholder: "width", text: $box.width, width: 132)
                    TrackerTextField(placeholder: "height", text: $box.height, width: 132)
                }
            } else {
                GridRow {
                    TrackerTextField(placeholder: "x1", text: $scale.x1, width: 132)
                    TrackerTextField(placeholder: "y1", text: $scale.y1, width: 132)
                }
                GridRow {
                    TrackerTextField(placeholder: "x2", text: $scale.x2, width: 132)
                    TrackerTextField(placeholder: "y2", text: $scale.y2, width: 132)
                }
            }
        }
    }
}

struct AdditionalObjectGrid: View {
    @Binding var object: AdditionalObjectDraft

    var body: some View {
        Grid(horizontalSpacing: TrackerTheme.Spacing.xxs, verticalSpacing: TrackerTheme.Spacing.xxs) {
            GridRow {
                TrackerTextField(placeholder: "track_id", text: $object.trackID, width: 132)
                TrackerTextField(placeholder: "display name", text: $object.name, width: 132)
            }
            GridRow {
                TrackerTextField(placeholder: "kind", text: $object.kind, width: 132)
                Spacer()
            }
            GridRow {
                TrackerTextField(placeholder: "x", text: $object.x, width: 132)
                TrackerTextField(placeholder: "y", text: $object.y, width: 132)
            }
            GridRow {
                TrackerTextField(placeholder: "width", text: $object.width, width: 132)
                TrackerTextField(placeholder: "height", text: $object.height, width: 132)
            }
        }
    }
}
