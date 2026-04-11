import SwiftUI

struct WidgetShell<Content: View>: View {
    let title: String
    var badge: String? = nil
    var zone: String? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme
    @State private var isCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCollapsed.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accentFull)
                        .frame(width: 12)

                    Text(title)
                        .font(.system(size: theme.fontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accentFull)
                        .tracking(2)

                    if let badge {
                        Text(badge)
                            .font(.system(size: theme.fontSize - 2, design: .monospaced))
                            .foregroundColor(theme.accentFull)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(theme.accentBadge)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    if let zone {
                        Text(zone)
                            .font(.system(size: theme.fontSize - 3, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary.opacity(0.5))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.accentHeaderBg)
            }
            .buttonStyle(.plain)

            // Content
            if !isCollapsed {
                content()
                    .padding(12)
            }
        }
        .background(.ultraThinMaterial.opacity(0.3))
        .background(ThemeManager.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(theme.accentBorder, style: StrokeStyle(
                    lineWidth: theme.borderWidth,
                    dash: theme.borderStrokeDash
                ))
        )
        .overlay(
            AsciiBorderOverlay(chars: theme.borderChars, color: theme.accentBorder)
        )
    }
}

// MARK: - ASCII Border Overlay

struct AsciiBorderOverlay: View {
    let chars: BorderChars
    let color: Color

    private let charSize: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Corners
            cornerChar(chars.tl)
                .position(x: charSize / 2, y: charSize / 2)
            cornerChar(chars.tr)
                .position(x: w - charSize / 2, y: charSize / 2)
            cornerChar(chars.bl)
                .position(x: charSize / 2, y: h - charSize / 2)
            cornerChar(chars.br)
                .position(x: w - charSize / 2, y: h - charSize / 2)

            // Top edge characters (spaced)
            let hCount = max(0, Int((w - charSize * 3) / (charSize * 1.2)))
            if hCount > 0 {
                let spacing = (w - charSize * 2) / CGFloat(hCount + 1)
                ForEach(0..<hCount, id: \.self) { i in
                    edgeChar(chars.h)
                        .position(x: charSize + spacing * CGFloat(i + 1), y: charSize / 2 - 1)
                }
                ForEach(0..<hCount, id: \.self) { i in
                    edgeChar(chars.h)
                        .position(x: charSize + spacing * CGFloat(i + 1), y: h - charSize / 2 + 1)
                }
            }

            // Side edge characters (spaced)
            let vCount = max(0, Int((h - charSize * 3) / (charSize * 1.5)))
            if vCount > 0 {
                let spacing = (h - charSize * 2) / CGFloat(vCount + 1)
                ForEach(0..<vCount, id: \.self) { i in
                    edgeChar(chars.v)
                        .position(x: charSize / 2 - 1, y: charSize + spacing * CGFloat(i + 1))
                }
                ForEach(0..<vCount, id: \.self) { i in
                    edgeChar(chars.v)
                        .position(x: w - charSize / 2 + 1, y: charSize + spacing * CGFloat(i + 1))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerChar(_ ch: String) -> some View {
        Text(ch)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(color.opacity(0.7))
    }

    private func edgeChar(_ ch: String) -> some View {
        Text(ch)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(color.opacity(0.35))
    }
}
