import AppKit

/// EchoVela's menu bar picture: a sun whose disc is lit on the left and outlined on the right, like
/// the app icon. It is a template image, so macOS draws it white or black to match the menu bar.
enum MenuBarGlyph {
    @MainActor static let image: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Eight short rays.
            let rays = NSBezierPath()
            rays.lineWidth = 1.4
            rays.lineCapStyle = .round
            for index in 0 ..< 8 {
                let angle = (90 + CGFloat(index) * 45) * .pi / 180
                rays.move(to: NSPoint(x: center.x + cos(angle) * 6.3, y: center.y + sin(angle) * 6.3))
                rays.line(to: NSPoint(x: center.x + cos(angle) * 8.2, y: center.y + sin(angle) * 8.2))
            }
            rays.stroke()

            // The disc: left half filled, whole edge drawn.
            let radius: CGFloat = 4.2
            let lit = NSBezierPath()
            lit.move(to: NSPoint(x: center.x, y: center.y + radius))
            lit.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 270, clockwise: false)
            lit.close()
            lit.fill()

            let edge = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            edge.lineWidth = 1.3
            edge.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "EchoVela"
        return image
    }()
}
