import SwiftUI

/// Cycles through `HeroCopy.headlines` every ~22s. The prototype also refreshes
/// from Claude Haiku every 4h; when a ClaudeService lands in Swift, wire it in
/// at `refreshPool()`. Until then the seed pool rotates forever.
struct RotatingHeadline: View {
    @State private var pool: [String] = HeroCopy.headlines
    @State private var idx: Int = Int.random(in: 0..<HeroCopy.headlines.count)
    private let tick = Timer.publish(every: 22, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(pool.isEmpty ? "" : pool[idx % pool.count])
            .font(.system(size: 20, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.7), radius: 7, x: 0, y: 0)
            .transition(.opacity)
            .id(idx)
            .onReceive(tick) { _ in
                guard !pool.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    idx = (idx + 1) % pool.count
                }
            }
    }
}
