import SwiftUI

struct WeatherWidget: View {
    let weather: WeatherData?
    @Environment(\.theme) private var theme
    @State private var now = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background weather effects
                if let w = weather {
                    WeatherEffectsView(code: w.code, size: geo.size)
                }

                VStack(spacing: 0) {
                    // Sky arc zone (top 45%)
                    SkyArcView(weather: weather, now: now)
                        .frame(height: geo.size.height * 0.45)

                    // Hour strip (bottom 55%)
                    HourStripView(weather: weather, now: now)
                        .frame(height: geo.size.height * 0.55)
                }
            }
        }
        .onReceive(timer) { _ in now = Date() }
    }
}

// MARK: - Sky Arc View

private struct SkyArcView: View {
    let weather: WeatherData?
    let now: Date
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let isNight = isNightTime

            ZStack {
                // Dome arc path (subtle guide line)
                arcPath(width: w, height: h)
                    .stroke(
                        theme.accentFull.opacity(0.1),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )

                // Celestial body
                let pos = celestialPosition(width: w, height: h)
                if isNight {
                    MoonView(phase: weather?.moonPhase ?? WeatherService.moonPhase(for: now))
                        .position(pos)
                } else {
                    SunView(code: weather?.code ?? 0, zenithFactor: zenithFactor)
                        .position(pos)
                }

                // Current temp + condition (top right)
                if let w = weather {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(w.temp))°")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textEmphasis)
                        Text(w.desc.uppercased())
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1)
                        Text("H:\(Int(w.hi))° L:\(Int(w.lo))°")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary.opacity(0.7))
                    }
                    .position(x: geo.size.width - 50, y: h * 0.45)
                }
            }
        }
    }

    private var isNightTime: Bool {
        guard let w = weather else { return false }
        return now < w.sunrise || now > w.sunset
    }

    private var zenithFactor: Double {
        guard let w = weather, !isNightTime else { return 0 }
        let total = w.sunset.timeIntervalSince(w.sunrise)
        let elapsed = now.timeIntervalSince(w.sunrise)
        let progress = elapsed / total
        // Peak at noon (progress=0.5), 0 at horizon
        return 1.0 - abs(progress - 0.5) * 2.0
    }

    private func celestialPosition(width: CGFloat, height: CGFloat) -> CGPoint {
        guard let w = weather else {
            return CGPoint(x: width / 2, y: height / 2)
        }

        let progress: Double
        if isNightTime {
            // Moon: sunset → next sunrise
            let nightDuration: TimeInterval
            let nightElapsed: TimeInterval
            if now > w.sunset {
                // After sunset today
                let nextSunrise = w.sunrise.addingTimeInterval(86400)
                nightDuration = nextSunrise.timeIntervalSince(w.sunset)
                nightElapsed = now.timeIntervalSince(w.sunset)
            } else {
                // Before sunrise today
                let prevSunset = w.sunset.addingTimeInterval(-86400)
                nightDuration = w.sunrise.timeIntervalSince(prevSunset)
                nightElapsed = now.timeIntervalSince(prevSunset)
            }
            progress = max(0, min(1, nightElapsed / max(1, nightDuration)))
        } else {
            // Sun: sunrise → sunset
            let dayDuration = w.sunset.timeIntervalSince(w.sunrise)
            let dayElapsed = now.timeIntervalSince(w.sunrise)
            progress = max(0, min(1, dayElapsed / max(1, dayDuration)))
        }

        // Arc: semicircle from left to right
        let margin: CGFloat = 20
        let arcWidth = width - margin * 2
        let arcHeight = height * 0.8
        let x = margin + arcWidth * CGFloat(progress)
        let normalizedX = (CGFloat(progress) - 0.5) * 2.0 // -1 to 1
        let yOffset = arcHeight * CGFloat(sqrt(max(0, 1.0 - normalizedX * normalizedX)))
        let y = height - 8 - yOffset

        return CGPoint(x: x, y: y)
    }

    private func arcPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let margin: CGFloat = 20
            let arcWidth = width - margin * 2
            let arcHeight = height * 0.8
            let steps = 40

            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let x = margin + arcWidth * CGFloat(t)
                let normalizedX = (CGFloat(t) - 0.5) * 2.0
                let yOffset = arcHeight * CGFloat(sqrt(max(0, 1.0 - normalizedX * normalizedX)))
                let y = height - 8 - yOffset

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }
}

// MARK: - Sun View

private struct SunView: View {
    let code: Int
    let zenithFactor: Double

    var body: some View {
        let color = sunColor
        let glowRadius = 8 + zenithFactor * 12
        let cloudy = code >= 2 && code <= 3

        ZStack {
            // Outer glow
            Circle()
                .fill(color.opacity(cloudy ? 0.15 : 0.3))
                .frame(width: 32, height: 32)
                .blur(radius: glowRadius)

            // Sun body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, color],
                        center: .center,
                        startRadius: 2,
                        endRadius: 10
                    )
                )
                .frame(width: 20, height: 20)
                .shadow(color: color.opacity(cloudy ? 0.3 : 0.6), radius: glowRadius)
        }
    }

    private var sunColor: Color {
        Color(red: 1.0, green: 0.72, blue: 0.30)
    }
}

// MARK: - Moon View

private struct MoonView: View {
    let phase: MoonPhase

    var body: some View {
        let size: CGFloat = 18
        let shadowOffset = moonShadowOffset(size: size)

        ZStack {
            // Glow for brighter phases
            if phase.illumination > 0.3 {
                Circle()
                    .fill(Color(white: 0.85).opacity(phase.illumination * 0.2))
                    .frame(width: size + 10, height: size + 10)
                    .blur(radius: 6)
            }

            // Moon body
            Circle()
                .fill(Color(red: 0.88, green: 0.89, blue: 0.94))
                .frame(width: size, height: size)

            // Crescent shadow
            Circle()
                .fill(Color(red: 0.03, green: 0.05, blue: 0.09))
                .frame(width: size, height: size)
                .offset(x: shadowOffset)
                .clipShape(Circle().size(width: size, height: size))
                .frame(width: size, height: size)
                .clipped()
        }
    }

    private func moonShadowOffset(size: CGFloat) -> CGFloat {
        // Full moon (illumination=1): offset far enough to hide shadow
        // New moon (illumination=0): offset=0, fully covered
        let maxOffset = size * 1.2
        let offset = maxOffset * CGFloat(phase.illumination)
        // Waxing: shadow on left (positive offset moves shadow right, revealing left)
        // Waning: shadow on right (negative offset)
        return phase.isWaxing ? offset : -offset
    }
}

// MARK: - Hour Strip View

private struct HourStripView: View {
    let weather: WeatherData?
    let now: Date
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            if let w = weather {
                let visibleHours = getVisibleHours(w)
                let currentHour = Calendar.current.component(.hour, from: now)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(visibleHours) { hour in
                                let isPast = hour.time < now

                                VStack(spacing: 3) {
                                    // Weather icon
                                    let colors = WeatherService.conditionColor(for: hour.code)
                                    Image(systemName: WeatherService.conditionSymbol(for: hour.code))
                                        .font(.system(size: 11))
                                        .foregroundColor(
                                            Color(red: colors.r, green: colors.g, blue: colors.b)
                                        )

                                    // Temp
                                    Text("\(Int(hour.temp))°")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(ThemeManager.textPrimary)

                                    // Hour label
                                    Text(hourLabel(hour.hour))
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(ThemeManager.textSecondary)
                                }
                                .frame(width: 36)
                                .padding(.vertical, 4)
                                .opacity(isPast ? 0.4 : 1.0)
                                .id(hour.hour)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onAppear {
                        proxy.scrollTo(currentHour, anchor: .center)
                    }
                }
            } else {
                // Loading state
                HStack {
                    Spacer()
                    Text("LOADING WEATHER DATA...")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                    Spacer()
                }
            }
        }
    }

    private func getVisibleHours(_ w: WeatherData) -> [HourForecast] {
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)

        #if os(iOS)
        // iPhone: ±3 hours from current
        let startHour = currentHour - 3
        let endHour = currentHour + 3
        return w.hourly.filter { forecast in
            let h = cal.component(.hour, from: forecast.time)
            let dayOffset = cal.isDate(forecast.time, inSameDayAs: now) ? 0 : 24
            let adjustedHour = h + dayOffset
            return adjustedHour >= startHour && adjustedHour <= endHour
        }
        #else
        // macOS: wider range, sunrise to 10pm (or sunrise if night)
        let isNight = now < w.sunrise || now > w.sunset
        let startHour = currentHour - 2

        if isNight {
            let endTime = w.sunrise.addingTimeInterval(now < w.sunrise ? 0 : 86400)
            return w.hourly.filter { f in
                f.time >= now.addingTimeInterval(-7200) && f.time <= endTime
            }
        } else {
            return w.hourly.filter { f in
                let h = cal.component(.hour, from: f.time)
                return cal.isDate(f.time, inSameDayAs: now) && h >= startHour && h <= 22
            }
        }
        #endif
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "a" : "p"
        return "\(h)\(suffix)"
    }
}

// MARK: - Weather Effects View

struct WeatherEffectsView: View {
    let code: Int
    let size: CGSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
            Canvas { context, canvasSize in
                let time = timeline.date.timeIntervalSinceReferenceDate

                switch code {
                case 51...67, 80...82:
                    // Rain
                    drawRain(context: context, size: canvasSize, time: time)
                case 71...86:
                    // Snow
                    drawSnow(context: context, size: canvasSize, time: time)
                case 95, 96, 99:
                    // Lightning flash
                    drawLightning(context: context, size: canvasSize, time: time)
                default:
                    break
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawRain(context: GraphicsContext, size: CGSize, time: Double) {
        let dropCount = 20
        for i in 0..<dropCount {
            let seed = Double(i) * 7.31
            let x = ((seed * 137.5).truncatingRemainder(dividingBy: 1.0)) * size.width
            let speed = 1.5 + (seed * 0.3).truncatingRemainder(dividingBy: 1.0)
            let y = ((time * speed + seed).truncatingRemainder(dividingBy: 1.0)) * size.height

            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 1, y: y + 6))
            context.stroke(path, with: .color(.blue.opacity(0.3)), lineWidth: 1)
        }
    }

    private func drawSnow(context: GraphicsContext, size: CGSize, time: Double) {
        let flakeCount = 15
        for i in 0..<flakeCount {
            let seed = Double(i) * 11.17
            let baseX = ((seed * 137.5).truncatingRemainder(dividingBy: 1.0)) * size.width
            let speed = 0.3 + (seed * 0.2).truncatingRemainder(dividingBy: 1.0)
            let y = ((time * speed + seed).truncatingRemainder(dividingBy: 1.0)) * size.height
            let drift = sin(time * 0.5 + seed) * 8
            let x = baseX + drift

            let rect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.4)))
        }
    }

    private func drawLightning(context: GraphicsContext, size: CGSize, time: Double) {
        // Occasional flash
        let flashCycle = time.truncatingRemainder(dividingBy: 4.0)
        if flashCycle < 0.1 {
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(.white.opacity(0.15)))
        }
    }
}
