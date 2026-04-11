import SwiftUI

// MARK: - Widget Identifier

enum WidgetID: String, CaseIterable, Identifiable {
    case clock = "CLOCK.SYS"
    case todayBar = "TODAY.EXE"
    case workTasks = "WORK.TODO"
    case lifeTasks = "LIFE.TODO"
    case habits = "HABITS.LOG"
    case calendar = "CALENDAR.DAT"
    case projects = "PROJECTS.DIR"
    case goals = "GOALS.CFG"
    case scratchpad = "SCRATCH.TXT"
    case stats = "STATS.BIN"
    case terminal = "CLAUDE.TTY"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .clock:      return "clock"
        case .todayBar:   return "chart.bar.fill"
        case .workTasks:  return "briefcase"
        case .lifeTasks:  return "heart"
        case .habits:     return "checkmark.circle"
        case .calendar:   return "calendar"
        case .projects:   return "folder"
        case .goals:      return "flag"
        case .scratchpad: return "note.text"
        case .stats:      return "chart.line.uptrend.xyaxis"
        case .terminal:   return "terminal"
        }
    }
}

// MARK: - Visibility State

@Observable
final class WidgetVisibility {
    var visible: Set<WidgetID>
    var order: [WidgetID]

    init() {
        let defaults = UserDefaults.standard
        if let savedHidden = defaults.array(forKey: "widgets.hidden") as? [String] {
            let hiddenIDs = Set(savedHidden.compactMap { WidgetID(rawValue: $0) })
            self.visible = Set(WidgetID.allCases).subtracting(hiddenIDs)
        } else {
            self.visible = Set(WidgetID.allCases)
        }

        if let savedOrder = defaults.array(forKey: "widgets.order") as? [String] {
            let ordered = savedOrder.compactMap { WidgetID(rawValue: $0) }
            // Append any new widgets not in saved order
            let remaining = WidgetID.allCases.filter { !ordered.contains($0) }
            self.order = ordered + remaining
        } else {
            self.order = WidgetID.allCases.map { $0 }
        }
    }

    func isVisible(_ id: WidgetID) -> Bool {
        visible.contains(id)
    }

    func toggle(_ id: WidgetID) {
        if visible.contains(id) {
            visible.remove(id)
        } else {
            visible.insert(id)
        }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        let hidden = WidgetID.allCases.filter { !visible.contains($0) }.map(\.rawValue)
        defaults.set(hidden, forKey: "widgets.hidden")
        defaults.set(order.map(\.rawValue), forKey: "widgets.order")
    }
}

// MARK: - Sidebar View

struct WidgetSidebar: View {
    @Bindable var visibility: WidgetVisibility
    @Binding var isExpanded: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                sidebarContent
                    .frame(width: 220)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Toggle tab
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            }) {
                VStack(spacing: 6) {
                    Image(systemName: isExpanded ? "sidebar.left" : "sidebar.right")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("WDG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(theme.accentFull)
                .frame(width: 32, height: 64)
                .background(ThemeManager.surface)
                .background(.ultraThinMaterial.opacity(0.3))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 8,
                        topTrailingRadius: 8
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 8,
                        topTrailingRadius: 8
                    )
                    .strokeBorder(theme.accentBorder, lineWidth: theme.borderWidth)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("WIDGETS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)
                    .tracking(3)

                Spacer()

                Text("\(visibility.visible.count)/\(WidgetID.allCases.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.accentHeaderBg)

            Divider()
                .background(theme.accentBorder)

            // Widget list
            List {
                ForEach(visibility.order) { widget in
                    widgetRow(widget)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    visibility.move(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
        }
        .background(ThemeManager.surface)
        .background(.ultraThinMaterial.opacity(0.3))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
            .strokeBorder(theme.accentBorder, style: StrokeStyle(
                lineWidth: theme.borderWidth,
                dash: theme.borderStrokeDash
            ))
        )
    }

    private func widgetRow(_ widget: WidgetID) -> some View {
        Button(action: { visibility.toggle(widget) }) {
            HStack(spacing: 8) {
                Image(systemName: widget.icon)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(visibility.isVisible(widget) ? theme.accentFull : ThemeManager.textSecondary.opacity(0.4))
                    .frame(width: 16)

                Text(widget.rawValue)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(visibility.isVisible(widget) ? ThemeManager.textPrimary : ThemeManager.textSecondary.opacity(0.4))
                    .lineLimit(1)

                Spacer()

                Image(systemName: visibility.isVisible(widget) ? "eye" : "eye.slash")
                    .font(.system(size: 9))
                    .foregroundColor(visibility.isVisible(widget) ? ThemeManager.success.opacity(0.7) : ThemeManager.textSecondary.opacity(0.3))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                visibility.isVisible(widget)
                    ? theme.accentTrack
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
