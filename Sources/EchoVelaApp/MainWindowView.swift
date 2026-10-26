import AppKit
import SwiftUI

/// The four screens of EchoVela's window.
enum EchoVelaScreen: String, CaseIterable, Identifiable {
    case displays = "Displays"
    case presets = "Presets"
    case shortcuts = "Shortcuts"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .displays: "display.2"
        case .presets: "sun.horizon"
        case .shortcuts: "keyboard"
        case .settings: "gearshape"
        }
    }
}

/// The window: a sidebar on the left and the chosen screen on the right. The sidebar is drawn by
/// hand, not with NavigationSplitView, which loops on layout in this app's window.
struct MainWindowView: View {
    @State private var selection: EchoVelaScreen = .displays

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(EchoVelaTheme.cardBorder)
                .frame(width: 1)
            Group {
                switch selection {
                case .displays: DisplaysView()
                case .presets: PresetsView()
                case .shortcuts: ShortcutsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EchoVelaTheme.background)
        }
        .groupBoxStyle(EchoVelaCardStyle())
        .tint(EchoVelaTheme.accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                Text("EchoVela")
                    .font(.title3.weight(.semibold))
            }
            .padding(.leading, 6)
            .padding(.bottom, 14)

            ForEach(EchoVelaScreen.allCases) { screen in
                SidebarRow(screen: screen, isSelected: screen == selection) {
                    selection = screen
                }
            }

            Spacer()

            Text("On this Mac only.\nNo accounts, no tracking.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(width: 208)
        .frame(maxHeight: .infinity)
        .background(EchoVelaTheme.sidebar)
    }
}

private struct SidebarRow: View {
    let screen: EchoVelaScreen
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: screen.symbolName)
                    .frame(width: 20)
                Text(screen.rawValue)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
