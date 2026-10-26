import Foundation

/// A colour as plain numbers (0 to 1), so the palette can be tested without any UI framework.
public struct RGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `RGB(hex: 0xE6E7EA)`.
    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colours (1 to 21).
    public static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let a = first.relativeLuminance
        let b = second.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The colours EchoVela draws itself. Text and secondary text are the system's own, so they always
/// read well on the light or dark background.
public struct SignaturePalette: Equatable, Sendable {
    /// Sliders, switches, the active preset and the brightness bar.
    public let accent: RGB
    /// Text on an accent surface.
    public let onAccent: RGB
    /// Behind each screen and the menu bar panel.
    public let window: RGB
    /// Cards.
    public let surface: RGB
    /// The sidebar, a shade away from the window.
    public let sidebar: RGB
}

/// EchoVela's one look: Echo App Studio's black, charcoal and silver (the same Signature colours
/// Verbyn uses), in a dark and a light version that follow the Mac's setting.
public enum Signature {
    public static func palette(dark: Bool) -> SignaturePalette {
        if dark {
            return SignaturePalette(
                accent: RGB(hex: 0xE6E7EA),
                onAccent: RGB(hex: 0x0B0C0D),
                window: RGB(hex: 0x0B0C0D),
                surface: RGB(hex: 0x151618),
                sidebar: RGB(hex: 0x060708)
            )
        }
        return SignaturePalette(
            accent: RGB(hex: 0x1C1D20),
            onAccent: RGB(hex: 0xFFFFFF),
            window: RGB(hex: 0xF3F3F4),
            surface: RGB(hex: 0xFFFFFF),
            sidebar: RGB(hex: 0xE6E6E8)
        )
    }
}
