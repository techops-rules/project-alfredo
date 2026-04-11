import SwiftUI

struct ProjectsWidget: View {
    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics
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
                    .font(.system(size: metrics.captionFontSize, weight: .bold, design: .monospaced))
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
            VStack(spacing: metrics.sectionSpacing) {
                ForEach(projectService.activeProjects.prefix(metrics.secondaryListLimit)) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        projectRow(project)
                    }
                    .buttonStyle(.plain)
                }

                if projectService.activeProjects.count > metrics.secondaryListLimit {
                    Text("+ \(projectService.activeProjects.count - metrics.secondaryListLimit) more projects")
                        .font(.system(size: metrics.captionFontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .font(.system(size: metrics.bodyFontSize, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeManager.textPrimary)
                        .lineLimit(1)

                    if !metrics.isCompact {
                        Text(project.status.rawValue.uppercased())
                            .font(.system(size: metrics.captionFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(project.status == .active ? ThemeManager.success : ThemeManager.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (project.status == .active ? ThemeManager.success : ThemeManager.warning).opacity(0.15)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(project.target)
                    .font(.system(size: metrics.captionFontSize, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(project.percent)%")
                    .font(.system(size: metrics.bodyFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                ProgressDots(percent: project.percent)
            }
        }
    }
}
