import SwiftUI

enum BorderStyle: String, CaseIterable, Codable {
    case solid, dashed, dotted, double

    var label: String { rawValue.uppercased() }
}

enum BorderChars: String, CaseIterable, Codable {
    case line      // ┌─┐│└─┘
    case round     // ╭─╮│╰─╯
    case heavy     // ┏━┓┃┗━┛
    case double    // ╔═╗║╚═╝
    case ascii     // +-+|+-+
    case block     // ▛▀▜█▙▄▟
    case dots      // ·····
    case stars     // *···*

    var label: String { rawValue.uppercased() }

    var tl: String { // top-left
        switch self {
        case .line:   return "┌"
        case .round:  return "╭"
        case .heavy:  return "┏"
        case .double: return "╔"
        case .ascii:  return "+"
        case .block:  return "▛"
        case .dots:   return "·"
        case .stars:  return "*"
        }
    }
    var tr: String { // top-right
        switch self {
        case .line:   return "┐"
        case .round:  return "╮"
        case .heavy:  return "┓"
        case .double: return "╗"
        case .ascii:  return "+"
        case .block:  return "▜"
        case .dots:   return "·"
        case .stars:  return "*"
        }
    }
    var bl: String { // bottom-left
        switch self {
        case .line:   return "└"
        case .round:  return "╰"
        case .heavy:  return "┗"
        case .double: return "╚"
        case .ascii:  return "+"
        case .block:  return "▙"
        case .dots:   return "·"
        case .stars:  return "*"
        }
    }
    var br: String { // bottom-right
        switch self {
        case .line:   return "┘"
        case .round:  return "╯"
        case .heavy:  return "┛"
        case .double: return "╝"
        case .ascii:  return "+"
        case .block:  return "▟"
        case .dots:   return "·"
        case .stars:  return "*"
        }
    }
    var h: String { // horizontal
        switch self {
        case .line:   return "─"
        case .round:  return "─"
        case .heavy:  return "━"
        case .double: return "═"
        case .ascii:  return "-"
        case .block:  return "▀"
        case .dots:   return "·"
        case .stars:  return "·"
        }
    }
    var v: String { // vertical
        switch self {
        case .line:   return "│"
        case .round:  return "│"
        case .heavy:  return "┃"
        case .double: return "║"
        case .ascii:  return "|"
        case .block:  return "█"
        case .dots:   return "·"
        case .stars:  return "*"
        }
    }

    /// Preview string for picker: "╭──╮"
    var preview: String {
        "\(tl)\(h)\(h)\(tr)"
    }
}

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var accent: AccentColor {
        didSet { save() }
    }
    var borderStyle: BorderStyle {
        didSet { save() }
    }
    var borderChars: BorderChars {
        didSet { save() }
    }
    var borderWidth: CGFloat {
        didSet { save() }
    }
    var fontSize: CGFloat {
        didSet { save() }
    }
    var zoom: CGFloat {
        didSet { save() }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.accent = AccentColor(rawValue: defaults.string(forKey: "theme.accent") ?? "") ?? .ice
        self.borderStyle = BorderStyle(rawValue: defaults.string(forKey: "theme.borderStyle") ?? "") ?? .solid
        self.borderChars = BorderChars(rawValue: defaults.string(forKey: "theme.borderChars") ?? "") ?? .round
        self.borderWidth = defaults.object(forKey: "theme.borderWidth") as? CGFloat ?? 1
        self.fontSize = defaults.object(forKey: "theme.fontSize") as? CGFloat ?? 13
        self.zoom = defaults.object(forKey: "theme.zoom") as? CGFloat ?? 1.0
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(accent.rawValue, forKey: "theme.accent")
        defaults.set(borderStyle.rawValue, forKey: "theme.borderStyle")
        defaults.set(borderChars.rawValue, forKey: "theme.borderChars")
        defaults.set(borderWidth, forKey: "theme.borderWidth")
        defaults.set(fontSize, forKey: "theme.fontSize")
        defaults.set(zoom, forKey: "theme.zoom")
    }

    // MARK: - Colors

    static let background = Color(red: 0.031, green: 0.055, blue: 0.094)        // #080E18
    static let surface = Color(red: 0.031, green: 0.055, blue: 0.094).opacity(0.76)
    static let textPrimary = Color(red: 0.671, green: 0.698, blue: 0.749)       // #ABB2BF
    static let textSecondary = Color(red: 0.361, green: 0.388, blue: 0.439)     // #5C6370
    static let textEmphasis = Color(red: 0.910, green: 0.918, blue: 0.929)      // #E8EAED
    static let success = Color(red: 0.596, green: 0.765, blue: 0.475)           // #98C379
    static let warning = Color(red: 0.898, green: 0.753, blue: 0.482)           // #E5C07B
    static let danger = Color(red: 0.878, green: 0.424, blue: 0.459)            // #E06C75

    // MARK: - Accent Opacities

    var accentFull: Color { accent.color }
    var accentBorder: Color { accent.color.opacity(0.28) }
    var accentBadge: Color { accent.color.opacity(0.18) }
    var accentTrack: Color { accent.color.opacity(0.12) }
    var accentHeaderBg: Color { accent.color.opacity(0.05) }
    var accentGrid: Color { accent.color.opacity(0.035) }

    // MARK: - Fonts

    var bodyFont: Font { .system(size: fontSize, design: .monospaced) }
    var headerFont: Font { .system(size: fontSize + 1, weight: .bold, design: .monospaced) }
    var captionFont: Font { .system(size: fontSize - 2, design: .monospaced) }
    var clockFont: Font { .system(size: 42, weight: .bold, design: .monospaced) }
    var statFont: Font { .system(size: 24, weight: .bold, design: .monospaced) }

    // MARK: - Border

    var borderStrokeDash: [CGFloat] {
        switch borderStyle {
        case .solid:  return []
        case .dashed: return [8, 4]
        case .dotted: return [2, 3]
        case .double: return []
        }
    }
}

// MARK: - Environment Key

private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue = ThemeManager.shared
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

// MARK: - Grid Background

struct GridBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 80
            let color = theme.accentGrid

            for x in stride(from: 0, through: size.width, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
        }
    }
}
