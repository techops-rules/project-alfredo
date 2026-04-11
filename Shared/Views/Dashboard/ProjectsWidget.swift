import SwiftUI

struct ProjectsWidget: View {
    @Environment(\.theme) private var theme
    @State private var selectedProject: Project?

    private let projectService = ProjectService.shared

    private var badgeView: AnyView? {
        let count = projectService.suggestedCount
        guard count > 0 else { return nil }
        return AnyView(
            HStack(spacing: 4) {
                Circle()
                    .fill(ThemeManager.shared.accentFull)
                    .frame(width: 5, height: 5)
                Text("\(count) new")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.shared.accentFull)
            }
        )
    }

    var body: some View {
        WidgetShell(
            title: "PROJECTS.DAT",
            badge: "\(projectService.activeProjects.count)",
            badgeView: badgeView,
            zone: "right"
        ) {
            VStack(spacing: 12) {
                ForEach(projectService.activeProjects) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        projectRow(project)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailSheet(project: project)
                .environment(\.theme, ThemeManager.shared)
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.system(size: theme.fontSize, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeManager.textPrimary)

                    Text(project.status.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(project.status == .active ? ThemeManager.success : ThemeManager.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (project.status == .active ? ThemeManager.success : ThemeManager.warning).opacity(0.15)
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
