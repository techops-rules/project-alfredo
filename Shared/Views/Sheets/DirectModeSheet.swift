import SwiftUI

@MainActor
struct DirectModeSheet: View {
    @ObservedObject var session: DirectModeSessionService
    let surface: DirectModeSurface

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""

    init(
        session: DirectModeSessionService,
        surface: DirectModeSurface
    ) {
        self.session = session
        self.surface = surface
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if session.entries.isEmpty {
                            Text("Direct Mode is ready for schedule, task, and project questions.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(session.entries) { entry in
                                entryView(entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.entries.count) { _, _ in
                    if let last = session.entries.last {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let expiresAt = session.expiresAt, session.isActive {
                Text("session ends \(expiresAt.formatted(date: .omitted, time: .shortened)) unless it stays active")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider().background(theme.accentBorder)

            HStack(spacing: 10) {
                Button {
                    if session.isActive {
                        session.end(reason: "closed from app")
                    } else {
                        session.start(surface: surface, trigger: "manual launch")
                    }
                } label: {
                    Text(session.isActive ? "END" : "START")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(session.isActive ? ThemeManager.danger : theme.accentFull)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background((session.isActive ? ThemeManager.danger : theme.accentFull).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                TerminalTextField(
                    text: $inputText,
                    placeholder: "ask about tomorrow, projects, or what is on your plate...",
                    onSubmit: submit
                )
                .frame(maxWidth: .infinity)

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(theme.accentFull)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(ThemeManager.background.opacity(0.95))
        }
        .background(ThemeManager.background)
        .presentationBackground(ThemeManager.background)
        .onAppear {
            if !session.isActive {
                session.start(surface: surface, trigger: "manual launch")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DIRECT MODE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)
                    .tracking(2)
                Text("surface // \(surface.rawValue)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
            }

            Spacer()

            Text(session.state.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentFull)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
    }

    @ViewBuilder
    private func entryView(_ entry: DirectModeEntry) -> some View {
        let style = entryStyle(for: entry.role)

        HStack(alignment: .top, spacing: 8) {
            Text(style.prefix)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(style.color)

            Text(entry.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(style.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func submit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        session.handleTranscript(trimmed)
    }

    private func entryStyle(for role: DirectModeEntry.Role) -> (color: Color, prefix: String) {
        switch role {
        case .system:
            return (ThemeManager.textSecondary, "#")
        case .user:
            return (theme.accentFull, ">")
        case .assistant:
            return (ThemeManager.textPrimary, "A")
        }
    }
}
