import EchoVelaCore
import SwiftUI

struct ShortcutsView: View {
    @Environment(EchoVelaRuntime.self) private var runtime
    @AppStorage(Preferences.brightnessKeysKey) private var brightnessKeys = true
    @AppStorage(Preferences.volumeKeysKey) private var volumeKeys = true
    @AppStorage(Preferences.brightnessKeyTargetKey) private var brightnessKeyTarget = BrightnessKeyTarget.pointerDisplay.rawValue

    private var shortcuts: ShortcutController { runtime.shortcuts }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    PageTitle("Shortcuts")
                    Text("Use your keyboard's brightness and volume keys on any monitor, or set your own key combos.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                keySettings
                shortcutSettings
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(EchoVelaTheme.background)
        .frame(minWidth: 640, minHeight: 540)
        .onChange(of: brightnessKeys) { runtime.updateKeyListening() }
        .onChange(of: volumeKeys) { runtime.updateKeyListening() }
    }

    // MARK: Brightness and volume keys

    private var keySettings: some View {
        GroupBox("Brightness and volume keys") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Use the brightness keys for external monitors", isOn: $brightnessKeys)
                Picker("The brightness keys change", selection: $brightnessKeyTarget) {
                    Text("The display with the pointer").tag(BrightnessKeyTarget.pointerDisplay.rawValue)
                    Text("All displays").tag(BrightnessKeyTarget.allDisplays.rawValue)
                }
                .fixedSize()
                .disabled(!brightnessKeys)
                Text("Your MacBook and Apple displays keep their usual brightness keys. Keys move 5% at a time, and 1% at a time below 5%. Hold Option and Shift for 1% steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Toggle("Use the volume keys for monitor speakers", isOn: $volumeKeys)
                Text("Works when your Mac's sound output is set to the monitor and the monitor reports a volume setting. Otherwise the volume keys work as usual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if brightnessKeys || volumeKeys {
                    Divider()
                    accessibilityStatus
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var accessibilityStatus: some View {
        if runtime.mediaKeys.isListening {
            Label("EchoVela is listening for the brightness and volume keys.", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Label("EchoVela needs Accessibility permission to use these keys. After each update, remove EchoVela from the list and add it again.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Allow…") { runtime.mediaKeys.requestPermission() }
            }
        }
    }

    // MARK: Your shortcuts

    private var shortcutSettings: some View {
        GroupBox("Your shortcuts") {
            VStack(alignment: .leading, spacing: 10) {
                shortcutRow("Brighter", action: .brighter, shortcut: shortcuts.brighter) { shortcuts.setBrighter($0) }
                shortcutRow("Dimmer", action: .dimmer, shortcut: shortcuts.dimmer) { shortcuts.setDimmer($0) }
                ForEach(runtime.presets.presets) { preset in
                    shortcutRow(preset.name, action: .preset(preset.id), shortcut: preset.shortcut) { newShortcut in
                        runtime.presets.update(preset.id) { $0.shortcut = newShortcut }
                        runtime.presetsChanged()
                    }
                }
                Text("Shortcuts work in every app and don't need Accessibility. Brighter and Dimmer change the same displays as the brightness keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func shortcutRow(
        _ title: String,
        action: ShortcutAction,
        shortcut: EchoVelaCore.KeyboardShortcut?,
        onChange: @escaping @MainActor (EchoVelaCore.KeyboardShortcut?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(title)
                    .frame(width: 120, alignment: .leading)
                ShortcutRecorder(
                    shortcut: shortcut,
                    onChange: onChange,
                    onCapturingChange: { shortcuts.setCapturing($0) }
                )
            }
            if let message = conflictMessage(for: action, shortcut: shortcut) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func conflictMessage(for action: ShortcutAction, shortcut: EchoVelaCore.KeyboardShortcut?) -> String? {
        guard let shortcut else { return nil }
        if shortcuts.unavailable.contains(action) {
            return "macOS didn't accept \(shortcut.displayText). Another app may be using it."
        }
        guard let owner = ShortcutConflicts.owner(of: shortcut, excluding: action, in: shortcuts.assignments) else {
            return nil
        }
        return "\(shortcut.displayText) is also used by \(Self.name(of: owner, presets: runtime.presets.presets))."
    }

    static func name(of action: ShortcutAction, presets: [BrightnessPreset]) -> String {
        switch action {
        case .brighter: "Brighter"
        case .dimmer: "Dimmer"
        case .preset(let id): presets.first { $0.id == id }?.name ?? "a preset"
        }
    }
}
