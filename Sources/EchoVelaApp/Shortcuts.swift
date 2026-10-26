import AppKit
import Carbon.HIToolbox
import EchoVelaCore
import Observation
import SwiftUI

private let echoVelaHotKeySignature: OSType = 0x4556_4C41 // "EVLA"

/// Registers key combos as system-wide hotkeys. macOS delivers a registered combo only to
/// EchoVela, and no Accessibility permission is needed.
@MainActor
final class SystemHotKeyCenter {
    private struct Registration {
        let reference: EventHotKeyRef
        let onPress: @MainActor () -> Void
    }

    private var handlerReference: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]

    /// Returns false when macOS refuses the combo (usually because another app owns it).
    func register(id: UInt32, shortcut: EchoVelaCore.KeyboardShortcut, onPress: @escaping @MainActor () -> Void) -> Bool {
        unregister(id: id)
        guard installHandlerIfNeeded() else { return false }
        var modifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if shortcut.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            modifiers,
            EventHotKeyID(signature: echoVelaHotKeySignature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        registrations[id] = Registration(reference: reference, onPress: onPress)
        return true
    }

    func unregister(id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.reference)
    }

    func unregisterAll() {
        for id in Array(registrations.keys) {
            unregister(id: id)
        }
    }

    fileprivate func handlePress(id: UInt32) {
        registrations[id]?.onPress()
    }

    private func installHandlerIfNeeded() -> Bool {
        if handlerReference != nil { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            echoVelaHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )
        return status == noErr && handlerReference != nil
    }
}

private func echoVelaHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == echoVelaHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let id = hotKeyID.id
    let center = Unmanaged<SystemHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers application events on the main thread.
    MainActor.assumeIsolated {
        center.handlePress(id: id)
    }
    return noErr
}

/// EchoVela's own shortcuts: brighter, dimmer, and one per preset.
@MainActor
@Observable
final class ShortcutController {
    private(set) var brighter: EchoVelaCore.KeyboardShortcut?
    private(set) var dimmer: EchoVelaCore.KeyboardShortcut?
    /// Shortcuts macOS wouldn't register, keyed by action.
    private(set) var unavailable: Set<ShortcutAction> = []

    @ObservationIgnored var perform: (@MainActor (ShortcutAction) -> Void)?
    @ObservationIgnored private let center = SystemHotKeyCenter()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var presets: [BrightnessPreset] = []
    @ObservationIgnored private var isCapturing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        brighter = Self.load(defaults.data(forKey: Preferences.brighterShortcutKey))
        dimmer = Self.load(defaults.data(forKey: Preferences.dimmerShortcutKey))
    }

    var assignments: [ShortcutAction: EchoVelaCore.KeyboardShortcut] {
        var result: [ShortcutAction: EchoVelaCore.KeyboardShortcut] = [:]
        if let brighter { result[.brighter] = brighter }
        if let dimmer { result[.dimmer] = dimmer }
        for preset in presets {
            if let shortcut = preset.shortcut { result[.preset(preset.id)] = shortcut }
        }
        return result
    }

    func setBrighter(_ shortcut: EchoVelaCore.KeyboardShortcut?) {
        brighter = shortcut
        defaults.set(shortcut.flatMap { try? JSONEncoder().encode($0) }, forKey: Preferences.brighterShortcutKey)
        registerAll()
    }

    func setDimmer(_ shortcut: EchoVelaCore.KeyboardShortcut?) {
        dimmer = shortcut
        defaults.set(shortcut.flatMap { try? JSONEncoder().encode($0) }, forKey: Preferences.dimmerShortcutKey)
        registerAll()
    }

    func updatePresets(_ presets: [BrightnessPreset]) {
        self.presets = presets
        registerAll()
    }

    /// While a shortcut is being recorded, EchoVela's own shortcuts step aside so the keys reach
    /// the recorder.
    func setCapturing(_ capturing: Bool) {
        isCapturing = capturing
        registerAll()
    }

    func registerAll() {
        center.unregisterAll()
        guard !isCapturing else { return }
        var failed = Set<ShortcutAction>()
        var nextID: UInt32 = 1
        for (action, shortcut) in assignments.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
            let registered = center.register(id: nextID, shortcut: shortcut) { [weak self] in
                self?.perform?(action)
            }
            if !registered {
                failed.insert(action)
            }
            nextID += 1
        }
        unavailable = failed
    }

    private static func load(_ data: Data?) -> EchoVelaCore.KeyboardShortcut? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(EchoVelaCore.KeyboardShortcut.self, from: data)
    }
}

/// A button that records the next key combo pressed.
struct ShortcutRecorder: View {
    let shortcut: EchoVelaCore.KeyboardShortcut?
    let onChange: @MainActor (EchoVelaCore.KeyboardShortcut?) -> Void
    var onCapturingChange: @MainActor (Bool) -> Void = { _ in }

    @State private var recorder = ShortcutRecorderModel()

    var body: some View {
        HStack(spacing: 8) {
            Button(recorder.isRecording ? "Press a key combo…" : (shortcut?.displayText ?? "Record Shortcut")) {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start(onRecord: onChange, onCapturingChange: onCapturingChange)
                }
            }
            .frame(minWidth: 150)
            if recorder.isRecording {
                Button("Cancel") { recorder.stop() }
                    .buttonStyle(.borderless)
            } else if shortcut != nil {
                Button("Clear") { onChange(nil) }
                    .buttonStyle(.borderless)
            }
            if let hint = recorder.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { recorder.stop() }
    }
}

@MainActor
@Observable
private final class ShortcutRecorderModel {
    private(set) var isRecording = false
    private(set) var hint: String?

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onCapturingChange: (@MainActor (Bool) -> Void)?

    func start(onRecord: @escaping @MainActor (EchoVelaCore.KeyboardShortcut?) -> Void, onCapturingChange: @escaping @MainActor (Bool) -> Void) {
        stop()
        self.onCapturingChange = onCapturingChange
        hint = "Hold ⌃, ⌥ or ⌘ and press a key. Esc cancels."
        isRecording = true
        onCapturingChange(true)
        // EchoVela's window gets the key, so the app in front never sees it.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isEscape = event.keyCode == UInt16(kVK_Escape)
            let recorded = ShortcutRecorderModel.shortcut(from: event)
            MainActor.assumeIsolated {
                guard let self else { return }
                if isEscape {
                    self.stop()
                } else if let recorded {
                    onRecord(recorded)
                    self.stop()
                } else {
                    self.hint = "Add ⌃, ⌥ or ⌘ to the key, such as ⌃⌥L."
                }
            }
            return nil
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        isRecording = false
        hint = nil
        onCapturingChange?(false)
        onCapturingChange = nil
    }

    nonisolated private static func shortcut(from event: NSEvent) -> EchoVelaCore.KeyboardShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: ShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        // Shift alone is too easy to press while typing, so it needs a partner.
        guard !modifiers.isEmpty else { return nil }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return EchoVelaCore.KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers, keyName: keyName(for: event))
    }

    nonisolated private static func keyName(for event: NSEvent) -> String {
        let functionKeys: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        let namedKeys: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"
        ]
        let code = Int(event.keyCode)
        if let name = functionKeys[code] ?? namedKeys[code] {
            return name
        }
        let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return characters.isEmpty ? "Key \(event.keyCode)" : characters
    }
}
