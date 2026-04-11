import SwiftUI

struct ProjectItem: Identifiable {
    let id = UUID()
    let name: String
    let percent: Int
    let status: String
    let target: String
}

struct ProjectsWidget: View {
    @Environment(\.theme) private var theme

    let projects: [ProjectItem] = [
        ProjectItem(name: "alfredo", percent: 15, status: "active", target: "May 2026"),
        ProjectItem(name: "Quote Tool v2", percent: 80, status: "active", target: "Apr 2026"),
        ProjectItem(name: "Home Lab", percent: 5, status: "paused", target: "TBD"),
    ]

    var body: some View {
        WidgetShell(title: "PROJECTS.DAT", badge: "\(projects.count)", zone: "right") {
            VStack(spacing: 12) {
                ForEach(projects) { project in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(project.name)
                                    .font(.system(size: theme.fontSize, weight: .medium, design: .monospaced))
                                    .foregroundColor(ThemeManager.textPrimary)

                                Text(project.status.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(project.status == "active" ? ThemeManager.success : ThemeManager.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        (project.status == "active" ? ThemeManager.success : ThemeManager.warning).opacity(0.15)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }

                            Text(project.target)
                                .font(.system(size: theme.fontSize - 2, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(project.percent)%")
                                .font(.system(size: theme.fontSize - 1, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeManager.textPrimary)
                            ProgressDots(percent: project.percent)
                        }
                    }
                }
            }
        }
    }
}
