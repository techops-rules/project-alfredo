import SwiftUI

struct HamburgerMenu: View {
    @Environment(\.theme) private var theme
    @State private var isOpen = false

    var onOpenTerminal: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Trigger button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isOpen.toggle()
                }
            } label: {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(ThemeManager.textSecondary)
                            .frame(width: 14, height: 1.5)
                    }
                }
                .frame(width: 32, height: 28)
                .background(.ultraThinMaterial.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            if isOpen {
                menuContent
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }
        }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            menuHeader("SETTINGS.CFG")

            // Terminal quick-launch
            if let onOpenTerminal {
                Button(action: {
                    onOpenTerminal()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isOpen = false
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10, design: .monospaced))
                        Text("OPEN TERMINAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                        Spacer()
                        Text(">_")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                    }
                    .foregroundColor(ThemeManager.textPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(theme.accentTrack)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                menuDivider
            }

            // Accent
            menuSection("ACCENT") {
                HStack(spacing: 8) {
                    ForEach(AccentColor.allCases, id: \.self) { accent in
                        Button {
                            theme.accent = accent
                        } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().strokeBorder(
                                        theme.accent == accent ? Color.white : Color.clear,
                                        lineWidth: 2
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            menuDivider

            // Border characters
            menuSection("BORDER CHARS") {
                VStack(alignment: .leading, spacing: 4) {
                    let columns = [GridItem(.adaptive(minimum: 70), spacing: 4)]
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(BorderChars.allCases, id: \.self) { chars in
                            Button {
                                theme.borderChars = chars
                            } label: {
                                VStack(spacing: 2) {
                                    Text(chars.preview)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(
                                            theme.borderChars == chars
                                                ? ThemeManager.textEmphasis
                                                : ThemeManager.textSecondary
                                        )
                                    Text(chars.label)
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(
                                            theme.borderChars == chars
                                                ? theme.accentFull
                                                : ThemeManager.textSecondary.opacity(0.5)
                                        )
                                        .tracking(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    theme.borderChars == chars
                                        ? theme.accentBadge
                                        : ThemeManager.background.opacity(0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(
                                            theme.borderChars == chars
                                                ? theme.accentBorder
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            menuDivider

            // Border style (line rendering)
            menuSection("STROKE") {
                HStack(spacing: 6) {
                    ForEach(BorderStyle.allCases, id: \.self) { style in
                        Button {
                            theme.borderStyle = style
                        } label: {
                            Text(style.label.prefix(4))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(
                                    theme.borderStyle == style
                                        ? ThemeManager.textEmphasis
                                        : ThemeManager.textSecondary
                                )
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    theme.borderStyle == style
                                        ? theme.accentBadge
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            menuDivider

            // Width
            menuSection("WIDTH") {
                HStack(spacing: 6) {
                    ForEach([CGFloat(1), 2, 3], id: \.self) { w in
                        Button {
                            theme.borderWidth = w
                        } label: {
                            Text("\(Int(w))px")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(
                                    theme.borderWidth == w
                                        ? ThemeManager.textEmphasis
                                        : ThemeManager.textSecondary
                                )
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    theme.borderWidth == w
                                        ? theme.accentBadge
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            menuDivider

            // Font size
            menuSection("FONT") {
                HStack(spacing: 6) {
                    ForEach([CGFloat(11), 13, 15], id: \.self) { s in
                        Button {
                            theme.fontSize = s
                        } label: {
                            Text("\(Int(s))pt")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(
                                    theme.fontSize == s
                                        ? ThemeManager.textEmphasis
                                        : ThemeManager.textSecondary
                                )
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    theme.fontSize == s
                                        ? theme.accentBadge
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            #if os(macOS)
            menuDivider

            // Zoom
            menuSection("ZOOM") {
                HStack(spacing: 6) {
                    ForEach([CGFloat(0.75), 1.0, 1.25], id: \.self) { z in
                        Button {
                            theme.zoom = z
                        } label: {
                            Text("\(Int(z * 100))%")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(
                                    theme.zoom == z
                                        ? ThemeManager.textEmphasis
                                        : ThemeManager.textSecondary
                                )
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    theme.zoom == z
                                        ? theme.accentBadge
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            #endif

            // Live preview
            menuDivider
            borderPreview
        }
        .padding(14)
        .frame(width: 260)
        .background(.ultraThinMaterial.opacity(0.6))
        .background(ThemeManager.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.accentBorder, style: StrokeStyle(
                    lineWidth: theme.borderWidth,
                    dash: theme.borderStrokeDash
                ))
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func menuHeader(_ text: String) -> some View {
        HStack {
            AsciiMascot(mood: .idle, color: theme.accentFull, size: 9)
            Spacer()
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentFull)
                .tracking(2)
        }
    }

    private func menuSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
                .tracking(1)
            content()
        }
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(theme.accentBorder)
            .frame(height: 0.5)
    }

    private var borderPreview: some View {
        let bc = theme.borderChars
        let inner = " preview "
        let w = inner.count
        let top = bc.tl + String(repeating: bc.h, count: w) + bc.tr
        let mid = bc.v + inner + bc.v
        let bot = bc.bl + String(repeating: bc.h, count: w) + bc.br

        return Text(top + "\n" + mid + "\n" + bot)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(theme.accentFull)
            .lineSpacing(0)
            .frame(maxWidth: .infinity)
    }
}
