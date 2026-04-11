import SwiftUI

struct QuickCaptureField: View {
    let placeholder: String
    let onSubmit: (String) -> Void

    @Environment(\.theme) private var theme
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(size: theme.fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentFull)

            TerminalTextField(
                text: $text,
                placeholder: placeholder,
                onSubmit: {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSubmit(text)
                    text = ""
                }
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ThemeManager.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(theme.accentBorder, lineWidth: 1)
        )
        .onTapGesture { /* focus handled by TerminalTextField */ }
    }
}
