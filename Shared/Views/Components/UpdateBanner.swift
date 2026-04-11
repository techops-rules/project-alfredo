import SwiftUI

struct UpdateBanner: View {
    let updateService: UpdateService
    @Environment(\.theme) private var theme
    @State private var isVisible = false
    @State private var isHovering = false

    var body: some View {
        if updateService.hasUpdate, let version = updateService.availableVersion {
            HStack(spacing: 10) {
                // Pulse dot
                Circle()
                    .fill(ThemeManager.success)
                    .frame(width: 6, height: 6)
                    .shadow(color: ThemeManager.success.opacity(0.6), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("UPDATE READY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeManager.success)
                        .tracking(2)

                    Text("v\(version)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ThemeManager.textPrimary)

                    if let notes = updateService.releaseNotes {
                        Text(notes)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Apply button
                Button(action: { updateService.applyUpdate() }) {
                    Text("APPLY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeManager.background)
                        .tracking(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ThemeManager.success)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                // Dismiss
                Button(action: {
                    withAnimation(.easeOut(duration: 0.25)) {
                        updateService.dismiss()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeManager.textSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ThemeManager.surface)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial.opacity(0.6))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        ThemeManager.success.opacity(isHovering ? 0.5 : 0.25),
                        style: StrokeStyle(
                            lineWidth: theme.borderWidth,
                            dash: theme.borderStrokeDash
                        )
                    )
            )
            .shadow(color: ThemeManager.success.opacity(0.1), radius: 12, y: 4)
            .frame(maxWidth: 340)
            #if os(macOS)
            .onHover { isHovering = $0 }
            #endif
            .offset(y: isVisible ? 0 : -60)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.3)) {
                    isVisible = true
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
