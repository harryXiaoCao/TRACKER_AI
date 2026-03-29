import SwiftUI

enum TrackerTheme {
    static let canvas = Color(red: 0.956, green: 0.945, blue: 0.918)
    static let panel = Color(red: 0.984, green: 0.976, blue: 0.957)
    static let panelStroke = Color(red: 0.843, green: 0.808, blue: 0.749)
    static let ink = Color(red: 0.071, green: 0.129, blue: 0.196)
    static let muted = Color(red: 0.373, green: 0.447, blue: 0.514)
    static let navy = Color(red: 0.090, green: 0.204, blue: 0.294)
    static let accent = Color(red: 0.663, green: 0.357, blue: 0.204)
    static let steel = Color(red: 0.894, green: 0.922, blue: 0.941)
    static let warm = Color(red: 0.965, green: 0.937, blue: 0.890)
    static let success = Color(red: 0.149, green: 0.561, blue: 0.310)
    static let warning = Color(red: 0.792, green: 0.412, blue: 0.086)
    static let critical = Color(red: 0.694, green: 0.208, blue: 0.192)

    static let heroGradient = LinearGradient(
        colors: [navy, Color(red: 0.153, green: 0.314, blue: 0.416), accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
