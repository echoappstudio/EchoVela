import AppKit
import EchoVelaCore
import SwiftUI

/// The panel that opens from EchoVela's menu bar icon.
struct MenuBarView: View {
    @Environment(EchoVelaRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow

    private var displays: DisplayController { runtime.displays }

    private var activePresetID: UUID? {
        let levels = displays.displays.filter { !$0.isChecking }.map { $0.brightness }
        return BrightnessPresets.active(in: runtime.presets.presets, displayLevels: levels)?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text("EchoVela")
                    .font(.headline)
                Spacer()
                Button {
                    openMainWindow()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(FramedIconButtonStyle())
                .help("Open EchoVela")
            }

            if displays.displays.isEmpty {
                Text("No displays found.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displays.displays) { display in
                    MenuDisplayControls(display: display)
                }
            }

            presetButtons

            if runtime.brightnessKeysEnabled, !runtime.mediaKeys.hasAccessibilityPermission {
                Button {
                    runtime.mediaKeys.requestPermission()
                } label: {
                    Label("Allow Accessibility to use the brightness keys", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
            }

            if let version = runtime.updates.updateWaiting {
                Button {
                    runtime.updates.checkForUpdates()
                } label: {
                    Label("EchoVela \(version) is ready to install", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(EchoVelaTheme.accent)
            }

            Divider()

            HStack {
                Button("Open EchoVela…") { openMainWindow() }
                Spacer()
                Button("Check for Updates…") { runtime.updates.checkForUpdates() }
                    .disabled(!runtime.updates.canCheckForUpdates)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 330)
        .background(EchoVelaTheme.background)
        .tint(EchoVelaTheme.accent)
        .onAppear {
            displays.refreshNativeLevels()
            runtime.mediaKeys.refreshPermission()
        }
    }

    private var presetButtons: some View {
        let columns = [GridItem(.adaptive(minimum: 92), spacing: 6)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(runtime.presets.presets) { preset in
                let isActive = preset.id == activePresetID
                Button {
                    runtime.apply(preset)
                } label: {
                    Label(preset.name, systemImage: preset.symbolName)
                        .lineLimit(1)
                }
                .buttonStyle(PresetChipStyle(isActive: isActive))
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
    }

    private func openMainWindow() {
        openWindow(id: EchoVelaWindow.main)
        EchoVelaWindow.didOpen()
    }
}

/// One display's sliders in the menu bar panel.
private struct MenuDisplayControls: View {
    @Environment(EchoVelaRuntime.self) private var runtime
    let display: EchoVelaDisplay

    private var displays: DisplayController { runtime.displays }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if display.isChecking {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                Text(display.kindDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            LevelSlider(
                value: display.brightness,
                lowSymbol: "sun.min",
                highSymbol: "sun.max.fill",
                isEnabled: !display.isChecking
            ) { displays.setBrightnessFromSlider($0, for: display) }

            if let contrast = display.contrast {
                LevelSlider(value: contrast, lowSymbol: "circle.lefthalf.filled", highSymbol: "circle.lefthalf.filled", isEnabled: true) {
                    displays.setContrast($0, for: display)
                }
            }
            if let volume = display.volume {
                HStack(spacing: 6) {
                    Button {
                        displays.toggleMute(display)
                    } label: {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .frame(width: 16)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(volume == 0 ? "Unmute" : "Mute")
                    Slider(value: Binding(get: { volume }, set: { displays.setVolume($0, for: display) }), in: 0 ... 1)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoVelaCard()
    }
}

/// A slider with a symbol on each end, used in the menu bar and the window.
struct LevelSlider: View {
    let value: Double
    let lowSymbol: String
    let highSymbol: String
    let isEnabled: Bool
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: lowSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0 ... 1)
                .disabled(!isEnabled)
            Image(systemName: highSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
    }
}
