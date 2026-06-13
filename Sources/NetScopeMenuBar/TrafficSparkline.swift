import SwiftUI
import NetScopeCore

struct TrafficSparkline: View {
    let points: [TrafficTrendPoint]
    let theme: NetScopePopoverTheme

    var body: some View {
        Canvas { context, size in
            let railRect = CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)
            context.fill(Path(railRect), with: .color(theme.rail))

            guard points.count >= 2 else {
                return
            }

            let maxValue = max(points.map(\.totalBytesPerSecond).max() ?? 1, 1)
            let step = size.width / CGFloat(points.count - 1)
            var path = Path()

            for (index, point) in points.enumerated() {
                let x = CGFloat(index) * step
                let normalized = CGFloat(point.totalBytesPerSecond) / CGFloat(maxValue)
                let y = size.height - max(2, normalized * (size.height - 3))

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(theme.neutralAccent), lineWidth: 2)
        }
        .overlay(alignment: .leading) {
            if points.count < 2 {
                Text("Waiting for more samples")
                    .font(NetScopeFont.medium(10.5))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .accessibilityLabel("Traffic trend")
    }
}
