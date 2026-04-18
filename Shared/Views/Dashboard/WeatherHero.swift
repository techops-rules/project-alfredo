import SwiftUI

/// Full-bleed weather hero — ported from `design/alfredo-hud/widgets.jsx` IosHero.
/// Day/date upper-left, sun or moon upper-right (moon phase shadow), temp centered
/// on the celestial body, weather description + Monday-voice quip under it, star
/// field at night, horizon silhouette at bottom, lightning on thunderstorm, radial
/// sky gradient with day/night variants, heavy text-shadow for readability.
struct WeatherHero: View {
    let weather: WeatherData?

    @State private var now = Date()
    @State private var flash = false
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let lightning = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    private var isDay: Bool {
        if let w = weather {
            return now >= w.sunrise && now < w.sunset
        }
        let h = Calendar.current.component(.hour, from: now)
        return h >= 6 && h < 20
    }

    private var code: Int { weather?.code ?? 1 }
    private var temp: Int { Int((weather?.temp ?? 64).rounded()) }
    private var rainy: Bool { [51,53,55,61,63,65,80,81,82,95,96,99].contains(code) }
    private var snowy: Bool { [71,73,75,85,86].contains(code) }
    private var cloudy: Bool { [2,3,45,48].contains(code) || cloudCoverEst >= 40 }
    private var thunder: Bool { [95,96,99].contains(code) }
    private var cloudCoverEst: Int {
        switch code {
        case 0: return 5
        case 1: return 20
        case 2: return 55
        case 3: return 85
        case 45, 48: return 90
        default: return rainy || snowy ? 80 : 30
        }
    }

    private var nearHorizon: Bool {
        guard let w = weather else { return false }
        let window: TimeInterval = 30 * 60
        return abs(now.timeIntervalSince(w.sunrise)) < window
            || abs(now.timeIntervalSince(w.sunset)) < window
    }

    private var weatherLine: (line: String, quip: String?) {
        let hourlyCodes = weather?.hourly.map { $0.code } ?? []
        let wind = weather?.wind ?? 0
        let hi = Int(weather?.hi ?? 0)
        return HeroCopy.describeDay(
            code: code,
            cloudCover: cloudCoverEst,
            windMph: wind,
            hiF: hi,
            hourlyTodayCodes: Array(hourlyCodes.prefix(24))
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                skyGradient

                if !isDay {
                    StarField(width: geo.size.width, height: geo.size.height)
                }

                if cloudy { CloudBand(cloudCover: cloudCoverEst) }
                if rainy { RainEffect() }
                if snowy { SnowEffect() }

                if thunder {
                    Rectangle()
                        .fill(Color(white: 0.96).opacity(flash ? 0.32 : 0))
                        .allowsHitTesting(false)
                }

                // Bottom scrim for text legibility
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.32),
                        .init(color: Color.black.opacity(0.55), location: 0.62),
                        .init(color: Color.black.opacity(0.82), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                HorizonSilhouette()
                    .frame(height: 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                // Sun / moon pinned upper-right
                celestialBody
                    .frame(width: 66, height: 66)
                    .position(x: geo.size.width - 20 - 33, y: 16 + 33)

                // Temp centered on the sun/moon
                tempBlock
                    .position(x: geo.size.width - 20 - 33, y: 16 + 33)

                // Weather description under the sun
                if !weatherLine.line.isEmpty {
                    wxDesc
                        .frame(width: 100)
                        .position(x: geo.size.width - 20 - 33, y: 16 + 66 + 16)
                }

                // Day/date + holiday upper-left
                dayDate.padding(.leading, 20).padding(.top, 14)

                // Headline + mood + micro-facts at bottom, wrap-constrained
                VStack(alignment: .leading, spacing: 3) {
                    Spacer(minLength: 0)
                    RotatingHeadline()
                    MicroFactsTicker()
                }
                .padding(.top, 70)
                .padding(.trailing, 100)
                .padding(.leading, 20)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .clipped()
        }
        .onReceive(tick) { now = $0 }
        .onReceive(lightning) { _ in
            guard thunder else { return }
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeIn(duration: 0.2)) { flash = false }
            }
        }
    }

    // MARK: - Pieces

    private var skyGradient: some View {
        ZStack {
            if isDay {
                LinearGradient(
                    colors: [Color(red: 0.115, green: 0.165, blue: 0.250),
                             Color(red: 0.060, green: 0.086, blue: 0.145),
                             .black],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.7, blue: 0.31, opacity: 0.18), .clear],
                    center: UnitPoint(x: 0.7, y: 0.0),
                    startRadius: 0, endRadius: 260
                )
            } else {
                LinearGradient(
                    colors: [Color(red: 0.039, green: 0.071, blue: 0.141),
                             Color(red: 0.031, green: 0.055, blue: 0.110),
                             .black],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color(red: 0.59, green: 0.67, blue: 0.86, opacity: 0.16), .clear],
                    center: UnitPoint(x: 0.3, y: 0.05),
                    startRadius: 0, endRadius: 240
                )
            }
        }
    }

    @ViewBuilder private var celestialBody: some View {
        if isDay {
            SunBody(nearHorizon: nearHorizon)
        } else {
            MoonBody(phase: weather?.moonPhase ?? WeatherService.moonPhase(for: now))
        }
    }

    private var tempBlock: some View {
        HStack(alignment: .top, spacing: 1) {
            Text("\(temp)")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
            Text("°")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .opacity(0.7)
        }
        .foregroundColor(.white)
        .monospacedDigit()
        .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 2)
        .shadow(color: .black.opacity(0.82), radius: 7, x: 0, y: 0)
        .allowsHitTesting(false)
    }

    private var wxDesc: some View {
        VStack(spacing: 1) {
            Text(weatherLine.line)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(0.54)
                .foregroundColor(.white)
            if let q = weatherLine.quip {
                Text(q)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .italic()
                    .foregroundColor(Color(red: 0.55, green: 0.85, blue: 0.80))
                    .opacity(0.85)
            }
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
        .shadow(color: .black.opacity(0.7), radius: 5, x: 0, y: 0)
        .allowsHitTesting(false)
    }

    private var dayDate: some View {
        let weekdayFmt = DateFormatter(); weekdayFmt.dateFormat = "EEE"
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "MMM d"
        let holiday = HeroCopy.holiday(for: now)
        return VStack(alignment: .leading, spacing: 2) {
            Text(weekdayFmt.string(from: now).uppercased())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 1)
                .shadow(color: .black.opacity(0.7), radius: 7, x: 0, y: 0)
            Text(dateFmt.string(from: now).uppercased())
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(0.9)
                .foregroundColor(Color(red: 0.55, green: 0.85, blue: 0.80))
                .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
            if let h = holiday {
                Text("· \(h.uppercased())")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(0.9)
                    .foregroundColor(Color(red: 1.0, green: 0.77, blue: 0.30))
                    .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                    .padding(.top, 1)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Sun

private struct SunBody: View {
    let nearHorizon: Bool
    var body: some View {
        let cool = [Color(red: 1, green: 0.89, blue: 0.48),
                    Color(red: 1, green: 0.83, blue: 0.29),
                    Color(red: 1, green: 0.70, blue: 0.28),
                    Color(red: 1, green: 0.70, blue: 0.28).opacity(0)]
        let warm = [Color(red: 1, green: 0.70, blue: 0.40),
                    Color(red: 1, green: 0.55, blue: 0.26),
                    Color(red: 0.91, green: 0.30, blue: 0.24),
                    Color(red: 0.91, green: 0.30, blue: 0.24).opacity(0)]
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: (nearHorizon ? warm : cool)[0], location: 0.15),
                    .init(color: (nearHorizon ? warm : cool)[1], location: 0.45),
                    .init(color: (nearHorizon ? warm : cool)[2], location: 0.72),
                    .init(color: (nearHorizon ? warm : cool)[3], location: 1.0)
                ],
                center: .center, startRadius: 0, endRadius: 33
            ))
            .shadow(color: Color(red: 1, green: 0.72, blue: 0.30).opacity(0.48), radius: 16, x: 0, y: 0)
            .shadow(color: Color(red: 1, green: 0.65, blue: 0.0).opacity(0.20), radius: 32, x: 0, y: 0)
            .allowsHitTesting(false)
    }
}

// MARK: - Moon

private struct MoonBody: View {
    let phase: MoonPhase
    var body: some View {
        let illum = phase.illumination
        // shadow offset matches prototype: waxing → +(1-illum)*70 (shadow on right),
        // waning → negative
        let offsetPct = (phase.isWaxing ? (1 - illum) * 70 : -(1 - illum) * 70)
        let isFull = illum > 0.95
        let isNew = illum < 0.05

        return Circle()
            .fill(Color(red: 0.88, green: 0.89, blue: 0.94))
            .overlay(
                GeometryReader { g in
                    Circle()
                        .fill(Color.black)
                        .frame(width: g.size.width, height: g.size.height * 1.02)
                        .offset(x: g.size.width * CGFloat(offsetPct) / 100, y: -1)
                        .animation(.easeInOut(duration: 0.6), value: offsetPct)
                }
                .mask(Circle())
            )
            .opacity(isNew ? 0.35 : 1.0)
            .shadow(color: Color(red: 0.78, green: 0.82, blue: 0.94).opacity(isFull ? 0.55 : 0.42),
                    radius: isFull ? 13 : 11, x: 0, y: 0)
            .shadow(color: Color(red: 0.82, green: 0.86, blue: 0.98).opacity(isFull ? 0.26 : 0),
                    radius: 26, x: 0, y: 0)
            .allowsHitTesting(false)
    }
}

// MARK: - Stars

private struct StarField: View {
    let width: CGFloat
    let height: CGFloat
    private let stars: [Star]

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
        var rng = SeededRNG(seed: 0xA1F2E3)
        var out: [Star] = []
        for _ in 0..<48 {
            let sz = rng.unitFloat()
            let size: CGFloat = sz < 0.7 ? 1 : sz < 0.92 ? 1.5 : 2.2
            out.append(Star(
                x: CGFloat(rng.unitFloat()),
                y: CGFloat(rng.unitFloat()) * 0.62,
                size: size,
                baseOpacity: 0.45 + CGFloat(rng.unitFloat()) * 0.45,
                twinkle: 2.2 + Double(rng.unitFloat()) * 3.2,
                delay: Double(rng.unitFloat()) * 3
            ))
        }
        self.stars = out
    }

    var body: some View {
        ZStack {
            ForEach(stars.indices, id: \.self) { i in
                TwinkleStar(star: stars[i])
                    .position(x: stars[i].x * width, y: stars[i].y * height)
            }
        }
        .allowsHitTesting(false)
    }

    struct Star { let x, y, size: CGFloat; let baseOpacity: CGFloat; let twinkle, delay: Double }

    struct TwinkleStar: View {
        let star: Star
        @State private var dim = false
        var body: some View {
            Circle()
                .fill(Color.white)
                .frame(width: star.size, height: star.size)
                .opacity(dim ? star.baseOpacity * 0.25 : star.baseOpacity)
                .shadow(color: .white.opacity(0.7), radius: 1)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + star.delay) {
                        withAnimation(.easeInOut(duration: star.twinkle / 2).repeatForever(autoreverses: true)) {
                            dim = true
                        }
                    }
                }
        }
    }
}

// simple deterministic RNG so stars don't jitter between renders
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func unitFloat() -> Float {
        Float(next() % 10_000) / 10_000.0
    }
}

// MARK: - Clouds, rain, snow, horizon

private struct CloudBand: View {
    let cloudCover: Int
    var body: some View {
        ZStack {
            cloud(width: 0.45, top: 18, leftFrac: 0.04, opacity: 0.78, blur: 1.8)
            cloud(width: 0.55, top: 36, leftFrac: 0.28, opacity: 0.66, blur: 1.8)
            if cloudCover >= 45 {
                cloud(width: 0.38, top: 12, leftFrac: 0.58, opacity: 0.58, blur: 2.4)
            }
            if cloudCover >= 60 {
                cloud(width: 0.42, top: 54, leftFrac: -0.06, opacity: 0.5, blur: 2.2)
            }
            if cloudCover >= 75 {
                cloud(width: 0.36, top: 48, leftFrac: 0.48, opacity: 0.52, blur: 1.8)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cloud(width: CGFloat, top: CGFloat, leftFrac: CGFloat, opacity: Double, blur: CGFloat) -> some View {
        GeometryReader { g in
            Capsule()
                .fill(LinearGradient(
                    colors: [Color(red: 0.92, green: 0.95, blue: 0.99, opacity: 0.58),
                             Color(red: 0.75, green: 0.80, blue: 0.88, opacity: 0.42)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: g.size.width * width, height: 12)
                .blur(radius: blur)
                .opacity(opacity)
                .position(x: g.size.width * (leftFrac + width / 2), y: top)
        }
    }
}

private struct RainEffect: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            ZStack {
                ForEach(0..<14, id: \.self) { i in
                    let dropHeight = CGFloat.random(in: 10...20)
                    Capsule()
                        .fill(Color(red: 0.78, green: 0.88, blue: 1.0).opacity(0.55))
                        .frame(width: 1.4, height: dropHeight)
                        .position(
                            x: CGFloat(i) * g.size.width / 14 + CGFloat.random(in: 0...10),
                            y: (phase * g.size.height + CGFloat(i) * 40).truncatingRemainder(dividingBy: g.size.height)
                        )
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SnowEffect: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    let sz = CGFloat.random(in: 2.5...4.5)
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: sz, height: sz)
                        .position(
                            x: CGFloat(i) * g.size.width / 12 + CGFloat.random(in: 0...12),
                            y: (phase * g.size.height + CGFloat(i) * 30).truncatingRemainder(dividingBy: g.size.height)
                        )
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HorizonSilhouette: View {
    var body: some View {
        GeometryReader { g in
            ZStack {
                // back ridge
                Path { p in
                    let w = g.size.width, h = g.size.height
                    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 390 * w, y: y / 28 * h) }
                    p.move(to: pt(0, 28))
                    p.addLine(to: pt(0, 18))
                    p.addLine(to: pt(30, 12)); p.addLine(to: pt(60, 16)); p.addLine(to: pt(95, 8))
                    p.addLine(to: pt(135, 14)); p.addLine(to: pt(170, 6)); p.addLine(to: pt(210, 12))
                    p.addLine(to: pt(250, 4)); p.addLine(to: pt(290, 10)); p.addLine(to: pt(330, 6))
                    p.addLine(to: pt(370, 12)); p.addLine(to: pt(390, 9)); p.addLine(to: pt(390, 28))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.031, green: 0.047, blue: 0.078).opacity(0.55))

                // front ridge
                Path { p in
                    let w = g.size.width, h = g.size.height
                    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 390 * w, y: y / 28 * h) }
                    p.move(to: pt(0, 28))
                    p.addLine(to: pt(0, 22))
                    p.addLine(to: pt(22, 18)); p.addLine(to: pt(48, 22)); p.addLine(to: pt(78, 16))
                    p.addLine(to: pt(110, 20)); p.addLine(to: pt(138, 14)); p.addLine(to: pt(170, 18))
                    p.addLine(to: pt(198, 12)); p.addLine(to: pt(232, 16)); p.addLine(to: pt(262, 10))
                    p.addLine(to: pt(298, 14)); p.addLine(to: pt(330, 8)); p.addLine(to: pt(362, 14))
                    p.addLine(to: pt(390, 10)); p.addLine(to: pt(390, 28))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.020, green: 0.031, blue: 0.055).opacity(0.88))
            }
        }
        .allowsHitTesting(false)
    }
}
