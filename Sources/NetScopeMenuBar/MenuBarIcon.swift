import AppKit
import NetScopeCore

enum MenuBarIcon {
    static func image(for status: NetworkStatus) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawIcon(in: rect, status: status)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription(for: status)
        return image
    }

    private static func drawIcon(in rect: NSRect, status: NetworkStatus) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let scaleX = rect.width / 18
        let scaleY = rect.height / 18

        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        let frame = NSRect(
            x: rect.minX + 2.7 * scaleX,
            y: rect.minY + 3.2 * scaleY,
            width: 12.6 * scaleX,
            height: 11.6 * scaleY
        )
        let framePath = NSBezierPath(roundedRect: frame, xRadius: 3.8 * scaleX, yRadius: 3.8 * scaleY)
        framePath.lineWidth = 1.35
        framePath.stroke()

        let wave = NSBezierPath()
        wave.lineWidth = 1.55
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        wave.move(to: point(4.6, 8.8))
        wave.line(to: point(6.2, 8.8))
        wave.line(to: point(7.6, 11.4))
        wave.line(to: point(9.8, 6.7))
        wave.line(to: point(11.0, 9.3))
        wave.line(to: point(13.3, 9.3))
        wave.stroke()

        switch status {
        case .normal:
            break
        case .possiblePressure:
            NSBezierPath(ovalIn: NSRect(
                x: rect.minX + 12.7 * scaleX,
                y: rect.minY + 12.2 * scaleY,
                width: 2.7 * scaleX,
                height: 2.7 * scaleY
            )).fill()
        case .likelyIssue:
            let mark = NSBezierPath(roundedRect: NSRect(
                x: rect.minX + 13.35 * scaleX,
                y: rect.minY + 8.7 * scaleY,
                width: 1.45 * scaleX,
                height: 4.8 * scaleY
            ), xRadius: 0.7 * scaleX, yRadius: 0.7 * scaleY)
            mark.fill()
            NSBezierPath(ovalIn: NSRect(
                x: rect.minX + 13.15 * scaleX,
                y: rect.minY + 6.0 * scaleY,
                width: 1.85 * scaleX,
                height: 1.85 * scaleY
            )).fill()
        }
    }

    private static func accessibilityDescription(for status: NetworkStatus) -> String {
        switch status {
        case .normal:
            return "NetScope normal"
        case .possiblePressure:
            return "NetScope possible pressure"
        case .likelyIssue:
            return "NetScope likely issue"
        }
    }
}
