import SwiftUI

struct ThemeControlPanel: View {
    @Environment(\.theme) private var theme
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3)) { isOpen.toggle() }
            } label: {
                Text("THEME")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .tracking(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 12) {
                    // Accent color
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ACCENT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1)
                        HStack(spacing: 8) {
                            ForEach(AccentColor.allCases, id: \.self) { accent in
                                Button {
                                    theme.accent = accent
                                } label: {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 20, height: 20)
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

                    // Border style
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BORDER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1)
                        HStack(spacing: 6) {
                            ForEach(BorderStyle.allCases, id: \.self) { style in
                                Button {
                                    theme.borderStyle = style
                                } label: {
                                    Text(style.rawValue.prefix(4).uppercased())
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(theme.borderStyle == style ? ThemeManager.textEmphasis : ThemeManager.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(theme.borderStyle == style ? theme.accentBadge : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Border width
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WIDTH")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1)
                        HStack(spacing: 6) {
                            ForEach([CGFloat(1), 2, 3], id: \.self) { w in
                                Button {
                                    theme.borderWidth = w
                                } label: {
                                    Text("\(Int(w))px")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(theme.borderWidth == w ? ThemeManager.textEmphasis : ThemeManager.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(theme.borderWidth == w ? theme.accentBadge : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Font size
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FONT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1)
                        HStack(spacing: 6) {
                            ForEach([CGFloat(11), 13, 15], id: \.self) { s in
                                Button {
                                    var t = Transaction()
                                    t.disablesAnimations = true
                                    withTransaction(t) { theme.fontSize = s }
                                } label: {
                                    Text("\(Int(s))pt")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(theme.fontSize == s ? ThemeManager.textEmphasis : ThemeManager.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(theme.fontSize == s ? theme.accentBadge : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    #if os(macOS)
                    // Zoom (macOS only)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ZOOM")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1)
                        HStack(spacing: 6) {
                            ForEach([CGFloat(0.75), 1.0, 1.25], id: \.self) { z in
                                Button {
                                    theme.zoom = z
                                } label: {
                                    Text("\(Int(z * 100))%")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(theme.zoom == z ? ThemeManager.textEmphasis : ThemeManager.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(theme.zoom == z ? theme.accentBadge : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    #endif
                }
                .padding(12)
                .background(.ultraThinMaterial.opacity(0.5))
                .background(ThemeManager.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(theme.accentBorder, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
    }
}
