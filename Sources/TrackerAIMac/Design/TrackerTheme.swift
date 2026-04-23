import SwiftUI

enum TrackerTheme {
    enum Spacing {
        static let xxxs: CGFloat = 4
        static let xxs: CGFloat = 8
        static let xs: CGFloat = 12
        static let sm: CGFloat = 16
        static let md: CGFloat = 24
        static let lg: CGFloat = 32
    }

    enum Radius {
        static let field: CGFloat = 14
        static let button: CGFloat = 16
        static let panel: CGFloat = 22
        static let workspace: CGFloat = 30
    }

    enum Typography {
        static let appTitle = Font.system(size: 30, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let cardTitle = Font.system(size: 15, weight: .semibold, design: .default)
        static let body = Font.system(size: 13, weight: .regular, design: .default)
        static let bodyStrong = Font.system(size: 13, weight: .semibold, design: .default)
        static let caption = Font.system(size: 12, weight: .medium, design: .default)
        static let helper = Font.system(size: 11, weight: .regular, design: .default)
        static let eyebrow = Font.system(size: 11, weight: .bold, design: .rounded)
        static let metric = Font.system(size: 22, weight: .bold, design: .rounded)
        static let monoBody = Font.system(size: 12, weight: .medium, design: .monospaced)
        static let monoCaption = Font.system(size: 12, weight: .bold, design: .monospaced)
    }

    enum Status {
        case ready
        case warning
        case error
        case processing
        case complete
        case neutral
        case accent
        case inverse

        var tint: Color {
            switch self {
            case .ready: return TrackerTheme.ready
            case .warning: return TrackerTheme.warning
            case .error: return TrackerTheme.critical
            case .processing: return TrackerTheme.processing
            case .complete: return TrackerTheme.success
            case .neutral: return TrackerTheme.muted
            case .accent: return TrackerTheme.accent
            case .inverse: return .white
            }
        }
    }

    enum ButtonVariant {
        case primary
        case secondary
        case tertiary
        case destructive
        case success
        case stage
    }

    enum TextStyle {
        case appTitle
        case sectionTitle
        case cardTitle
        case body
        case bodyStrong
        case caption
        case helper
        case eyebrow
        case metric
        case monoBody
        case monoCaption

        var font: Font {
            switch self {
            case .appTitle: return Typography.appTitle
            case .sectionTitle: return Typography.sectionTitle
            case .cardTitle: return Typography.cardTitle
            case .body: return Typography.body
            case .bodyStrong: return Typography.bodyStrong
            case .caption: return Typography.caption
            case .helper: return Typography.helper
            case .eyebrow: return Typography.eyebrow
            case .metric: return Typography.metric
            case .monoBody: return Typography.monoBody
            case .monoCaption: return Typography.monoCaption
            }
        }

        var tracking: CGFloat {
            switch self {
            case .eyebrow, .monoCaption:
                return 0.9
            default:
                return 0
            }
        }
    }

    static let canvas = Color(red: 0.930, green: 0.941, blue: 0.953)
    static let canvasAccent = Color(red: 0.887, green: 0.913, blue: 0.936)
    static let panel = Color(red: 0.979, green: 0.985, blue: 0.990)
    static let panelElevated = Color(red: 0.993, green: 0.996, blue: 0.999)
    static let panelStroke = Color(red: 0.769, green: 0.812, blue: 0.847)
    static let divider = Color(red: 0.847, green: 0.878, blue: 0.906)

    static let ink = Color(red: 0.078, green: 0.114, blue: 0.165)
    static let muted = Color(red: 0.354, green: 0.425, blue: 0.490)
    static let tertiaryText = Color(red: 0.492, green: 0.560, blue: 0.624)

    static let navy = Color(red: 0.086, green: 0.208, blue: 0.337)
    static let scienceBlue = Color(red: 0.118, green: 0.333, blue: 0.525)
    static let accent = Color(red: 0.776, green: 0.482, blue: 0.176)
    static let steel = Color(red: 0.887, green: 0.918, blue: 0.945)
    static let warm = Color(red: 0.961, green: 0.942, blue: 0.902)
    static let success = Color(red: 0.110, green: 0.541, blue: 0.349)
    static let ready = Color(red: 0.086, green: 0.447, blue: 0.682)
    static let processing = Color(red: 0.235, green: 0.420, blue: 0.812)
    static let warning = Color(red: 0.780, green: 0.463, blue: 0.125)
    static let critical = Color(red: 0.733, green: 0.227, blue: 0.227)

    static let hoverFill = Color.white.opacity(0.78)
    static let pressedFill = Color.black.opacity(0.08)
    static let disabledFill = Color(red: 0.945, green: 0.954, blue: 0.963)
    static let focusRing = accent.opacity(0.32)
    static let selectionRing = scienceBlue.opacity(0.28)
    static let panelShadow = Color.black.opacity(0.06)

    static let shellGradient = LinearGradient(
        colors: [
            canvas,
            canvasAccent.opacity(0.82),
            warm.opacity(0.56)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            navy,
            scienceBlue,
            Color(red: 0.170, green: 0.445, blue: 0.580)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func trackerText(_ style: TrackerTheme.TextStyle, color: Color = TrackerTheme.ink) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .foregroundStyle(color)
    }
}
