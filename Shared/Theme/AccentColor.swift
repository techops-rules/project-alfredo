import SwiftUI

enum AccentColor: String, CaseIterable, Codable {
    case ice, coral, amber, green

    var color: Color {
        switch self {
        case .ice:   return Color(red: 0.380, green: 0.686, blue: 0.937)   // #61AFEF
        case .coral: return Color(red: 0.878, green: 0.424, blue: 0.459)   // #E06C75
        case .amber: return Color(red: 0.898, green: 0.753, blue: 0.482)   // #E5C07B
        case .green: return Color(red: 0.596, green: 0.765, blue: 0.475)   // #98C379
        }
    }

    var label: String {
        rawValue.uppercased()
    }
}
