import SwiftUI

struct EmailReplySheet: View {
    let task: AppTask
    let messageId: String
    let subject: String

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var thread: EmailThread?
    @State private var draftBody: String = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var sendError: String?
    @State private var didSend = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(ThemeManager.textSecondary.opacity(0.2))

            if isLoading {
                loadingView
            } else {
                content
            }
        }
        .background(ThemeManager.background)
        .task { await loadThread() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("EMAIL REPLY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .tracking(2)

                Text(subject)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                    .lineLimit(2)

                if let from = thread?.messages.last?.from {
                    Text("from \(from)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeManager.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().tint(theme.accentFull)
            Text("fetching thread...")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
            Spacer()
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Thread context (last 2 messages)
                    if let messages = thread?.messages.suffix(2), !messages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("THREAD")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                                .tracking(1.5)

                            ForEach(messages) { msg in
                                ThreadMessageRow(message: msg)
                            }
                        }
                    }

                    // Related task
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RELATED TASK")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1.5)

                        Text(task.displayText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(theme.accentFull)
                    }

                    // Editable reply
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("YOUR REPLY")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                                .tracking(1.5)
                            Spacer()
                            Text("\(draftBody.count) chars")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                        }

                        TextEditor(text: $draftBody)
                            .font(.system(size: theme.fontSize, design: .monospaced))
                            .foregroundColor(ThemeManager.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(ThemeManager.textSecondary.opacity(0.06))
                            .cornerRadius(4)
                            .frame(minHeight: 140)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(ThemeManager.textSecondary.opacity(0.2), lineWidth: 1)
                            )
                    }

                    if let err = sendError {
                        Text(err)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.danger)
                    }
                }
                .padding(16)
            }

            Divider().background(ThemeManager.textSecondary.opacity(0.2))
            actions
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Discard")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            if didSend {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("Sent")
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(ThemeManager.success)
            } else {
                Button {
                    Task { await sendReply() }
                } label: {
                    HStack(spacing: 4) {
                        if isSending {
                            ProgressView().scaleEffect(0.7).tint(.black)
                        } else {
                            Image(systemName: "paperplane")
                        }
                        Text(isSending ? "Sending..." : "Send Reply")
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? ThemeManager.textSecondary.opacity(0.3)
                                : theme.accentFull)
                    .foregroundColor(.black)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
        .padding(16)
    }

    // MARK: - Data loading

    private func loadThread() async {
        isLoading = true
        defer { isLoading = false }

        let fetched = await EmailService.shared.fetchThread(messageId: messageId)
        await MainActor.run {
            thread = fetched
            draftBody = generateDraft(from: fetched)
        }
    }

    private func sendReply() async {
        guard !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        sendError = nil

        let success = await EmailService.shared.sendReply(
            messageId: messageId,
            threadId: thread?.threadId,
            body: draftBody
        )

        await MainActor.run {
            isSending = false
            if success {
                didSend = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            } else {
                sendError = "Failed to send. Check connection and try again."
            }
        }
    }

    // MARK: - Draft generation

    private func generateDraft(from thread: EmailThread?) -> String {
        guard let lastMsg = thread?.messages.last else {
            return "Hi,\n\nRe: \(task.displayText)\n\n"
        }
        let greeting = lastMsg.from.components(separatedBy: " ").first.map { "Hi \($0)," } ?? "Hi,"
        return "\(greeting)\n\n\n\nBest,\nTodd"
    }
}

// MARK: - Thread message row

struct ThreadMessageRow: View {
    let message: EmailMessage
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.from)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                Spacer()
                Text(message.dateString)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
            }
            Text(message.snippet)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
                .lineLimit(3)
        }
        .padding(8)
        .background(ThemeManager.textSecondary.opacity(0.06))
        .cornerRadius(4)
    }
}

// MARK: - Models

struct EmailThread {
    let threadId: String
    let messages: [EmailMessage]
}

struct EmailMessage: Identifiable {
    let id: String
    let from: String
    let snippet: String
    let dateString: String
    let fullBody: String?
}
