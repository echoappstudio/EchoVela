import AppKit
import EchoVelaCore
import Observation
import ServiceManagement

/// The one runtime the app, its menu and its window share.
@MainActor
enum RunningApp {
    static let runtime = EchoVelaRuntime()
}

@MainActor
@Observable
final class EchoVelaRuntime {
    let displays: DisplayController
    let presets: PresetController
    let mediaKeys: MediaKeyController
    let shortcuts: ShortcutController
    let launchAtLogin: LaunchAtLoginController
    let updates: UpdateController

    @ObservationIgnored private let indicator = LevelIndicatorController()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let displays = DisplayController(defaults: defaults)
        self.displays = displays
        presets = PresetController(defaults: defaults)
        mediaKeys = MediaKeyController()
        shortcuts = ShortcutController(defaults: defaults)
        launchAtLogin = LaunchAtLoginController(defaults: defaults)
        updates = UpdateController(displays: displays)
    }

    var brightnessKeysEnabled: Bool { Preferences.isOn(Preferences.brightnessKeysKey, defaults: defaults) }
    var volumeKeysEnabled: Bool { Preferences.isOn(Preferences.volumeKeysKey, defaults: defaults) }
    var showsIndicator: Bool { Preferences.isOn(Preferences.showIndicatorKey, defaults: defaults) }

    var brightnessKeyTarget: BrightnessKeyTarget {
        BrightnessKeyTarget(rawValue: defaults.string(forKey: Preferences.brightnessKeyTargetKey) ?? "") ?? .pointerDisplay
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        mediaKeys.handler = { [weak self] press, fine in
            self?.handleMediaKey(press, fine: fine) ?? false
        }
        shortcuts.perform = { [weak self] action in
            self?.perform(action)
        }
        displays.refreshDisplays()
        shortcuts.updatePresets(presets.presets)
        updateKeyListening()
        updates.start()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDisplayRefresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDisplayRefresh() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mediaKeys.refreshPermission() }
        })
    }

    func updateKeyListening() {
        mediaKeys.setEnabled(brightnessKeysEnabled || volumeKeysEnabled)
    }

    func presetsChanged() {
        shortcuts.updatePresets(presets.presets)
    }

    /// Waits for macOS to finish rearranging displays before looking at them again.
    private func scheduleDisplayRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            self.displays.refreshDisplays()
        }
    }

    // MARK: Presets and shortcuts

    func apply(_ preset: BrightnessPreset) {
        for display in displays.displays {
            displays.setBrightness(preset.level, for: display, slow: true)
        }
        showIndicator(symbolName: preset.symbolName, title: preset.name, level: preset.level, on: NSScreen.pointerDisplayID)
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .brighter:
            stepBrightness(up: true, fine: false)
        case .dimmer:
            stepBrightness(up: false, fine: false)
        case .preset(let id):
            if let preset = presets.presets.first(where: { $0.id == id }) {
                apply(preset)
            }
        }
    }

    /// Brighter/Dimmer shortcuts change the displays the brightness keys would, including
    /// the ones macOS adjusts itself.
    private func stepBrightness(up: Bool, fine: Bool) {
        let pointerID = NSScreen.pointerDisplayID
        let targets = (brightnessKeyTarget == .allDisplays || displays.linkDisplays)
            ? displays.displays
            : displays.displays.filter { $0.id == pointerID }
        for display in targets {
            let level = displays.stepBrightness(display, up: up, fine: fine)
            showIndicator(symbolName: "sun.max.fill", title: display.name, level: level, on: display.id)
        }
    }

    // MARK: Media keys

    private func handleMediaKey(_ press: MediaKeyPress, fine: Bool) -> Bool {
        if press.key.isBrightness {
            return handleBrightnessKey(press, fine: fine)
        }
        return handleVolumeKey(press, fine: fine)
    }

    private func handleBrightnessKey(_ press: MediaKeyPress, fine: Bool) -> Bool {
        guard brightnessKeysEnabled else { return false }
        let target: BrightnessKeyTarget = displays.linkDisplays ? .allDisplays : brightnessKeyTarget
        let route = MediaKeyRouting.route(
            target: target,
            pointerDisplayID: NSScreen.pointerDisplayID,
            displays: displays.displays
                .filter { !$0.isChecking }
                .map { RoutableDisplay(id: $0.id, isNativelyControlled: $0.kind == .native) }
        )
        if press.isDown {
            for id in route.echoVelaDisplayIDs {
                guard let display = displays.display(withID: id) else { continue }
                let level = displays.stepBrightness(display, up: press.key == .brightnessUp, fine: fine)
                showIndicator(symbolName: "sun.max.fill", title: display.name, level: level, on: id)
            }
        }
        return !route.passToSystem
    }

    /// The volume keys change a monitor's speakers only while the Mac's sound goes to that monitor.
    private func handleVolumeKey(_ press: MediaKeyPress, fine: Bool) -> Bool {
        guard volumeKeysEnabled, let outputName = SoundOutput.currentDeviceName() else { return false }
        guard let display = displays.displays.first(where: {
            $0.volume != nil && AudioDeviceMatching.matches(outputDevice: outputName, displayName: $0.name)
        }) else {
            return false
        }
        guard press.isDown else { return true }
        let level: Double
        switch press.key {
        case .mute:
            guard !press.isRepeat else { return true }
            level = displays.toggleMute(display)
        case .volumeUp:
            level = displays.stepVolume(display, up: true, fine: fine)
        default:
            level = displays.stepVolume(display, up: false, fine: fine)
        }
        let symbol = level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        showIndicator(symbolName: symbol, title: display.name, level: level, on: display.id)
        return true
    }

    private func showIndicator(symbolName: String, title: String, level: Double, on displayID: CGDirectDisplayID?) {
        guard showsIndicator else { return }
        indicator.show(symbolName: symbolName, title: title, level: level, on: displayID)
    }
}

/// The saved presets.
@MainActor
@Observable
final class PresetController {
    private(set) var presets: [BrightnessPreset]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = BrightnessPresets.load(from: defaults.data(forKey: Preferences.presetsKey))
    }

    var canAdd: Bool { presets.count < BrightnessPresets.maximumCount }

    func update(_ id: UUID, _ change: (inout BrightnessPreset) -> Void) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        change(&presets[index])
        save()
    }

    func add(level: Double) {
        guard canAdd else { return }
        presets.append(BrightnessPresets.makeNew(level: level, existing: presets))
        save()
    }

    func delete(_ id: UUID) {
        guard presets.count > 1 else { return }
        presets.removeAll { $0.id == id }
        save()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard presets.indices.contains(destination) else { return }
        presets.swapAt(index, destination)
        save()
    }

    func restoreDefaults() {
        presets = BrightnessPresets.defaults
        save()
    }

    private func save() {
        presets = BrightnessPresets.sanitized(presets)
        defaults.set(BrightnessPresets.encode(presets), forKey: Preferences.presetsKey)
    }
}

/// Opens EchoVela when the Mac starts, through macOS's Login Items.
@MainActor
@Observable
final class LaunchAtLoginController {
    private(set) var isEnabled: Bool
    private(set) var statusMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let service = SMAppService.mainApp

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.object(forKey: Preferences.launchAtLoginKey) as? Bool
        isEnabled = LaunchAtLoginPreferencePolicy.isEnabled(storedValue: storedValue)
        if storedValue == nil {
            defaults.set(isEnabled, forKey: Preferences.launchAtLoginKey)
            if isEnabled, ProcessInfo.processInfo.environment["CI"] != "true" {
                register()
            }
        } else {
            refreshStatus()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Preferences.launchAtLoginKey)
        if enabled {
            register()
        } else {
            unregister()
        }
    }

    func refreshStatus() {
        switch service.status {
        case .enabled:
            statusMessage = nil
        case .requiresApproval:
            statusMessage = "macOS needs your approval. Open Login Items and allow EchoVela."
        case .notRegistered:
            statusMessage = isEnabled ? "Launch at login is on but not active yet. Turn it off and on again, or allow EchoVela in Login Items." : nil
        case .notFound:
            statusMessage = isEnabled ? "macOS couldn't find EchoVela's login item. Make sure you're opening EchoVela from Applications." : nil
        @unknown default:
            statusMessage = "macOS couldn't confirm EchoVela's login item."
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func register() {
        if service.status == .notRegistered {
            do {
                try service.register()
            } catch {
                if service.status != .requiresApproval {
                    statusMessage = "Couldn't turn on launch at login: \(error.localizedDescription)"
                    return
                }
            }
        }
        refreshStatus()
    }

    private func unregister() {
        if service.status != .notRegistered {
            do {
                try service.unregister()
            } catch {
                statusMessage = "Couldn't turn off launch at login: \(error.localizedDescription)"
                return
            }
        }
        refreshStatus()
    }
}
