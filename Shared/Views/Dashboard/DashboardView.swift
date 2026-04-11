import SwiftUI

struct DashboardView: View {
    @Environment(\.theme) private var theme
    @State private var taskBoard = TaskBoardService()
    @State private var scratchpadService = ScratchpadService()
    @State private var whatNext = WhatNextEngine()
    @State private var habits: [Habit] = []
    @State private var goals: [Goal] = []
    @State private var canvasOffset: CGPoint = .zero
    @State private var showFocusMode = false
    @State private var widgetVisibility = WidgetVisibility()
    @State private var sidebarExpanded = false
    @StateObject private var layoutManager = WidgetLayoutManager()
    private let calendarService = CalendarService.shared
    private let updateService = UpdateService.shared

    // Zoom
    @State private var canvasScale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0

    // Edit mode (iOS)
    @State private var isEditMode = false

    // iOS bottom sheets
    @State private var showSettingsSheet = false
    @State private var showWidgetSheet = false

    // Minimap auto-hide
    @State private var minimapVisible = false
    @State private var minimapHideTask: Task<Void, Never>?

    private let worldSize = CGSize(width: 2800, height: 1200)

    // Platform-specific edit mode: macOS always allows drag/resize, iOS requires edit mode
    private var widgetsEditable: Bool {
        #if os(iOS)
        return isEditMode
        #else
        return true
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                ThemeManager.background.ignoresSafeArea()
                GridBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    // Breadcrumb bar (fixed)
                    BreadcrumbBar(
                        engine: whatNext,
                        tasks: taskBoard.todayTasks,
                        onStartTask: { _ in },
                        onSync: { syncAll() }
                    )

                    // Canvas with zoom
                    ZStack {
                        InfiniteCanvas(worldSize: worldSize, offset: $canvasOffset) {
                            ZStack(alignment: .topLeading) {
                                canvasWidgets
                            }
                        }
                        .scaleEffect(canvasScale)

                        #if os(iOS)
                        // Tap to exit edit mode
                        if isEditMode {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isEditMode = false
                                    }
                                }
                                .allowsHitTesting(true)
                                .zIndex(-1)
                        }
                        #endif
                    }
                    #if os(iOS)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                canvasScale = min(max(baseScale * scale, 0.5), 2.0)
                            }
                            .onEnded { _ in
                                baseScale = canvasScale
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                guard !isEditMode else { return }
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isEditMode = true
                                }
                            }
                    )
                    #endif
                }

                // Fixed overlays
                overlays(geo: geo)

                #if os(iOS)
                // Edit mode banner
                if isEditMode {
                    VStack {
                        Spacer()
                        editModeBanner
                    }
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                #endif
            }
        }
        .onAppear { loadData() }
        .onChange(of: canvasOffset) { _, _ in
            flashMinimap()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFocusMode) {
            if let task = whatNext.currentTask {
                FocusModeView(task: task, engine: whatNext, onDone: {
                    taskBoard.reload()
                    showFocusMode = false
                })
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            HamburgerMenu(onOpenTerminal: {
                showSettingsSheet = false
                showTerminal()
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWidgetSheet) {
            WidgetSidebar(
                visibility: widgetVisibility,
                isExpanded: .constant(true)
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        #else
        .sheet(isPresented: $showFocusMode) {
            if let task = whatNext.currentTask {
                FocusModeView(task: task, engine: whatNext, onDone: {
                    taskBoard.reload()
                    showFocusMode = false
                })
            }
        }
        #endif
    }

    // MARK: - Canvas Widgets

    @ViewBuilder
    private var canvasWidgets: some View {
        // Primary zone
        if widgetVisibility.isVisible(.clock) {
            DraggableWidgetContainer(
                widgetId: "clock",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("clock"),
                isEditMode: widgetsEditable
            ) {
                WidgetShell(title: "CLOCK.SYS", zone: "primary") {
                    ClockWidget()
                }
            }
            .transition(.opacity)
        }

        if widgetVisibility.isVisible(.todayBar) {
            DraggableWidgetContainer(
                widgetId: "todayBar",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("todayBar"),
                isEditMode: widgetsEditable
            ) {
                WidgetShell(title: "TODAY.EXE", zone: "primary") {
                    TodayBarWidget(
                        tasksDone: taskBoard.todayDoneCount,
                        tasksTotal: taskBoard.todayTotalCount,
                        habitsDone: habits.filter(\.isDoneToday).count,
                        habitsTotal: habits.count,
                        focusHours: Double(whatNext.elapsedMinutes) / 60.0,
                        eventsLeft: CalendarEvent.sampleEvents.filter { $0.startTime > Date() }.count
                    )
                }
            }
            .transition(.opacity)
        }

        if widgetVisibility.isVisible(.workTasks) {
            DraggableWidgetContainer(
                widgetId: "workTasks",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("workTasks"),
                isEditMode: widgetsEditable
            ) {
                TaskListWidget(
                    title: "WORK.TODO",
                    tasks: taskBoard.workTasks,
                    onToggle: { taskBoard.toggleTask($0) },
                    onTapTask: { whatNext.startTask($0) }
                )
            }
            .transition(.opacity)
        }

        if widgetVisibility.isVisible(.lifeTasks) {
            DraggableWidgetContainer(
                widgetId: "lifeTasks",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("lifeTasks"),
                isEditMode: widgetsEditable
            ) {
                TaskListWidget(
                    title: "LIFE.TODO",
                    tasks: taskBoard.personalTasks,
                    onToggle: { taskBoard.toggleTask($0) },
                    onTapTask: { whatNext.startTask($0) }
                )
            }
            .transition(.opacity)
        }

        if widgetVisibility.isVisible(.habits) {
            DraggableWidgetContainer(
                widgetId: "habits",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("habits"),
                isEditMode: widgetsEditable
            ) {
                HabitWidget(habits: $habits)
            }
            .transition(.opacity)
        }

        if widgetVisibility.isVisible(.calendar) {
            DraggableWidgetContainer(
                widgetId: "calendar",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("calendar"),
                isEditMode: widgetsEditable
            ) {
                CalendarWidget(events: calendarService.events.isEmpty ? CalendarEvent.sampleEvents : calendarService.events)
            }
            .transition(.opacity)
        }

        // Right zone
        if widgetVisibility.isVisible(.projects) {
            DraggableWidgetContainer(
                widgetId: "projects",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("projects"),
                isEditMode: widgetsEditable
            ) {
                ProjectsWidget()
            }
            .transition(.opacity)
        }

        if widgetVisibility.isVisible(.goals) {
            DraggableWidgetContainer(
                widgetId: "goals",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("goals"),
                isEditMode: widgetsEditable
            ) {
                GoalsWidget(goals: goals)
            }
            .transition(.opacity)
        }

        if widgetVisibility.isVisible(.scratchpad) {
            DraggableWidgetContainer(
                widgetId: "scratchpad",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("scratchpad"),
                isEditMode: widgetsEditable
            ) {
                ScratchpadWidget(
                    lines: scratchpadService.scratchpad.lines,
                    onAddLine: { scratchpadService.addLine($0) }
                )
            }
            .transition(.opacity)
        }

        // Bottom zone
        // Terminal widget (bottom left)
        if widgetVisibility.isVisible(.terminal) {
            DraggableWidgetContainer(
                widgetId: "terminal",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("terminal"),
                isEditMode: widgetsEditable
            ) {
                TerminalWidget()
            }
            .transition(.opacity)
        }
                if widgetVisibility.isVisible(.stats) {
            DraggableWidgetContainer(
                widgetId: "stats",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("stats"),
                isEditMode: widgetsEditable
            ) {
                StatsWidget()
            }
            .transition(.opacity)
        }

        // Edge hints
        edgeHint("PROJECTS >", x: 1260, y: 300, vertical: true)
        edgeHint("STATS v", x: 400, y: 780, vertical: false)
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlays(geo: GeometryProxy) -> some View {
        #if os(iOS)
        // iOS: menu top-left + toolbar at bottom
        VStack {
            // Menu (top-left) + connection status (top-right)
            HStack {
                HamburgerMenu(onOpenTerminal: {
                    showTerminal()
                })
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Spacer()

            HStack {
                // Widget visibility toggle
                Button {
                    showWidgetSheet = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Spacer()

                // Minimap — auto-hides when not panning
                if minimapVisible {
                    MinimapView(
                        worldSize: worldSize,
                        viewportSize: geo.size,
                        offset: canvasOffset
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer()

                // Terminal quick-launch
                Button {
                    showTerminal()
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        #else
        // macOS: inline overlays
        ZStack {
            // Minimap (bottom-left) — auto-hides when not panning
            if minimapVisible {
                HStack {
                    VStack {
                        Spacer()
                        MinimapView(
                            worldSize: worldSize,
                            viewportSize: geo.size,
                            offset: canvasOffset
                        )
                    }
                    Spacer()
                }
                .padding(12)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Hamburger menu (top-left) + connection status (top-right)
            HStack {
                VStack {
                    HamburgerMenu(onOpenTerminal: {
                        showTerminal()
                    })
                    Spacer()
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(height: 0)
        .allowsHitTesting(true)

        // Widget sidebar (left edge overlay)
        VStack {
            Spacer().frame(height: 60) // Below breadcrumb
            HStack {
                WidgetSidebar(
                    visibility: widgetVisibility,
                    isExpanded: $sidebarExpanded
                )
                Spacer()
            }
            Spacer()
        }

        // Update banner (top-right)
        VStack {
            HStack {
                Spacer()
                UpdateBanner(updateService: updateService)
            }
            .padding(.top, 48)
            .padding(.trailing, 16)
            Spacer()
        }
        #endif
    }

    // MARK: - Edit Mode Banner (iOS)

    #if os(iOS)
    private var editModeBanner: some View {
        HStack(spacing: 8) {
            Text("\u{2807}")
                .font(.system(size: 14, design: .monospaced))
            Text("EDIT MODE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
            Text("— drag to move, corners to resize")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
            Spacer()
            Button("Done") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isEditMode = false
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(ThemeManager.shared.accentFull)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }
    #endif

    // MARK: - Default Layouts

    private func defaultLayout(_ widgetId: String) -> WidgetLayoutState {
        #if os(iOS)
        return iOSDefaultLayout(widgetId)
        #else
        return macOSDefaultLayout(widgetId)
        #endif
    }

    private func macOSDefaultLayout(_ widgetId: String) -> WidgetLayoutState {
        switch widgetId {
        case "clock":      return WidgetLayoutState(position: CGPoint(x: 40, y: 20), size: CGSize(width: 340, height: 110))
        case "todayBar":   return WidgetLayoutState(position: CGPoint(x: 400, y: 20), size: CGSize(width: 840, height: 110))
        case "workTasks":  return WidgetLayoutState(position: CGPoint(x: 40, y: 150), size: CGSize(width: 360, height: 340))
        case "lifeTasks":  return WidgetLayoutState(position: CGPoint(x: 420, y: 150), size: CGSize(width: 360, height: 340))
        case "habits":     return WidgetLayoutState(position: CGPoint(x: 800, y: 150), size: CGSize(width: 440, height: 340))
        case "calendar":   return WidgetLayoutState(position: CGPoint(x: 40, y: 510), size: CGSize(width: 560, height: 270))
        case "projects":   return WidgetLayoutState(position: CGPoint(x: 1320, y: 150), size: CGSize(width: 500, height: 320))
        case "goals":      return WidgetLayoutState(position: CGPoint(x: 1320, y: 490), size: CGSize(width: 500, height: 260))
        case "scratchpad":return WidgetLayoutState(position: CGPoint(x: 1840, y: 150), size: CGSize(width: 420, height: 600))
        case "stats":      return WidgetLayoutState(position: CGPoint(x: 40, y: 820), size: CGSize(width: 700, height: 280))
        case "terminal":   return WidgetLayoutState(position: CGPoint(x: 800, y: 820), size: CGSize(width: 460, height: 280))
        default:           return WidgetLayoutState(position: .zero, size: CGSize(width: 300, height: 200))
        }
    }

    private func iOSDefaultLayout(_ widgetId: String) -> WidgetLayoutState {
        // From design brief Section 7 — compact layout for phone screens
        switch widgetId {
        case "clock":      return WidgetLayoutState(position: CGPoint(x: 0, y: 0), size: CGSize(width: 300, height: 100))
        case "todayBar":   return WidgetLayoutState(position: CGPoint(x: 320, y: 0), size: CGSize(width: 300, height: 100))
        case "workTasks":  return WidgetLayoutState(position: CGPoint(x: 0, y: 120), size: CGSize(width: 300, height: 260))
        case "lifeTasks":  return WidgetLayoutState(position: CGPoint(x: 320, y: 120), size: CGSize(width: 300, height: 200))
        case "calendar":   return WidgetLayoutState(position: CGPoint(x: 0, y: 400), size: CGSize(width: 300, height: 260))
        case "habits":     return WidgetLayoutState(position: CGPoint(x: 0, y: 680), size: CGSize(width: 300, height: 260))
        case "scratchpad":return WidgetLayoutState(position: CGPoint(x: 320, y: 340), size: CGSize(width: 300, height: 320))
        case "goals":      return WidgetLayoutState(position: CGPoint(x: 640, y: 0), size: CGSize(width: 300, height: 260))
        case "projects":   return WidgetLayoutState(position: CGPoint(x: 640, y: 280), size: CGSize(width: 300, height: 260))
        case "stats":      return WidgetLayoutState(position: CGPoint(x: 640, y: 560), size: CGSize(width: 300, height: 260))
        case "terminal":   return WidgetLayoutState(position: CGPoint(x: 0, y: 960), size: CGSize(width: 340, height: 280))
        default:           return WidgetLayoutState(position: .zero, size: CGSize(width: 300, height: 200))
        }
    }

    // MARK: - Minimap Auto-Hide

    private func flashMinimap() {
        // Show minimap
        if !minimapVisible {
            withAnimation(.easeOut(duration: 0.2)) {
                minimapVisible = true
            }
        }

        // Cancel previous hide timer
        minimapHideTask?.cancel()

        // Hide after 2 seconds of no movement
        minimapHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) {
                minimapVisible = false
            }
        }
    }

    // MARK: - Terminal

    private func showTerminal() {
        // Ensure terminal widget is visible
        if !widgetVisibility.isVisible(.terminal) {
            widgetVisibility.toggle(.terminal)
        }
        // Pan canvas to terminal widget position
        let termLayout = defaultLayout("terminal")
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            canvasOffset = CGPoint(
                x: -termLayout.position.x + 40,
                y: -termLayout.position.y + 60
            )
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        taskBoard.reload()
        scratchpadService.reload()

        let icloud = iCloudService.shared
        if let habitsContent = icloud.readFile(at: icloud.habitsURL) {
            habits = MarkdownParser.parseHabits(habitsContent)
        }
        if let goalsContent = icloud.readFile(at: icloud.goalsURL) {
            goals = MarkdownParser.parseGoals(goalsContent)
        }
    }

    private func syncAll() {
        loadData()
        calendarService.refresh()
        ConnectionMonitor.shared.checkAll()
    }

    private func edgeHint(_ text: String, x: CGFloat, y: CGFloat, vertical: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(ThemeManager.textSecondary.opacity(0.4))
            .tracking(3)
            .rotationEffect(vertical ? .degrees(-90) : .zero)
            .position(x: x, y: y)
    }
}
