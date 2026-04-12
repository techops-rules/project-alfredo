import SwiftUI

struct SettingsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var onOpenTerminal: (() -> Void)? = nil
    var onOpenDirectMode: (() -> Void)? = nil
    var onToggleWidget: ((WidgetID) -> Void)? = nil
    var widgetVisibility: WidgetVisibility = WidgetVisibility()

    var body: some View {
        VStack(spacing: 0) {
            // Handle + header
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ThemeManager.textSecondary.opacity(0.4))
                    .frame(width: 36, height: 4)

                HStack {
                    AsciiMascot(mood: .idle, color: theme.accentFull, size: 11)
                    Spacer()
                    Text("SETTINGS.CFG")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accentFull)
                        .tracking(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)

            Divider().background(theme.accentBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: - Terminal
                    if onOpenTerminal != nil || onOpenDirectMode != nil {
                        sectionHeader("QUICK LAUNCH")
                        if let onOpenDirectMode {
                            largeButton(
                                icon: "waveform.circle",
                                label: "Talk to Alfredo",
                                sublabel: "DIRECT MODE"
                            ) {
                                onOpenDirectMode()
                                dismiss()
                            }
                        }
                        if let onOpenTerminal {
                            largeButton(
                                icon: "terminal",
                                label: "Open Terminal",
                                sublabel: ">_ CLAUDE.TTY"
                            ) {
                                onOpenTerminal()
                                dismiss()
                            }
                        }
                        sectionDivider
                    }

                    // MARK: - Font size
                    sectionHeader("FONT SIZE")
                    VStack(spacing: 1) {
                        ForEach([
                            (CGFloat(11), "S", "Small"),
                            (CGFloat(13), "M", "Medium"),
                            (CGFloat(15), "L", "Large")
                        ], id: \.0) { size, label, name in
                            fontSizeRow(size: size, label: label, name: name)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    sectionDivider

                    // MARK: - Accent color
                    sectionHeader("ACCENT COLOR")
                    HStack(spacing: 12) {
                        ForEach(AccentColor.allCases, id: \.self) { accent in
                            Button {
                                theme.accent = accent
                            } label: {
                                VStack(spacing: 5) {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle().strokeBorder(
                                                theme.accent == accent ? Color.white : Color.clear,
                                                lineWidth: 2.5
                                            )
                                        )
                                        .shadow(
                                            color: theme.accent == accent ? accent.color.opacity(0.5) : .clear,
                                            radius: 6
                                        )
                                    Text(accent.rawValue.uppercased())
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(
                                            theme.accent == accent
                                                ? ThemeManager.textEmphasis
                                                : ThemeManager.textSecondary
                                        )
                                        .tracking(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    sectionDivider

                    // MARK: - Border style
                    sectionHeader("BORDER STYLE")
                    VStack(spacing: 1) {
                        ForEach(BorderChars.allCases, id: \.self) { chars in
                            borderCharRow(chars)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // Stroke + width inline
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("STROKE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                                .tracking(1)
                            HStack(spacing: 6) {
                                ForEach(BorderStyle.allCases, id: \.self) { style in
                                    chipButton(style.label.prefix(4).description,
                                               active: theme.borderStyle == style) {
                                        theme.borderStyle = style
                                    }
                                }
                            }
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("WIDTH")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                                .tracking(1)
                            HStack(spacing: 6) {
                                ForEach([CGFloat(1), 2, 3], id: \.self) { w in
                                    chipButton("\(Int(w))px", active: theme.borderWidth == w) {
                                        theme.borderWidth = w
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    sectionDivider

                    // MARK: - Widgets
                    if onToggleWidget != nil {
                        sectionHeader("WIDGETS")
                        VStack(spacing: 1) {
                            ForEach(WidgetID.allCases, id: \.self) { id in
                                widgetToggleRow(id)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        sectionDivider
                    }

                    // MARK: - Layout Preset
                    sectionHeader("LAYOUT")
                    layoutPresetSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    sectionDivider

                    // MARK: - Preview
                    sectionHeader("PREVIEW")
                    borderPreviewRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
        }
        .background(ThemeManager.background)
        .presentationBackground(ThemeManager.background)
    }

    // MARK: - Font size row

    private func fontSizeRow(size: CGFloat, label: String, name: String) -> some View {
        Button {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { theme.fontSize = size }
        } label: {
            HStack(spacing: 16) {
                // Size indicator
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.fontSize == size ? theme.accentFull : ThemeManager.textSecondary)
                    .frame(width: 20)

                // Sample text at actual size
                Text("The quick brown fox")
                    .font(.system(size: size, design: .monospaced))
                    .foregroundColor(theme.fontSize == size ? ThemeManager.textPrimary : ThemeManager.textSecondary)

                Spacer()

                // pt label + checkmark
                Text("\(Int(size))pt")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)

                if theme.fontSize == size {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.accentFull)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 16)
            .background(
                theme.fontSize == size
                    ? theme.accentBadge
                    : ThemeManager.textSecondary.opacity(0.05)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Border char row

    private func borderCharRow(_ chars: BorderChars) -> some View {
        Button {
            theme.borderChars = chars
        } label: {
            HStack(spacing: 16) {
                Text(chars.preview)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(
                        theme.borderChars == chars
                            ? theme.accentFull
                            : ThemeManager.textSecondary
                    )
                    .frame(width: 60, alignment: .leading)

                Text(chars.label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(
                        theme.borderChars == chars
                            ? ThemeManager.textPrimary
                            : ThemeManager.textSecondary
                    )
                    .tracking(1)

                Spacer()

                if theme.borderChars == chars {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.accentFull)
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 16)
            .background(
                theme.borderChars == chars
                    ? theme.accentBadge
                    : ThemeManager.textSecondary.opacity(0.05)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Widget toggle row

    private func widgetToggleRow(_ id: WidgetID) -> some View {
        Button {
            onToggleWidget?(id)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: widgetVisibility.isVisible(id) ? "checkmark.square" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(
                        widgetVisibility.isVisible(id) ? theme.accentFull : ThemeManager.textSecondary
                    )

                Text(id.rawValue)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)

                Spacer()
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 16)
            .background(ThemeManager.textSecondary.opacity(0.05))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Large button row

    private func largeButton(icon: String, label: String, sublabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(theme.accentFull)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeManager.textPrimary)
                    Text(sublabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeManager.textSecondary)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layout Presets

    private var layoutPresetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            Text("iPhone layout preset — controls widget order and sizing on both screens")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)

            let presets: [(String, String, String)] = [
                ("DASHBOARD", "dashboard", "Balanced view: weather, hotlist, calendar, tasks across two screens"),
                ("FOCUS", "focus", "Deep work: large task list, minimal distractions, calendar below"),
                ("MINIMAL", "minimal", "Essential only: clock, hotlist, weather. Hide everything else"),
                ("CUSTOM", "custom", "Your arrangement — toggle widgets above, adjust to taste"),
            ]
            #else
            Text("Mac layout preset — sets widget positions on the canvas")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)

            let presets: [(String, String, String)] = [
                ("COMMAND", "command", "Mission control: all widgets visible, organized by zone"),
                ("FOCUS", "focus", "Work tasks + terminal prominent, secondary widgets compact"),
                ("CLEAN", "clean", "Key widgets only: tasks, calendar, weather. Large and readable"),
                ("CUSTOM", "custom", "Drag and resize freely — your positions persist to iCloud"),
            ]
            #endif

            ForEach(presets, id: \.1) { (label, key, desc) in
                presetRow(label: label, key: key, description: desc)
            }
        }
    }

    @AppStorage("layout.preset") private var currentPreset: String = "dashboard"

    private func presetRow(label: String, key: String, description: String) -> some View {
        Button {
            currentPreset = key
            applyLayoutPreset(key)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(currentPreset == key ? theme.accentFull : ThemeManager.textSecondary.opacity(0.2))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(currentPreset == key ? ThemeManager.textEmphasis : ThemeManager.textSecondary)
                        .tracking(1)
                    Text(description)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary.opacity(0.6))
                        .lineLimit(2)
                }

                Spacer()

                if currentPreset == key {
                    Text("ACTIVE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accentFull)
                        .tracking(1)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(currentPreset == key ? theme.accentFull.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func applyLayoutPreset(_ key: String) {
        #if os(iOS)
        // iOS presets control widget visibility — the flow layout handles positioning
        switch key {
        case "dashboard":
            // Show all primary widgets
            setVisibility(show: [.weather, .hotlist, .calendar, .workTasks, .lifeTasks, .habits, .projects, .goals, .todayBar, .stats])
            setVisibility(hide: [.terminal, .scratchpad, .deferredTasks, .waitingTasks, .longTermTasks])
        case "focus":
            // Work tasks prominent, minimal distractions
            setVisibility(show: [.weather, .workTasks, .calendar, .hotlist, .todayBar])
            setVisibility(hide: [.lifeTasks, .habits, .projects, .goals, .stats, .terminal, .scratchpad, .deferredTasks, .waitingTasks, .longTermTasks])
        case "minimal":
            // Just the essentials
            setVisibility(show: [.weather, .hotlist, .todayBar])
            setVisibility(hide: [.workTasks, .lifeTasks, .habits, .calendar, .projects, .goals, .stats, .terminal, .scratchpad, .deferredTasks, .waitingTasks, .longTermTasks])
        case "custom":
            break // user controls visibility manually
        default:
            break
        }
        #else
        // macOS presets set widget visibility — positions are free-form
        switch key {
        case "command":
            setVisibility(show: WidgetID.allCases)
        case "focus":
            setVisibility(show: [.workTasks, .terminal, .calendar, .hotlist, .weather, .todayBar, .clock])
            setVisibility(hide: [.lifeTasks, .habits, .projects, .goals, .stats, .scratchpad, .deferredTasks, .waitingTasks, .longTermTasks, .funFact])
        case "clean":
            setVisibility(show: [.workTasks, .lifeTasks, .calendar, .weather, .todayBar, .clock])
            setVisibility(hide: [.habits, .projects, .goals, .stats, .terminal, .scratchpad, .hotlist, .deferredTasks, .waitingTasks, .longTermTasks, .funFact])
        case "custom":
            break
        default:
            break
        }
        #endif
    }

    private func setVisibility(show widgets: [WidgetID]) {
        for w in widgets {
            if !widgetVisibility.isVisible(w) {
                onToggleWidget?(w)
            }
        }
    }

    private func setVisibility(hide widgets: [WidgetID]) {
        for w in widgets {
            if widgetVisibility.isVisible(w) {
                onToggleWidget?(w)
            }
        }
    }

    // MARK: - Chip button

    private func chipButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(active ? ThemeManager.textEmphasis : ThemeManager.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? theme.accentBadge : ThemeManager.textSecondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(ThemeManager.textSecondary)
            .tracking(2)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(theme.accentBorder)
            .frame(height: 0.5)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
    }

    // MARK: - Border preview

    private var borderPreviewRow: some View {
        let bc = theme.borderChars
        let inner = "  alfredo v0.51  "
        let w = inner.count
        let top = bc.tl + String(repeating: bc.h, count: w) + bc.tr
        let mid = bc.v + inner + bc.v
        let bot = bc.bl + String(repeating: bc.h, count: w) + bc.br

        return Text(top + "\n" + mid + "\n" + bot)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(theme.accentFull)
            .lineSpacing(2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(theme.accentHeaderBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
