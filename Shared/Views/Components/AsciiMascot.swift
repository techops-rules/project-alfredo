import SwiftUI

enum MascotMood {
    case idle, loading, happy, thinking

    var frames: [String] {
        switch self {
        case .idle:
            return [
                """
                 ┌─┐
                 │·│
                ─┘ └─
                """,
                """
                 ┌─┐
                 │°│
                ─┘ └─
                """
            ]
        case .loading:
            return [
                """
                 ┌─┐
                 │◠│
                ─┘ └─
                 ╱ ╲
                """,
                """
                 ┌─┐
                 │◡│
                ─┘ └─
                 ╲ ╱
                """,
                """
                 ┌─┐
                 │◠│
                ─┘ └─
                 │ │
                """,
                """
                 ┌─┐
                 │◡│
                ─┘ └─
                 ╱ ╲
                """
            ]
        case .happy:
            return [
                """
                 ┌─┐
                 │◡│
                ─┘ └─
                  ╱
                """,
                """
                 ┌─┐
                 │◡│
                ─┘ └─
                ╲
                """
            ]
        case .thinking:
            return [
                """
                 ┌─┐ ·
                 │·│·
                ─┘ └─
                """,
                """
                 ┌─┐  ·
                 │°│ ·
                ─┘ └─
                """,
                """
                 ┌─┐ °
                 │·│
                ─┘ └─
                """
            ]
        }
    }
}

struct AsciiMascot: View {
    var mood: MascotMood = .idle
    var color: Color = ThemeManager.textSecondary
    var size: CGFloat = 11

    @State private var frameIndex = 0
    @State private var timer: Timer?

    var body: some View {
        let frames = mood.frames
        let safeIndex = min(frameIndex, frames.count - 1)

        return Text(frames[safeIndex])
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .lineSpacing(0)
            .fixedSize()
            .onAppear { startAnimation() }
            .onDisappear { stopAnimation() }
            .onChange(of: mood) {
                frameIndex = 0
                startAnimation()
            }
    }

    private func startAnimation() {
        stopAnimation()
        guard mood.frames.count > 1 else { return }
        let interval: TimeInterval = mood == .loading ? 0.3 : 0.8
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                frameIndex = (frameIndex + 1) % mood.frames.count
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}
