import SwiftUI

struct BreadcrumbBar: View {
    @Bindable var engine: WhatNextEngine
    let tasks: [AppTask]
    let onStartTask: (AppTask) -> Void
    var onSync: (() -> Void)? = nil

    @Environment(\.theme) private var theme
    @State private var showingSuggestion = false
    @State private var suggestedTask: AppTask?
    @State private var isSyncing = false

    private let monitor = ConnectionMonitor.shared

    @State private var showDiagnostics = false

    var body: some View {
        HStack(spacing: 12) {
            if let task = engine.currentTask {
                // Active task
                HStack(spacing: 8) {
                    Text("Working on:")
                        .font(.system(size: theme.fontSize - 1, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                    Text(task.displayText)
                        .font(.system(size: theme.fontSize, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeManager.textEmphasis)
                        .lineLimit(1)
                    Text(engine.elapsedString)
                        .font(.system(size: theme.fontSize - 1, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }
            } else {
                // Connector statuses
                HStack(spacing: 14) {
                    // Claude / Pi status — tappable for diagnostics
                    Button {
                        if monitor.piStatus == .connected {
                            showDiagnostics = false
                        } else {
                            showDiagnostics.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusDotColor(monitor.piStatus))
                                .frame(width: 6, height: 6)
                            Text("Claude")
                                .font(.system(size: theme.fontSize, design: .monospaced))
                                .foregroundColor(statusColor(monitor.piStatus))
                        }
                    }
                    .buttonStyle(.plain)

                    // Other connectors
                    ForEach(monitor.connectors.filter { $0.name != "Pi" }, id: \.name) { connector in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusDotColor(connector.status))
                                .frame(width: 6, height: 6)
                            Text(connector.name)
                                .font(.system(size: theme.fontSize, design: .monospaced))
                                .foregroundColor(statusColor(connector.status))
                        }
                    }
                }

                // Diagnostics popover / inline
                if showDiagnostics {
                    Text("|")
                        .font(.system(size: theme.fontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary.opacity(0.3))

                    if let error = monitor.piError {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error)
                                .font(.system(size: theme.fontSize - 1, design: .monospaced))
                                .foregroundColor(ThemeManager.danger)
                                .lineLimit(1)
                            if let suggestion = monitor.piSuggestion {
                                Text("\u{2192} \(suggestion)")
                                    .font(.system(size: theme.fontSize - 1, design: .monospaced))
                                    .foregroundColor(ThemeManager.warning)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Button {
                        monitor.checkPi()
                    } label: {
                        Text("retry")
                            .font(.system(size: theme.fontSize - 1, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.accentFull)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(theme.accentFull.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Sync button
            Button {
                guard !isSyncing else { return }
                isSyncing = true
                monitor.checkAll()
                onSync?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isSyncing = false
                }
            } label: {
                Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSyncing ? theme.accentFull : ThemeManager.textSecondary)
                    .rotationEffect(.degrees(isSyncing ? 360 : 0))
                    .animation(isSyncing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isSyncing)
            }
            .buttonStyle(.plain)

            WhatNextButton {
                if let next = engine.suggestNext(from: tasks) {
                    suggestedTask = next
                    showingSuggestion = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ThemeManager.background)
        .overlay(
            Rectangle()
                .fill(theme.accentBorder)
                .frame(height: 1),
            alignment: .bottom
        )
        .animation(.none, value: monitor.connectors)
        .sheet(isPresented: $showingSuggestion) {
            if let task = suggestedTask {
                SuggestionSheet(task: task, engine: engine, onStart: {
                    engine.startTask(task)
                    onStartTask(task)
                    showingSuggestion = false
                }, onSkip: {
                    engine.skip(task)
                    if let next = engine.suggestNext(from: tasks) {
                        suggestedTask = next
                    } else {
                        showingSuggestion = false
                    }
                })
            }
        }
    }

    private func statusColor(_ status: ConnectionStatus) -> Color {
        switch status {
        case .connected: return ThemeManager.success.opacity(0.7)
        case .checking: return ThemeManager.warning.opacity(0.6)
        case .disconnected: return ThemeManager.textSecondary.opacity(0.35)
        case .notConfigured: return ThemeManager.textSecondary.opacity(0.2)
        }
    }

    private func statusDotColor(_ status: ConnectionStatus) -> Color {
        switch status {
        case .connected: return ThemeManager.success
        case .checking: return ThemeManager.warning
        case .disconnected: return ThemeManager.danger.opacity(0.6)
        case .notConfigured: return ThemeManager.textSecondary.opacity(0.3)
        }
    }
}

private struct SuggestionSheet: View {
    let task: AppTask
    let engine: WhatNextEngine
    let onStart: () -> Void
    let onSkip: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("SUGGESTED NEXT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
                .tracking(2)

            Text(task.displayText)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(ThemeManager.textEmphasis)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Skip") { onSkip() }
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ThemeManager.textSecondary.opacity(0.3)))

                Button("Start") { onStart() }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textEmphasis)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(theme.accentBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 200)
        .background(ThemeManager.background)
    }
}
