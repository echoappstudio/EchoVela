import AppKit
import EchoVelaCore
import SwiftUI

/// EchoVela's colours, all from the Signature palette. Each one picks its light or dark version
/// from the window it is drawn in, so the app follows the Mac's setting.
@MainActor
enum EchoVelaTheme {
    /// Behind each screen and the menu bar panel.
    static var background: Color { signature { palette, _ in NSColor(palette.window) } }
    /// The sidebar, a shade away from the content.
    static var sidebar: Color { signature { palette, _ in NSColor(palette.sidebar) } }
    /// Cards.
    static var card: Color { signature { palette, _ in NSColor(palette.surface) } }
    static var cardBorder: Color {
        signature { _, dark in dark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.08) }
    }
    /// Sliders, switches, the active preset and the brightness bar.
    static var accent: Color { signature { palette, _ in NSColor(palette.accent) } }
    /// Text on an accent surface.
    static var onAccent: Color { signature { palette, _ in NSColor(palette.onAccent) } }
    static let cornerRadius: CGFloat = 12
    /// The website's silver headline gradient, used for screen titles in dark mode.
    static let silver = LinearGradient(
        colors: [Color(white: 1), Color(red: 0.851, green: 0.855, blue: 0.863), Color(red: 0.553, green: 0.561, blue: 0.576)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// One of the palette's colours, light or dark to match where it is drawn.
    private static func signature(_ make: @escaping @Sendable (SignaturePalette, Bool) -> NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { @Sendable appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return make(Signature.palette(dark: dark), dark)
        })
    }
}

extension NSColor {
    convenience init(_ colour: RGB) {
        self.init(srgbRed: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
    }
}

/// A screen's big title ("Displays", "Settings"). In dark mode it takes the website's silver gradient.
struct PageTitle: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let title = Text(text).font(.largeTitle.weight(.semibold))
        if colorScheme == .dark {
            title.foregroundStyle(EchoVelaTheme.silver)
        } else {
            title
        }
    }
}

/// A rounded card. In dark mode its top edge is lit, as the website's cards are.
struct EchoVelaCardBackground: ViewModifier {
    var cornerRadius: CGFloat = EchoVelaTheme.cornerRadius
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(EchoVelaTheme.card, in: shape)
            .overlay {
                shape.strokeBorder(EchoVelaTheme.cardBorder, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                if colorScheme == .dark {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.24), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 1)
                    .padding(.horizontal, cornerRadius)
                    .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func echoVelaCard(cornerRadius: CGFloat = EchoVelaTheme.cornerRadius) -> some View {
        modifier(EchoVelaCardBackground(cornerRadius: cornerRadius))
    }
}

/// Draws every GroupBox in the window as a card.
@MainActor
struct EchoVelaCardStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoVelaCard()
    }
}

/// The main action: the accent fill with the palette's own text colour on it.
@MainActor
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? EchoVelaTheme.onAccent : Color.secondary.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(shape.fill(isEnabled ? EchoVelaTheme.accent : Color.primary.opacity(0.07)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    @MainActor static var accent: AccentButtonStyle { AccentButtonStyle() }
}

/// A preset button in the menu bar panel: a solid accent chip while it is the one in use.
@MainActor
struct PresetChipStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return configuration.label
            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? EchoVelaTheme.onAccent : Color.primary)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(shape.fill(isActive ? EchoVelaTheme.accent : Color.primary.opacity(0.07)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(shape)
    }
}

/// The small framed button beside the title in the panel.
@MainActor
struct FramedIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return configuration.label
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(shape.fill(Color.primary.opacity(0.07)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }
}

/// A segmented choice drawn in the palette: the chosen part is an accent chip.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(title: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? EchoVelaTheme.onAccent : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? EchoVelaTheme.accent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}
