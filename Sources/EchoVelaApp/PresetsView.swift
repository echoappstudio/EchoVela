import AppKit
import EchoVelaCore
import SwiftUI

struct PresetsView: View {
    @Environment(EchoVelaRuntime.self) private var runtime

    private var presets: PresetController { runtime.presets }

    /// New presets start at the brightness of the display with the pointer, or the first one.
    private var currentLevel: Double {
        let displays = runtime.displays.displays
        let pointerID = NSScreen.pointerDisplayID
        return (displays.first { $0.id == pointerID } ?? displays.first)?.brightness ?? 0.7
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    PageTitle("Presets")
                    Text("Set every display to a saved brightness with one click or one shortcut.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(presets.presets.enumerated()), id: \.element.id) { index, preset in
                    PresetPanel(preset: preset, isFirst: index == 0, isLast: index == presets.presets.count - 1)
                }

                HStack(spacing: 12) {
                    Button("Add Preset") {
                        presets.add(level: currentLevel)
                        runtime.presetsChanged()
                    }
                    .disabled(!presets.canAdd)
                    Button("Restore Day, Evening and Night") {
                        presets.restoreDefaults()
                        runtime.presetsChanged()
                    }
                    Spacer()
                }

                Text("A new preset starts at the brightness of the display with the pointer. Presets fade in slowly, so the change is easy on your eyes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(EchoVelaTheme.background)
        .frame(minWidth: 640, minHeight: 540)
    }
}

private struct PresetPanel: View {
    @Environment(EchoVelaRuntime.self) private var runtime
    let preset: BrightnessPreset
    let isFirst: Bool
    let isLast: Bool

    private var presets: PresetController { runtime.presets }

    private func update(_ change: (inout BrightnessPreset) -> Void) {
        presets.update(preset.id, change)
        runtime.presetsChanged()
    }

    private var nameBinding: Binding<String> {
        Binding(get: { preset.name }, set: { newName in update { $0.name = newName } })
    }

    private var symbolBinding: Binding<String> {
        Binding(get: { preset.symbolName }, set: { newSymbol in update { $0.symbolName = newSymbol } })
    }

    private var conflictMessage: String? {
        guard let shortcut = preset.shortcut else { return nil }
        if runtime.shortcuts.unavailable.contains(.preset(preset.id)) {
            return "macOS didn't accept \(shortcut.displayText). Another app may be using it."
        }
        guard let owner = ShortcutConflicts.owner(of: shortcut, excluding: .preset(preset.id), in: runtime.shortcuts.assignments) else {
            return nil
        }
        return "\(shortcut.displayText) is also used by \(ShortcutsView.name(of: owner, presets: presets.presets))."
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Symbol", selection: symbolBinding) {
                        ForEach(BrightnessPresets.symbolChoices, id: \.self) { symbol in
                            Image(systemName: symbol).tag(symbol)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("Name", text: nameBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    Spacer()
                    Button("Apply") { runtime.apply(preset) }
                        .buttonStyle(.accent)
                    Button {
                        presets.move(preset.id, by: -1)
                        runtime.presetsChanged()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(isFirst)
                    .help("Move up")
                    Button {
                        presets.move(preset.id, by: 1)
                        runtime.presetsChanged()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(isLast)
                    .help("Move down")
                    Button(role: .destructive) {
                        presets.delete(preset.id)
                        runtime.presetsChanged()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(presets.presets.count <= 1)
                    .help("Delete preset")
                }

                HStack(spacing: 12) {
                    Text("Brightness")
                        .frame(width: 80, alignment: .leading)
                    LevelSlider(value: preset.level, lowSymbol: "sun.min", highSymbol: "sun.max.fill", isEnabled: true) { newLevel in
                        update { $0.level = newLevel }
                    }
                    Text(Level.percentText(preset.level))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Text("Shortcut")
                        .frame(width: 80, alignment: .leading)
                    ShortcutRecorder(
                        shortcut: preset.shortcut,
                        onChange: { newShortcut in update { $0.shortcut = newShortcut } },
                        onCapturingChange: { runtime.shortcuts.setCapturing($0) }
                    )
                }
                if let conflictMessage {
                    Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
