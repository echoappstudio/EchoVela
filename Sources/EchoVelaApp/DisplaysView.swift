import AppKit
import EchoVelaCore
import SwiftUI

struct DisplaysView: View {
    @Environment(EchoVelaRuntime.self) private var runtime

    private var displays: DisplayController { runtime.displays }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    PageTitle("Displays")
                    Text("Brightness, contrast and volume for every screen connected to this Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if runtime.brightnessKeysEnabled, !runtime.mediaKeys.hasAccessibilityPermission {
                    accessibilityNotice
                }

                if displays.displays.isEmpty {
                    GroupBox {
                        Text("No displays found. Connect a monitor, then choose Find Displays Again.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                ForEach(displays.displays) { display in
                    DisplayPanel(display: display)
                }

                HStack {
                    Button("Find Displays Again") { displays.refreshDisplays() }
                    Spacer()
                }

                Label("EchoVela works entirely on this Mac. It has no accounts, no tracking and doesn't connect to the internet.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            // Fill the window at any size, including full screen.
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(EchoVelaTheme.background)
        .frame(minWidth: 640, minHeight: 540)
        .onAppear { displays.refreshNativeLevels() }
    }

    private var accessibilityNotice: some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("To use your keyboard's brightness keys on your monitors, allow EchoVela in Accessibility.", systemImage: "keyboard")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Allow…") { runtime.mediaKeys.requestPermission() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct DisplayPanel: View {
    @Environment(EchoVelaRuntime.self) private var runtime
    let display: EchoVelaDisplay

    private var displays: DisplayController { runtime.displays }

    private var modeBinding: Binding<DisplayControlMode> {
        Binding(
            get: { displays.controlMode(for: display) },
            set: { displays.setControlMode($0, for: display) }
        )
    }

    var body: some View {
        GroupBox(display.name) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label(display.kindDescription, systemImage: display.kindSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if display.isChecking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking what this monitor supports…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                row("Brightness", level: display.brightness) {
                    LevelSlider(value: display.brightness, lowSymbol: "sun.min", highSymbol: "sun.max.fill", isEnabled: !display.isChecking) {
                        displays.setBrightnessFromSlider($0, for: display)
                    }
                }
                if let contrast = display.contrast {
                    row("Contrast", level: contrast) {
                        LevelSlider(value: contrast, lowSymbol: "circle.lefthalf.filled", highSymbol: "circle.lefthalf.filled", isEnabled: true) {
                            displays.setContrast($0, for: display)
                        }
                    }
                }
                if let volume = display.volume {
                    row("Volume", level: volume) {
                        HStack(spacing: 6) {
                            LevelSlider(value: volume, lowSymbol: "speaker.fill", highSymbol: "speaker.wave.3.fill", isEnabled: true) {
                                displays.setVolume($0, for: display)
                            }
                            Button(volume == 0 ? "Unmute" : "Mute") { displays.toggleMute(display) }
                        }
                    }
                }

                if display.hasConnection || display.kind == .software, display.kind != .native {
                    Divider()
                    controlModePicker
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func row<Content: View>(_ title: String, level: Double, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 80, alignment: .leading)
            content()
            Text(Level.percentText(level))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var controlModePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Brightness control")
                    .frame(width: 140, alignment: .leading)
                SegmentedChoice(
                    options: [
                        (title: "Automatic", value: DisplayControlMode.automatic),
                        (title: "Monitor's own (DDC)", value: DisplayControlMode.hardware),
                        (title: "Software dimming", value: DisplayControlMode.software)
                    ],
                    selection: modeBinding
                )
                .disabled(display.isChecking)
            }
            Text(modeExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeExplanation: String {
        if !display.hasConnection {
            return "This screen can't be reached over DDC (for example AirPlay, Sidecar, or some docks and adapters), so EchoVela dims its picture instead."
        }
        return "Automatic uses the monitor's own brightness when it answers, and software dimming when it doesn't. Choose the monitor's own brightness if your monitor accepts changes but never reports its settings."
    }
}
