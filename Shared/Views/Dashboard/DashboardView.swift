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
    private let prepService = MeetingPrepService.shared
    private let weatherService = WeatherService.shared

    // Zoom
    @State private var canvasScale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0

    // Edit mode — widgets can only be moved/resized when true (both iOS + macOS)
    @State private var isEditMode = false

    // Context-aware layout
    @State private var contextNow = Date()
    private let contextTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum AppContext { case workFocus, night, weekend, personal }

    private var appContext: AppContext {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: contextNow)
        let weekday = cal.component(.weekday, from: contextNow)
        let isWeekend = weekday == 1 || weekday == 7
        let isNight = hour >= 20 || hour < 7
        let isWork = !isWeekend && hour >= 9 && hour < 18
        if isWeekend { return .weekend }
        if isNight   { return .night }
        if isWork    { return .workFocus }
        return .personal
    }

    /// Show weekend schedule on Sat, Sun, or Friday night (6pm+)
    private var isWeekendCalendarMode: Bool {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: contextNow)
        let hour = cal.component(.hour, from: contextNow)
        return weekday == 1 || weekday == 7 || (weekday == 6 && hour >= 18)
    }

    // iOS bottom sheets
    @State private var showSettingsSheet = false
    @State private var showWidgetSheet = false
    @State private var showDirectModeSheet = false

    // Email reply deep link
    @State private var emailReplyTask: AppTask?

    // Minimap auto-hide
    @State private var minimapVisible = false
    @State private var minimapHideTask: Task<Void, Never>?

    // Widgets are only movable/resizable while edit mode is on (both platforms).
    private var widgetsEditable: Bool {
        isEditMode
    }

    private var worldSize: CGSize {
        #if os(iOS)
        return iOSWorldSize
        #else
        return CGSize(width: 2800, height: 1200)
        #endif
    }

    private var appContextLabel: String {
        switch appContext {
        case .workFocus: return "Work"
        case .night: return "Night"
        case .weekend: return "Weekend"
        case .personal: return "Personal"
        }
    }

    private var chromeSummary: String? {
        if let current = whatNext.currentTask {
            return "NOW // \(current.text)"
        }
        if let next = whatNext.suggestNext(from: taskBoard.todayTasks) {
            return "NEXT // \(next.text)"
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                ThemeManager.background.ignoresSafeArea()
                GridBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top chrome (fixed)
                    #if os(iOS)
                    iOSTopChrome(
                        modeLabel: appContextLabel,
                        summary: chromeSummary,
                        isEditMode: isEditMode,
                        onSync: { syncAll() },
                        onHamburger: { showSettingsSheet = true }
                    )
                    #else
                    BreadcrumbBar(
                        engine: whatNext,
                        tasks: taskBoard.todayTasks,
                        onStartTask: { _ in },
                        onSync: { syncAll() },
                        isEditMode: $isEditMode
                    )
                    #endif

                    // Canvas with zoom
                    ZStack {
                        InfiniteCanvas(
                            worldSize: worldSize,
                            offset: $canvasOffset,
                            isPanningEnabled: !isEditMode
                        ) {
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
                                guard !isEditMode else { return }
                                canvasScale = min(max(baseScale * scale, 0.5), 2.0)
                            }
                            .onEnded { _ in
                                guard !isEditMode else { return }
                                baseScale = canvasScale
                            }
                    , including: isEditMode ? .subviews : .gesture
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
        .onReceive(contextTimer) { _ in contextNow = Date() }
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
            SettingsSheet(
                onOpenTerminal: {
                    showSettingsSheet = false
                    showTerminal()
                },
                onOpenDirectMode: {
                    showSettingsSheet = false
                    showDirectModeSheet = true
                },
                onToggleWidget: { widgetVisibility.toggle($0) },
                widgetVisibility: widgetVisibility,
                isEditMode: $isEditMode
            )
            .environment(\.theme, ThemeManager.shared)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDirectModeSheet) {
            DirectModeSheet(session: DirectModeSessionService.shared, surface: .iOS)
                .environment(\.theme, ThemeManager.shared)
                .presentationDetents([.medium, .large])
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
        #if os(macOS)
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheet(
                onOpenTerminal: {
                    showSettingsSheet = false
                    showTerminal()
                },
                onOpenDirectMode: {
                    showSettingsSheet = false
                    showDirectModeSheet = true
                },
                onToggleWidget: { widgetVisibility.toggle($0) },
                widgetVisibility: widgetVisibility,
                isEditMode: $isEditMode
            )
            .environment(\.theme, ThemeManager.shared)
            .frame(minWidth: 360, minHeight: 600)
        }
        .sheet(isPresented: $showDirectModeSheet) {
            DirectModeSheet(session: DirectModeSessionService.shared, surface: .macOS)
                .environment(\.theme, ThemeManager.shared)
                .frame(minWidth: 560, minHeight: 520)
        }
        #endif
        .sheet(item: $emailReplyTask) { task in
            if case .email(let messageId, let subject) = task.source {
                EmailReplySheet(task: task, messageId: messageId, subject: subject)
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
        }
    }

    // MARK: - Task Navigation

    private func handleTaskNavigation(_ task: AppTask) {
        switch task.source {
        case .email:
            emailReplyTask = task
        case .calendarEvent(let eventId, _):
            // Find the matching CalendarEvent and show its briefing sheet
            // CalendarWidget handles its own sheet; post a notification the widget can pick up
            NotificationCenter.default.post(
                name: .showEventBriefing,
                object: nil,
                userInfo: ["eventId": eventId]
            )
        case .manual, .unresolvable:
            break // flash handled in TodoItemView
        }
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
                    onToggleSubtask: { taskBoard.toggleSubtask($0) },
                    onTapTask: { whatNext.startTask($0) },
                    onNavigate: { handleTaskNavigation($0) }
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
                    onToggleSubtask: { taskBoard.toggleSubtask($0) },
                    onTapTask: { whatNext.startTask($0) },
                    onNavigate: { handleTaskNavigation($0) }
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
                CalendarWidget(
                    events: calendarService.events.isEmpty ? CalendarEvent.sampleEvents : calendarService.events,
                    weekendMode: isWeekendCalendarMode
                )
            }
            .transition(.opacity)
        }

        if widgetVisibility.isVisible(.hotlist) {
            DraggableWidgetContainer(
                widgetId: "hotlist",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("hotlist"),
                isEditMode: widgetsEditable
            ) {
                HotlistWidget(
                    tasks: taskBoard.todayTasks,
                    events: calendarService.events.isEmpty ? CalendarEvent.sampleEvents : calendarService.events,
                    onToggle: { taskBoard.toggleTask($0) }
                )
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
        // Weather widget
        if widgetVisibility.isVisible(.weather) {
            DraggableWidgetContainer(
                widgetId: "weather",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("weather"),
                isEditMode: widgetsEditable
            ) {
                WeatherHero(weather: weatherService.current)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .transition(.opacity)
        }

        // Terminal widget (macOS only on canvas; iOS uses pinned AlfredoInputBar)
        #if os(macOS)
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
        #endif

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

        // Deferred tasks
        if widgetVisibility.isVisible(.deferredTasks) {
            DraggableWidgetContainer(
                widgetId: "deferredTasks",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("deferredTasks"),
                isEditMode: widgetsEditable
            ) {
                TaskListWidget(
                    title: "DEFERRED.TODO",
                    tasks: taskBoard.deferredTasks,
                    onToggle: { taskBoard.toggleTask($0) },
                    onToggleSubtask: { taskBoard.toggleSubtask($0) },
                    onTapTask: { whatNext.startTask($0) },
                    onNavigate: { handleTaskNavigation($0) }
                )
            }
            .transition(.opacity)
        }

        // Waiting tasks
        if widgetVisibility.isVisible(.waitingTasks) {
            DraggableWidgetContainer(
                widgetId: "waitingTasks",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("waitingTasks"),
                isEditMode: widgetsEditable
            ) {
                TaskListWidget(
                    title: "WAITING.TODO",
                    tasks: taskBoard.waitingTasks,
                    onToggle: { taskBoard.toggleTask($0) },
                    onToggleSubtask: { taskBoard.toggleSubtask($0) },
                    onTapTask: { whatNext.startTask($0) },
                    onNavigate: { handleTaskNavigation($0) }
                )
            }
            .transition(.opacity)
        }

        // Long-term tasks
        if widgetVisibility.isVisible(.longTermTasks) {
            DraggableWidgetContainer(
                widgetId: "longTermTasks",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("longTermTasks"),
                isEditMode: widgetsEditable
            ) {
                TaskListWidget(
                    title: "LONGTERM.TODO",
                    tasks: taskBoard.longTermTasks,
                    onToggle: { taskBoard.toggleTask($0) },
                    onToggleSubtask: { taskBoard.toggleSubtask($0) },
                    onTapTask: { whatNext.startTask($0) },
                    onNavigate: { handleTaskNavigation($0) }
                )
            }
            .transition(.opacity)
        }

        // Fun fact
        if widgetVisibility.isVisible(.funFact) {
            DraggableWidgetContainer(
                widgetId: "funFact",
                layoutManager: layoutManager,
                defaultLayout: defaultLayout("funFact"),
                isEditMode: widgetsEditable
            ) {
                FunFactWidget()
            }
            .transition(.opacity)
        }

        // Edge hints (macOS only)
        #if os(macOS)
        edgeHint("PROJECTS >", x: 1260, y: 300, vertical: true)
        edgeHint("STATS v", x: 400, y: 780, vertical: false)
        #endif
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlays(geo: GeometryProxy) -> some View {
        #if os(iOS)
        // iOS: pinned ALFREDO.TTY input bar at bottom
        VStack(spacing: 0) {
            Spacer()
            AlfredoInputBar()
        }
        .ignoresSafeArea(.keyboard)
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

            // Settings button top-left
            HStack {
                VStack {
                    Button { showSettingsSheet = true } label: {
                        VStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(ThemeManager.textSecondary)
                                    .frame(width: 14, height: 1.5)
                            }
                        }
                        .frame(width: 32, height: 28)
                        .background(.ultraThinMaterial.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
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
        case "clock":         return WidgetLayoutState(position: CGPoint(x: 40, y: 20), size: CGSize(width: 340, height: 110))
        case "todayBar":      return WidgetLayoutState(position: CGPoint(x: 400, y: 20), size: CGSize(width: 840, height: 110))
        case "weather":       return WidgetLayoutState(position: CGPoint(x: 1260, y: 20), size: CGSize(width: 500, height: 200))
        case "workTasks":     return WidgetLayoutState(position: CGPoint(x: 40, y: 150), size: CGSize(width: 360, height: 340))
        case "lifeTasks":     return WidgetLayoutState(position: CGPoint(x: 420, y: 150), size: CGSize(width: 360, height: 340))
        case "habits":        return WidgetLayoutState(position: CGPoint(x: 800, y: 150), size: CGSize(width: 440, height: 340))
        case "calendar":      return WidgetLayoutState(position: CGPoint(x: 40, y: 510), size: CGSize(width: 560, height: 270))
        case "hotlist":       return WidgetLayoutState(position: CGPoint(x: 620, y: 510), size: CGSize(width: 620, height: 270))
        case "projects":      return WidgetLayoutState(position: CGPoint(x: 1320, y: 240), size: CGSize(width: 500, height: 320))
        case "goals":         return WidgetLayoutState(position: CGPoint(x: 1320, y: 580), size: CGSize(width: 500, height: 260))
        case "scratchpad":    return WidgetLayoutState(position: CGPoint(x: 1840, y: 150), size: CGSize(width: 420, height: 600))
        case "stats":         return WidgetLayoutState(position: CGPoint(x: 40, y: 820), size: CGSize(width: 700, height: 280))
        case "terminal":      return WidgetLayoutState(position: CGPoint(x: 800, y: 820), size: CGSize(width: 460, height: 280))
        case "deferredTasks": return WidgetLayoutState(position: CGPoint(x: 1840, y: 770), size: CGSize(width: 420, height: 200))
        case "waitingTasks":  return WidgetLayoutState(position: CGPoint(x: 1840, y: 980), size: CGSize(width: 420, height: 200))
        case "longTermTasks": return WidgetLayoutState(position: CGPoint(x: 1320, y: 860), size: CGSize(width: 500, height: 200))
        case "funFact":       return WidgetLayoutState(position: CGPoint(x: 40, y: 1120), size: CGSize(width: 500, height: 120))
        default:              return WidgetLayoutState(position: .zero, size: CGSize(width: 300, height: 200))
        }
    }

    // MARK: - iOS Flow Layout

    /// Widget layout definitions for each screen.
    /// Positions are computed dynamically by iOSFlowLayout, skipping hidden widgets.
    private enum WidgetWidth { case full, halfLeft, halfRight }
    private typealias WidgetSlot = (id: String, width: WidgetWidth, height: CGFloat)
    private let iosFullWidth: CGFloat = 375
    private let iosHalfWidth: CGFloat = 182
    private let iosFlowGap: CGFloat = 11
    private let iosFlowSpacing: CGFloat = 5
    // Screens stack vertically on iOS — screen 2 starts below screen 1's content.
    private let iosScreenGapY: CGFloat = 48

    private var iosScreen2OriginY: CGFloat {
        flowExtent(for: screen1Slots, xBase: 0).height + iosScreenGapY
    }

    private var screen1Slots: [WidgetSlot] {
        #if os(iOS)
        let base: [WidgetSlot] = [("weather", .full, 210)]
        switch appContext {
        case .workFocus:
            return base + [
                ("hotlist",   .full, 220),
                ("calendar",  .full, 250),
                ("workTasks", .full, 280),
            ]
        case .night:
            return base + [("hotlist", .full, 220)]
        case .weekend:
            return base + [
                ("hotlist",   .full, 200),
                ("calendar",  .full, 220),
                ("lifeTasks", .full, 280),
            ]
        case .personal:
            return base + [
                ("hotlist",   .full, 200),
                ("calendar",  .full, 220),
                ("workTasks", .full, 240),
            ]
        }
        #else
        return [
            ("weather",    .full,      130),
            ("scratchpad", .halfLeft,  200),
            ("hotlist",    .halfRight, 200),
            ("calendar",   .full,      250),
            ("workTasks",  .full,      280),
        ]
        #endif
    }

    private var screen2Slots: [WidgetSlot] {
        #if os(iOS)
        switch appContext {
        case .weekend:
            return [
                ("workTasks",     .full,      230),
                ("habits",        .full,      180),
                ("projects",      .full,      200),
                ("goals",         .full,      160),
                ("stats",         .halfLeft,  160),
                ("deferredTasks", .halfRight, 160),
                ("waitingTasks",  .halfLeft,  160),
                ("longTermTasks", .halfRight, 160),
                ("funFact",       .full,      120),
            ]
        default:
            return [
                ("lifeTasks",     .full,      230),
                ("habits",        .full,      180),
                ("projects",      .full,      200),
                ("goals",         .full,      160),
                ("stats",         .halfLeft,  160),
                ("deferredTasks", .halfRight, 160),
                ("waitingTasks",  .halfLeft,  160),
                ("longTermTasks", .halfRight, 160),
                ("funFact",       .full,      120),
            ]
        }
        #else
        return [
            ("lifeTasks",     .full,      230),
            ("habits",        .full,      180),
            ("projects",      .full,      200),
            ("goals",         .full,      160),
            ("stats",         .halfLeft,  160),
            ("deferredTasks", .halfRight, 160),
            ("waitingTasks",  .halfLeft,  160),
            ("longTermTasks", .halfRight, 160),
            ("funFact",       .full,      120),
        ]
        #endif
    }

    private var iOSWorldSize: CGSize {
        let screen1Extent = flowExtent(for: screen1Slots, xBase: 0)
        let screen2Extent = flowExtent(for: screen2Slots, xBase: 0)
        let totalHeight = screen1Extent.height + iosScreenGapY + screen2Extent.height + 40
        return CGSize(
            width: iosFullWidth,
            height: max(1100, totalHeight)
        )
    }

    private func iOSDefaultLayout(_ widgetId: String) -> WidgetLayoutState {
        // Flow screen 1
        if let result = flowPosition(
            for: widgetId,
            in: screen1Slots,
            xBase: 0,
            yBase: 0,
            fw: iosFullWidth,
            hw: iosHalfWidth,
            gap: iosFlowGap,
            spacing: iosFlowSpacing
        ) {
            return result
        }

        // Flow screen 2 — stacked below screen 1
        if let result = flowPosition(
            for: widgetId,
            in: screen2Slots,
            xBase: 0,
            yBase: iosScreen2OriginY,
            fw: iosFullWidth,
            hw: iosHalfWidth,
            gap: iosFlowGap,
            spacing: iosFlowSpacing
        ) {
            return result
        }

        // Widgets not in iOS flow (clock, todayBar, terminal — replaced by chrome/input bar)
        // Return off-screen position so they don't appear
        return WidgetLayoutState(position: CGPoint(x: -1000, y: -1000), size: CGSize(width: 0, height: 0))
    }

    private func flowPosition(for widgetId: String, in slots: [WidgetSlot], xBase: CGFloat, yBase: CGFloat = 0, fw: CGFloat, hw: CGFloat, gap: CGFloat, spacing: CGFloat) -> WidgetLayoutState? {
        var y: CGFloat = yBase
        var i = 0

        while i < slots.count {
            let slot = slots[i]

            // Check if this is a half-width pair
            if slot.width == .halfLeft && i + 1 < slots.count && slots[i + 1].width == .halfRight {
                let leftSlot = slot
                let rightSlot = slots[i + 1]
                let leftVisible = isWidgetVisibleForFlow(leftSlot.id)
                let rightVisible = isWidgetVisibleForFlow(rightSlot.id)
                let pairHeight = max(leftSlot.height, rightSlot.height)

                if leftVisible || rightVisible {
                    if widgetId == leftSlot.id {
                        return WidgetLayoutState(
                            position: CGPoint(x: xBase, y: y),
                            size: CGSize(width: leftVisible ? hw : 0, height: pairHeight)
                        )
                    }
                    if widgetId == rightSlot.id {
                        return WidgetLayoutState(
                            position: CGPoint(x: xBase + hw + gap, y: y),
                            size: CGSize(width: rightVisible ? hw : 0, height: pairHeight)
                        )
                    }
                    y += pairHeight + spacing
                }
                i += 2
                continue
            }

            // Full-width widget
            let visible = isWidgetVisibleForFlow(slot.id)
            if visible {
                if widgetId == slot.id {
                    return WidgetLayoutState(
                        position: CGPoint(x: xBase, y: y),
                        size: CGSize(width: fw, height: slot.height)
                    )
                }
                y += slot.height + spacing
            }
            i += 1
        }

        return nil
    }

    private func flowExtent(for slots: [WidgetSlot], xBase: CGFloat) -> CGSize {
        var y: CGFloat = 0
        var maxX = xBase
        var i = 0

        while i < slots.count {
            let slot = slots[i]

            if slot.width == .halfLeft && i + 1 < slots.count && slots[i + 1].width == .halfRight {
                let leftSlot = slot
                let rightSlot = slots[i + 1]
                let leftVisible = isWidgetVisibleForFlow(leftSlot.id)
                let rightVisible = isWidgetVisibleForFlow(rightSlot.id)
                let pairHeight = max(leftSlot.height, rightSlot.height)

                if leftVisible || rightVisible {
                    if leftVisible {
                        maxX = max(maxX, xBase + iosHalfWidth)
                    }
                    if rightVisible {
                        maxX = max(maxX, xBase + iosHalfWidth + iosFlowGap + iosHalfWidth)
                    }
                    y += pairHeight + iosFlowSpacing
                }
                i += 2
                continue
            }

            if isWidgetVisibleForFlow(slot.id) {
                let width = slot.width == .full ? iosFullWidth : iosHalfWidth
                let x = slot.width == .halfRight ? xBase + iosHalfWidth + iosFlowGap : xBase
                maxX = max(maxX, x + width)
                y += slot.height + iosFlowSpacing
            }
            i += 1
        }

        return CGSize(width: maxX, height: max(0, y - iosFlowSpacing))
    }

    private func isWidgetVisibleForFlow(_ id: String) -> Bool {
        guard let widgetId = WidgetID.allCases.first(where: { $0.rawValue.lowercased().contains(id.lowercased()) || widgetIdString($0) == id }) else {
            return true
        }
        return widgetVisibility.isVisible(widgetId)
    }

    private func widgetIdString(_ id: WidgetID) -> String {
        switch id {
        case .clock: return "clock"
        case .todayBar: return "todayBar"
        case .weather: return "weather"
        case .workTasks: return "workTasks"
        case .lifeTasks: return "lifeTasks"
        case .habits: return "habits"
        case .calendar: return "calendar"
        case .projects: return "projects"
        case .goals: return "goals"
        case .scratchpad: return "scratchpad"
        case .hotlist: return "hotlist"
        case .stats: return "stats"
        case .terminal: return "terminal"
        case .deferredTasks: return "deferredTasks"
        case .waitingTasks: return "waitingTasks"
        case .longTermTasks: return "longTermTasks"
        case .funFact: return "funFact"
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

        // Pre-load meeting briefings for today's events
        prepService.preloadTodaysBriefings(events: calendarService.events)

        // Background-enrich work tasks with subtasks + source tags
        TaskEnrichmentService.shared.enrichIfNeeded(taskBoard.workTasks, taskBoard: taskBoard)

        // Start weather service
        weatherService.start()
    }

    private func syncAll() {
        loadData()
        calendarService.refresh()
        ConnectionMonitor.shared.checkAll()
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            .foregroundColor(ThemeManager.textSecondary)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
