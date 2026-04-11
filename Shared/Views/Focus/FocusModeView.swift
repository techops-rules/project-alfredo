import SwiftUI

struct FocusModeView: View {
    let task: AppTask
    @Bindable var engine: WhatNextEngine
    let onDone: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ThemeManager.background.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Task name
                Text(task.displayText)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundColor(ThemeManager.textEmphasis)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // Elapsed time (subtle)
                Text(engine.elapsedString)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)

                Spacer()

                // Buttons
                HStack(spacing: 24) {
                    Button {
                        engine.clearCurrent()
                        dismiss()
                    } label: {
                        Text("Switch")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(ThemeManager.textSecondary.opacity(0.3))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.clearCurrent()
                        onDone()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textEmphasis)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(ThemeManager.success.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(ThemeManager.success.opacity(0.4))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 60)
            }
        }
    }
}
