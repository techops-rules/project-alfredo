import SwiftUI

#if os(iOS)
struct AlfredoInputBar: View {
    @Environment(\.theme) private var theme
    @StateObject private var session = TerminalSession()
    @State private var showSheet = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(theme.accentBorder.opacity(0.4))
                .frame(height: 1)

            HStack(spacing: 8) {
                // TTY label
                Text("ALFREDO.TTY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull.opacity(0.5))
                    .tracking(1)

                // Prompt
                Text(">")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)

                // Input
                TerminalTextField(
                    text: $session.inputText,
                    placeholder: "talk to alfredo...",
                    onSubmit: { session.send() }
                )
                .frame(maxWidth: .infinity)
                .focused($isInputFocused)

                // Status dot
                Circle()
                    .fill(session.statusColor)
                    .frame(width: 6, height: 6)

                // Expand button
                Button {
                    showSheet = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10))
                        .foregroundColor(ThemeManager.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ThemeManager.background.opacity(0.95))
            .background(.ultraThinMaterial.opacity(0.8))
        }
        .sheet(isPresented: $showSheet) {
            AlfredoFullView(session: session)
                .environment(\.theme, ThemeManager.shared)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Full Terminal View (Sheet)

private struct AlfredoFullView: View {
    @ObservedObject var session: TerminalSession
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ALFREDO.TTY")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)
                    .tracking(2)

                Spacer()

                Text(session.statusBadge ?? "")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accentBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeManager.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.accentHeaderBg)

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(session.statusColor)
                    .frame(width: 5, height: 5)
                Text(session.connectionLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                Spacer()
                if !session.pendingCount.isEmpty {
                    Text(session.pendingCount)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ThemeManager.warning)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(ThemeManager.surface.opacity(0.4))

            // Output area
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.lines) { line in
                            terminalLine(line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: session.lines.count) { _, _ in
                    if let last = session.lines.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input area
            Divider().background(theme.accentBorder)

            HStack(spacing: 6) {
                Text(">")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)

                TerminalTextField(
                    text: $session.inputText,
                    placeholder: "talk to alfredo...",
                    onSubmit: { session.send() }
                )
                .frame(maxWidth: .infinity)

                Circle()
                    .fill(session.statusColor)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(ThemeManager.background.opacity(0.8))
        }
        .background(ThemeManager.background)
    }

    @ViewBuilder
    private func terminalLine(_ line: TerminalLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if line.isUser {
                Text(">")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)
            } else if line.isSystem {
                Text("#")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
            } else {
                Text(" ")
                    .font(.system(size: 11, design: .monospaced))
            }

            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(line.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
    }
}
#endif
