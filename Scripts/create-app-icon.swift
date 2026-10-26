import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: create-app-icon.swift <iconset-directory>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

/// Draws the EchoVela icon on a 1024-point canvas: a black rounded square (a little lighter at the
/// top) on the standard macOS icon grid, and a silver sun whose disc is lit on the left and
/// outlined on the right, like a brightness control. The colours are Echo App Studio's Signature
/// black and silver.
func drawIcon() {
    // macOS icon grid: an 824-point body centered on the 1024 canvas, with a soft drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, 0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0.03, 0.03, 0.04).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Near-black at the bottom, a little lighter at the top.
    let background = NSGradient(
        colors: [color(0.02, 0.024, 0.027), color(0.047, 0.051, 0.059), color(0.106, 0.11, 0.122)],
        atLocations: [0, 0.55, 1],
        colorSpace: .deviceRGB
    )
    background?.draw(in: bodyPath, angle: 90)
    color(1, 1, 1, 0.12).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    rim.lineWidth = 3
    rim.stroke()

    let center = NSPoint(x: 512, y: 512)
    // Silver from mid-grey at the bottom of the sun to near-white at the top.
    let bottomColor = (red: CGFloat(0.42), green: CGFloat(0.43), blue: CGFloat(0.45))
    let topColor = (red: CGFloat(0.96), green: CGFloat(0.96), blue: CGFloat(0.97))
    func silver(atY y: CGFloat) -> NSColor {
        let t = min(max((y - 180) / (844 - 180), 0), 1)
        return color(
            bottomColor.red + (topColor.red - bottomColor.red) * t,
            bottomColor.green + (topColor.green - bottomColor.green) * t,
            bottomColor.blue + (topColor.blue - bottomColor.blue) * t
        )
    }

    // Eight rounded rays, each colored by its height.
    let innerRadius: CGFloat = 238
    let outerRadius: CGFloat = 318
    for index in 0 ..< 8 {
        let angle = (90 + CGFloat(index) * 45) * .pi / 180
        let start = NSPoint(x: center.x + cos(angle) * innerRadius, y: center.y + sin(angle) * innerRadius)
        let end = NSPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius)
        let ray = NSBezierPath()
        ray.move(to: start)
        ray.line(to: end)
        ray.lineWidth = 46
        ray.lineCapStyle = .round
        silver(atY: (start.y + end.y) / 2).setStroke()
        ray.stroke()
    }

    // The disc: the left half is silver, the right half is only an outline.
    let discRadius: CGFloat = 178
    let leftHalf = NSBezierPath()
    leftHalf.move(to: NSPoint(x: center.x, y: center.y + discRadius))
    leftHalf.appendArc(withCenter: center, radius: discRadius, startAngle: 90, endAngle: 270, clockwise: false)
    leftHalf.close()
    let discGradient = NSGradient(starting: color(0.54, 0.545, 0.57), ending: color(0.96, 0.96, 0.965))
    discGradient?.draw(in: leftHalf, angle: 90)

    let rightEdge = NSBezierPath()
    rightEdge.appendArc(withCenter: center, radius: discRadius - 10, startAngle: -90, endAngle: 90, clockwise: false)
    rightEdge.lineWidth = 20
    color(0.66, 0.665, 0.69).setStroke()
    rightEdge.stroke()
}

func renderIcon(pixelSize: Int, fileName: String) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "EchoVelaIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create icon bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "EchoVelaIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create icon graphics context"])
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)

    drawIcon()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "EchoVelaIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
    }
    try data.write(to: iconsetURL.appendingPathComponent(fileName), options: .atomic)
}

let icons: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]
for (size, name) in icons {
    try renderIcon(pixelSize: size, fileName: name)
}
