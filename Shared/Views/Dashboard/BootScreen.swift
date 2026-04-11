import SwiftUI

struct BootScreen: View {
    let onComplete: () -> Void

    @Environment(\.theme) private var theme
    @State private var lines: [BootLine] = []
    @State private var progress: Double = 0
    @State private var phase: BootPhase = .banner
    @State private var showCursor = true

    // Static boot lines (connection status lines are appended dynamically)
    private static let bootSequencePre: [(String, Double, BootLineStyle)] = [
        ("ALFREDO SYSTEM v0.1.0",                        0.00, .header),
        ("(c) 2025 \u{2014} terminal dashboard engine",  0.00, .dim),
        ("",                                             0.05, .dim),
        ("BIOS ... OK",                                  0.08, .normal),
        ("MEM  ... 64K conventional, 512K extended",     0.10, .normal),
        ("",                                             0.12, .dim),
        ("[SYS] Loading kernel modules",                 0.14, .system),
        ("  icloud.driver     loaded",                   0.18, .success),
        ("  markdown.parser   loaded",                   0.22, .success),
        ("  theme.engine      loaded",                   0.26, .success),
        ("  canvas.physics    loaded",                   0.30, .success),
        ("",                                             0.32, .dim),
        ("[SVC] Initializing services",                  0.34, .system),
        ("  TaskBoardService  ... init",                 0.38, .normal),
        ("  ScratchpadService ... init",                 0.42, .normal),
        ("  WhatNextEngine    ... init",                 0.46, .normal),
        ("  WidgetVisibility  ... init",                 0.50, .normal),
        ("  UpdateService     ... init",                 0.54, .normal),
        ("",                                             0.56, .dim),
        ("[DAT] Loading user data",                      0.58, .system),
        ("  habits.md         read OK",                  0.62, .success),
        ("  goals.md          read OK",                  0.66, .success),
        ("  tasks/work.md     read OK",                  0.70, .success),
        ("  tasks/life.md     read OK",                  0.74, .success),
        ("  scratchpad.md     read OK",                  0.78, .success),
    ]

    private static let bootSequencePost: [(String, Double, BootLineStyle)] = [
        ("[GFX] Mounting widgets to canvas",             0.90, .system),
        ("  10 widgets registered",                      0.92, .normal),
        ("  canvas: 2800x1200 world",                    0.94, .normal),
        ("  viewport: ready",                            0.96, .normal),
    ]

    var body: some View {
        ZStack {
            ThemeManager.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                // Mascot
                HStack {
                    Spacer()
                    AsciiMascot(mood: progress < 1.0 ? .loading : .happy, color: theme.accentFull, size: 13)
                    Spacer()
                }
                .padding(.bottom, 16)

                // Boot log
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                bootLineView(line)
                                    .id(idx)
                            }

                            // Cursor
                            if progress < 1.0 {
                                Text(showCursor ? "█" : " ")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(theme.accentFull)
                                    .id("cursor")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 40)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: lines.count) {
                        withAnimation {
                            proxy.scrollTo("cursor", anchor: .bottom)
                        }
                    }
                }

                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    asciiProgressBar(progress: progress, width: 40)
                        .padding(.horizontal, 40)

                    Text(String(format: "  %3.0f%%", progress * 100))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accentFull)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 12)

                Spacer()
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .onAppear { startBoot() }
    }

    // MARK: - Boot Line View

    private func bootLineView(_ line: BootLine) -> some View {
        Text(line.text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(colorFor(line.style))
            .transition(.opacity)
    }

    private func colorFor(_ style: BootLineStyle) -> Color {
        switch style {
        case .header:  return ThemeManager.textEmphasis
        case .system:  return theme.accentFull
        case .normal:  return ThemeManager.textPrimary
        case .success: return ThemeManager.success
        case .dim:     return ThemeManager.textSecondary.opacity(0.5)
        case .accent:  return theme.accentFull
        }
    }

    // MARK: - ASCII Progress Bar

    private func asciiProgressBar(progress: Double, width: Int) -> some View {
        let filled = Int(Double(width) * min(progress, 1.0))
        let empty = width - filled
        let bc = theme.borderChars

        let bar = bc.v
            + String(repeating: "█", count: max(0, filled - 1))
            + (filled > 0 ? "▓" : "")
            + String(repeating: "░", count: max(0, empty))
            + bc.v

        let topLine = bc.tl + String(repeating: bc.h, count: width) + bc.tr
        let bottomLine = bc.bl + String(repeating: bc.h, count: width) + bc.br
        let content = topLine + "\n" + bar + "\n" + bottomLine

        return Text(content)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(theme.accentFull)
            .lineSpacing(0)
    }

    // MARK: - Boot Sequence

    private func startBoot() {
        // Cursor blink
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            showCursor.toggle()
        }

        let totalDuration: Double = 2.2 // seconds for full boot (slightly longer for connection check)

        // Phase 1: Pre-connection lines
        let preSequence = Self.bootSequencePre
        for entry in preSequence {
            let delay = entry.1 * totalDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.05)) {
                    lines.append(BootLine(text: entry.0, style: entry.2))
                    progress = entry.1
                }
            }
        }

        // Phase 2: Connection status (at ~0.80 mark)
        let connectionDelay = 0.80 * totalDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionDelay) {
            withAnimation(.easeOut(duration: 0.05)) {
                lines.append(BootLine(text: "", style: .dim))
                lines.append(BootLine(text: "[NET] Checking connections", style: .system))
                progress = 0.82
            }
            probeConnections(totalDuration: totalDuration)
        }
    }

    private func probeConnections(totalDuration: Double) {
        let monitor = ConnectionMonitor.shared
        let piHost = UserDefaults.standard.string(forKey: "terminal.piHost") ?? ""

        // Show Pi status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.05)) {
                if piHost.isEmpty {
                    lines.append(BootLine(text: "  pi bridge       not configured", style: .dim))
                } else {
                    lines.append(BootLine(text: "  pi bridge       probing \(piHost)...", style: .normal))
                }
                progress = 0.84
            }
        }

        // Check Pi connection result (monitor may have already checked)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.05)) {
                if piHost.isEmpty {
                    // already shown above
                } else if monitor.isConnected {
                    lines.append(BootLine(text: "  pi bridge       \u{2714} connected", style: .success))
                } else {
                    lines.append(BootLine(text: "  pi bridge       \u{2716} offline (cached mode)", style: .dim))
                }

                // iCloud status
                let icloud = iCloudService.shared
                if icloud.isUsingiCloud {
                    lines.append(BootLine(text: "  icloud sync     \u{2714} active", style: .success))
                } else {
                    lines.append(BootLine(text: "  icloud sync     \u{2716} local only", style: .dim))
                }

                // Cached terminal data
                let cached = TerminalCache.shared.load()
                if !cached.lines.isEmpty || !cached.pendingMessages.isEmpty {
                    let msg = "  terminal cache  \(cached.lines.count) lines, \(cached.pendingMessages.count) queued"
                    lines.append(BootLine(text: msg, style: .normal))
                }

                progress = 0.88
            }

            // Phase 3: Post-connection lines
            let postSequence = Self.bootSequencePost
            for entry in postSequence {
                let delay = (entry.1 - 0.88) * totalDuration
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, delay)) {
                    withAnimation(.easeOut(duration: 0.05)) {
                        lines.append(BootLine(text: entry.0, style: entry.2))
                        progress = entry.1
                    }
                }
            }

            // Finish
            let finishDelay = (1.0 - 0.88) * totalDuration + 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + finishDelay) {
                withAnimation(.easeOut(duration: 0.05)) {
                    lines.append(BootLine(text: "", style: .dim))
                    if monitor.isConnected {
                        lines.append(BootLine(text: "ALL SYSTEMS NOMINAL", style: .header))
                    } else {
                        lines.append(BootLine(text: "OFFLINE MODE \u{2014} CACHED DATA LOADED", style: .header))
                    }
                    lines.append(BootLine(text: "Launching dashboard ...", style: .accent))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        progress = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onComplete()
                    }
                }
            }
        }
    }
}

// MARK: - Models

private enum BootPhase {
    case banner, loading, done
}

private enum BootLineStyle {
    case header, system, normal, success, dim, accent
}

private struct BootLine {
    let text: String
    let style: BootLineStyle
}
