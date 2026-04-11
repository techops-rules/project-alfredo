import SwiftUI

struct MinimapView: View {
    let worldSize: CGSize
    let viewportSize: CGSize
    let offset: CGPoint

    @Environment(\.theme) private var theme

    private let mapSize = CGSize(width: 140, height: 90)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MAP")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
                .tracking(2)

            ZStack(alignment: .topLeading) {
                // World background
                RoundedRectangle(cornerRadius: 4)
                    .fill(ThemeManager.background.opacity(0.8))
                    .frame(width: mapSize.width, height: mapSize.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.accentBorder, lineWidth: 0.5)
                    )

                // Viewport indicator
                let scaleX = mapSize.width / worldSize.width
                let scaleY = mapSize.height / worldSize.height
                let vpW = viewportSize.width * scaleX
                let vpH = viewportSize.height * scaleY
                let vpX = -offset.x * scaleX
                let vpY = -offset.y * scaleY

                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(theme.accentFull, lineWidth: 1.5)
                    .background(theme.accentFull.opacity(0.1).clipShape(RoundedRectangle(cornerRadius: 2)))
                    .frame(width: max(vpW, 20), height: max(vpH, 12))
                    .offset(x: max(0, vpX), y: max(0, vpY))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
