import SwiftUI

struct WhatNextButton: View {
    let onTap: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                Text("What Next?")
                    .font(.system(size: theme.fontSize, weight: .medium, design: .monospaced))
            }
            .foregroundColor(ThemeManager.textEmphasis)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.accentBadge)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(theme.accentBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
