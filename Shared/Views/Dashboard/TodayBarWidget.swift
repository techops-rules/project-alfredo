import SwiftUI

struct TodayBarWidget: View {
    let tasksDone: Int
    let tasksTotal: Int
    let habitsDone: Int
    let habitsTotal: Int
    let focusHours: Double
    let eventsLeft: Int

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            statItem(value: "\(tasksDone)/\(tasksTotal)", label: "TASKS")
            divider
            statItem(value: "\(habitsDone)/\(habitsTotal)", label: "HABITS")
            divider
            statItem(value: String(format: "%.1f", focusHours), label: "FOCUS HRS")
            divider
            statItem(value: "\(eventsLeft)", label: "EVENTS LEFT")
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(ThemeManager.textEmphasis)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(ThemeManager.textSecondary.opacity(0.2))
            .frame(width: 1, height: 40)
    }
}
