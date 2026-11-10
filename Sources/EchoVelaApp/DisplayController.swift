import AppKit
import CoreGraphics
import EchoVelaCore
import Observation

/// How EchoVela changes one display's brightness.
enum DisplayKind: Equatable {
    /// A built-in or Apple display: macOS's own brightness control.
    case native
    /// An external monitor's own backlight over DDC, plus EchoVela's extra dimming below it.
    case hardware
    /// EchoVela's dimming layer only.
    case software
}

@MainActor
@Observable
final class EchoVelaDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let storageKey: String
    let isBuiltIn: Bool
    /// An external monitor EchoVela could reach over DDC.
    let hasConnection: Bool

    var kind: DisplayKind
    /// Where the brightness is heading; what the sliders show. 0–1.
    var brightness: Double
    /// Nil when the monitor didn't report a contrast setting.
    var contrast: Double?
    /// Nil when the monitor didn't report a volume setting.
    var volume: Double?
    /// The monitor answered DDC messages when EchoVela asked for its brightness.
    var monitorAnswered = false
    /// True until EchoVela has finished asking the monitor what it supports.
    var isChecking: Bool
    /// The monitor stopped answering DDC: changes may not be reaching it.
    var isNotAnswering = false
    /// EchoVela is asking the monitor again about settings it didn't answer.
    var isAskingAgain = false

    @ObservationIgnored var connection: DDCConnection?
    /// The brightness currently on screen while a smooth change is under way.
    @ObservationIgnored var shownBrightness: Double
    @ObservationIgnored var slowTransition = false
    @ObservationIgnored var brightnessMaximum: UInt16 = 100
    @ObservationIgnored var contrastMaximum: UInt16 = 100
    @ObservationIgnored var volumeMaximum: UInt16 = 100
    @ObservationIgnored var volumeBeforeMute = 0.25
    /// The volume EchoVela last sent, as the monitor's own DDC value.
    @ObservationIgnored var sentVolume: UInt16?

    init(id: CGDirectDisplayID, name: String, storageKey: String, isBuiltIn: Bool, kind: DisplayKind, brightness: Double, connection: DDCConnection?) {
        self.id = id
        self.name = name
        self.storageKey = storageKey
        self.isBuiltIn = isBuiltIn
        self.kind = kind
        self.brightness = brightness
        self.shownBrightness = brightness
        self.connection = connection
        self.hasConnection = connection != nil
        self.isChecking = kind != .native
    }

    var kindDescription: String {
        switch kind {
        case .native:
            return isBuiltIn ? "Built-in display, adjusted by macOS" : "Apple display, adjusted by macOS"
        case .hardware:
            return monitorAnswered ? "The monitor's own brightness (DDC)" : "The monitor's own brightness (DDC, values not reported)"
        case .software:
            return hasConnection ? "Software dimming (the monitor didn't answer DDC)" : "Software dimming"
        }
    }

    var kindSymbol: String {
        switch kind {
        case .native: "apple.logo"
        case .hardware: "cable.connector"
        case .software: "circle.lefthalf.filled"
        }
    }
}

/// Finds the connected displays and changes their brightness, contrast and volume.
@MainActor
@Observable
final class DisplayController {
    private(set) var displays: [EchoVelaDisplay] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let overlays = DimmingOverlayController()
    @ObservationIgnored private var animationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// What each monitor (by settings key) last reported over DDC, for as long as EchoVela runs.
    @ObservationIgnored private var known: [String: MonitorReadings] = [:]
    /// Tries again at questions a monitor didn't answer, per monitor.
    @ObservationIgnored private var followUps: [String: Task<Void, Never>] = [:]
    /// Asks a monitor whether it took a volume change, per monitor.
    @ObservationIgnored private var volumeChecks: [String: Task<Void, Never>] = [:]
    /// A volume to send again once a reconnected monitor answers, per monitor.
    @ObservationIgnored private var volumeAfterReconnect: [String: UInt16] = [:]
    @ObservationIgnored private var lastReconnect: [String: Date] = [:]
    @ObservationIgnored private var lastPanelRecheck: [String: Date] = [:]
    @ObservationIgnored private var panelRecheckCount: [String: Int] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var extraDimming: Bool { defaults.object(forKey: Preferences.extraDimmingKey) as? Bool ?? true }
    var smoothChanges: Bool { defaults.object(forKey: Preferences.smoothChangesKey) as? Bool ?? true }
    var linkDisplays: Bool { defaults.object(forKey: Preferences.linkDisplaysKey) as? Bool ?? false }

    func display(withID id: CGDirectDisplayID) -> EchoVelaDisplay? {
        displays.first { $0.id == id }
    }

    /// True while brightness is still gliding to a new level.
    var isChangingLevels: Bool { animationTask != nil }

    /// True while a monitor is still being asked what it supports.
    var isCheckingDisplays: Bool { displays.contains { $0.isChecking } }

    // MARK: Finding displays

    /// Looks for displays again. Called at launch, after a display is connected or rearranged,
    /// and after the Mac wakes.
    func refreshDisplays() {
        generation += 1
        let currentGeneration = generation
        let previous = displays
        for display in previous {
            display.connection?.retire()
        }
        for task in followUps.values { task.cancel() }
        followUps.removeAll()
        for task in volumeChecks.values { task.cancel() }
        volumeChecks.removeAll()
        let ids = onlineDisplayIDs()

        var nativeIDs = Set<CGDirectDisplayID>()
        var virtualIDs = Set<CGDirectDisplayID>()
        var rawNames: [CGDirectDisplayID: String] = [:]
        var identities: [DisplayIdentity] = []
        for id in ids {
            let info = SystemDisplayFunctions.info(for: id)
            rawNames[id] = displayName(id, info: info)
            if isVirtual(info) {
                virtualIDs.insert(id)
            } else if isNative(id) {
                nativeIDs.insert(id)
            } else {
                identities.append(identity(id, info: info, name: rawNames[id] ?? ""))
            }
        }

        var keys: [CGDirectDisplayID: String] = [:]
        var usedKeys = Set<String>()
        for (offset, id) in ids.enumerated() {
            var key = DisplayNaming.storageKey(
                name: rawNames[id] ?? "",
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id)
            )
            if !usedKeys.insert(key).inserted {
                key += "#\(offset)"
                usedKeys.insert(key)
            }
            keys[id] = key
        }

        let found = DDCConnectionFinder.findExternalConnections()
        let assignments = DisplayServiceMatching.assign(displays: identities, candidates: found.map(\.candidate))
        var connections: [CGDirectDisplayID: DDCConnection] = [:]
        var usedServices = Set<Int>()
        for item in found {
            if let displayID = assignments.first(where: { $0.value == item.candidate.index })?.key,
               connections[displayID] == nil, usedServices.insert(item.candidate.index).inserted {
                connections[displayID] = DDCConnection(service: item.service, monitorKey: keys[displayID] ?? "\(displayID)")
            } else {
                SystemDisplayFunctions.releaseAVService(item.service)
            }
        }

        let names = DisplayNaming.uniqueNames(ids.map { rawNames[$0] ?? "" })
        var newDisplays: [EchoVelaDisplay] = []
        var previousLevels: [String: Double] = [:]
        for (offset, id) in ids.enumerated() {
            let key = keys[id] ?? ""
            let isNative = nativeIDs.contains(id)
            let display = EchoVelaDisplay(
                id: id,
                name: names[offset],
                storageKey: key,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                kind: isNative ? .native : .software,
                brightness: isNative ? (SystemDisplayFunctions.nativeBrightness(of: id) ?? 1) : (savedBrightness(forKey: key) ?? 1),
                connection: virtualIDs.contains(id) ? nil : connections[id]
            )
            // A monitor that had stopped answering keeps saying so until it answers again.
            if let old = previous.first(where: { $0.storageKey == key && $0.kind != .native }) {
                previousLevels[key] = old.brightness
                display.isNotAnswering = old.isNotAnswering
            }
            newDisplays.append(display)
        }

        overlays.keepOnly(Set(ids.filter { !nativeIDs.contains($0) }))
        displays = newDisplays
        for display in newDisplays where display.kind != .native {
            let previousLevel = previousLevels[display.storageKey]
            Task { await prepare(display, generation: currentGeneration, previousLevel: previousLevel) }
        }
    }

    /// Asks an external monitor what it supports, then puts its brightness where it belongs.
    /// Anything a monitor reported before but doesn't answer now keeps its last value, and
    /// EchoVela asks again a few times (a monitor waking from standby can be slow to answer).
    /// - Parameter previousLevel: The brightness EchoVela showed for this monitor before the displays
    ///   changed, if it was already set up.
    private func prepare(_ display: EchoVelaDisplay, generation expectedGeneration: Int, previousLevel: Double? = nil) async {
        let key = display.storageKey
        let mode = controlMode(for: display)
        let saved = savedBrightness(forKey: key)
        let asks = display.connection != nil && mode != .software
        var fresh = MonitorReadings()

        display.isChecking = true
        if let connection = display.connection, asks {
            for control in DDCControl.allCases {
                fresh[control] = await connection.read(control)
            }
        }
        guard expectedGeneration == generation else { return }

        let levels = asks ? MonitorRecheck.merged(fresh: fresh, known: known[key]) : MonitorReadings()
        if !levels.isEmpty {
            known[key] = levels
        }
        var hardwareLevel: Double?
        if let reading = levels.brightness, let maximum = DDCLevelMapping.usableMaximum(reported: reading.maximum) {
            display.brightnessMaximum = maximum
            if fresh.brightness != nil {
                hardwareLevel = DDCLevelMapping.level(forRaw: reading.current, maximum: maximum)
            }
        }
        display.monitorAnswered = levels.brightness != nil
        let usesHardware = mode.usesHardware(hasConnection: display.connection != nil, monitorAnswered: display.monitorAnswered)
        display.kind = usesHardware ? .hardware : .software
        show(levels, on: display, usesHardware: usesHardware)

        let decision: StartupBrightnessPolicy.Decision
        if usesHardware, levels.brightness != nil, fresh.brightness == nil {
            decision = StartupBrightnessPolicy.afterMissedReading(previous: previousLevel, saved: saved)
        } else if usesHardware {
            decision = StartupBrightnessPolicy.decide(hardware: hardwareLevel, saved: saved, extraDimming: extraDimming)
        } else {
            decision = StartupBrightnessPolicy.Decision(level: saved ?? 1, needsWrite: true)
        }
        display.brightness = decision.level
        display.shownBrightness = decision.level
        display.isChecking = false
        apply(display, level: decision.level, sendToMonitor: decision.needsWrite)

        let missing = asks ? fresh.unanswered : []
        if fresh.volume != nil {
            resendVolumeAfterReconnect(display)
        }
        if missing.isEmpty {
            display.isNotAnswering = false
        } else {
            if volumeAfterReconnect[key] != nil, missing.contains(.volume) {
                // A reconnect after a volume change that didn't arrive: still no answer.
                display.isNotAnswering = true
            }
            askAgain(display, about: missing, after: MonitorRecheck.followUpDelays)
        }
    }

    /// Shows the contrast and volume a monitor reported (or last reported).
    private func show(_ levels: MonitorReadings, on display: EchoVelaDisplay, usesHardware: Bool) {
        var contrast: Double?
        var volume: Double?
        if usesHardware, let reading = levels.contrast, let maximum = DDCLevelMapping.usableMaximum(reported: reading.maximum) {
            display.contrastMaximum = maximum
            contrast = DDCLevelMapping.level(forRaw: reading.current, maximum: maximum)
        }
        if usesHardware, let reading = levels.volume, let maximum = DDCLevelMapping.usableMaximum(reported: reading.maximum) {
            display.volumeMaximum = maximum
            volume = DDCLevelMapping.level(forRaw: reading.current, maximum: maximum)
        }
        display.contrast = contrast
        display.volume = volume
        if let volume, volume > 0 {
            display.volumeBeforeMute = volume
        }
    }

    /// Asks a monitor again, after each delay, about the settings it didn't answer. A monitor that
    /// answers for the first time (it was asleep when EchoVela started) is set up properly. If it
    /// still hasn't answered about something it reported before, it's marked as not answering.
    private func askAgain(_ display: EchoVelaDisplay, about controls: [DDCControl], after delays: [Double]) {
        let key = display.storageKey
        let expectedGeneration = generation
        followUps[key]?.cancel()
        display.isAskingAgain = true
        followUps[key] = Task { [weak self] in
            var missing = controls
            for delay in delays {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, expectedGeneration == self.generation,
                      let connection = display.connection else { return }
                var fresh = MonitorReadings()
                for control in missing {
                    fresh[control] = await connection.read(control)
                }
                guard !Task.isCancelled, expectedGeneration == self.generation else { return }

                if fresh.brightness != nil, !display.monitorAnswered {
                    // First answer from this monitor: set it up from the start. That check
                    // takes over from this one.
                    display.isAskingAgain = false
                    self.followUps[key] = nil
                    await self.prepare(display, generation: expectedGeneration, previousLevel: display.brightness)
                    return
                }
                var levels = self.known[key] ?? MonitorReadings()
                for control in missing {
                    if let reading = fresh[control] {
                        levels[control] = reading
                    }
                }
                if !levels.isEmpty {
                    self.known[key] = levels
                }
                if display.kind == .hardware {
                    if fresh.contrast != nil || fresh.volume != nil {
                        self.show(levels, on: display, usesHardware: true)
                    }
                    if let reading = fresh.brightness, let maximum = DDCLevelMapping.usableMaximum(reported: reading.maximum) {
                        display.brightnessMaximum = maximum
                    }
                }
                if fresh.volume != nil {
                    self.resendVolumeAfterReconnect(display)
                }
                missing = fresh.unanswered.filter { missing.contains($0) }
                if missing.isEmpty { break }
            }
            guard !Task.isCancelled, let self, expectedGeneration == self.generation else { return }
            display.isNotAnswering = MonitorRecheck.stoppedAnswering(stillUnanswered: missing, known: self.known[key])
            display.isAskingAgain = false
            self.followUps[key] = nil
            // A volume waiting for a reconnect is only sent during that reconnect's checks, never
            // much later, when it could undo a change made on the monitor itself.
            self.volumeAfterReconnect[key] = nil
        }
    }

    /// Opening the menu-bar panel asks again about anything missing (at most once a minute per
    /// monitor, and a few times per session, so a monitor without speakers isn't asked forever).
    /// A monitor that stopped answering is reconnected every time.
    func recheckMissingSettings() {
        let now = Date()
        for display in displays where display.kind != .native && !display.isChecking && display.connection != nil {
            let key = display.storageKey
            guard controlMode(for: display) != .software, followUps[key] == nil else { continue }
            var missing: [DDCControl] = []
            if !display.monitorAnswered { missing.append(.brightness) }
            if display.contrast == nil { missing.append(.contrast) }
            if display.volume == nil { missing.append(.volume) }
            guard !missing.isEmpty || display.isNotAnswering else { continue }
            if let last = lastPanelRecheck[key], now.timeIntervalSince(last) < MonitorRecheck.panelRecheckInterval { continue }
            if display.isNotAnswering {
                lastPanelRecheck[key] = now
                reconnect(display)
                return
            }
            guard panelRecheckCount[key, default: 0] < MonitorRecheck.panelRecheckLimit else { continue }
            lastPanelRecheck[key] = now
            panelRecheckCount[key, default: 0] += 1
            askAgain(display, about: missing, after: [0])
        }
    }

    /// "Check Again": makes fresh connections to every monitor and asks them everything.
    func checkAgain() {
        lastReconnect.removeAll()
        refreshDisplays()
    }

    /// Makes fresh connections (a monitor's connection can go stale after hours of standby) and
    /// asks every monitor again. At most once every few seconds per monitor.
    private func reconnect(_ display: EchoVelaDisplay) {
        let key = display.storageKey
        let now = Date()
        if let last = lastReconnect[key], now.timeIntervalSince(last) < VolumeConfirmation.reconnectInterval {
            display.isNotAnswering = true
            return
        }
        lastReconnect[key] = now
        if let sent = display.sentVolume {
            volumeAfterReconnect[key] = sent
        }
        refreshDisplays()
    }

    /// Sends the volume a reconnect was waiting to deliver, now that the monitor answers.
    private func resendVolumeAfterReconnect(_ display: EchoVelaDisplay) {
        guard let raw = volumeAfterReconnect.removeValue(forKey: display.storageKey),
              display.kind == .hardware, display.volume != nil, let connection = display.connection else { return }
        display.volume = DDCLevelMapping.level(forRaw: raw, maximum: display.volumeMaximum)
        display.sentVolume = raw
        display.isNotAnswering = false
        connection.submit(.volume, value: raw, always: true)
        confirmVolume(display, sentAgain: true)
    }

    // MARK: Changing levels

    /// Sets brightness from a slider. With "Move all displays together" on, every display follows.
    func setBrightnessFromSlider(_ level: Double, for display: EchoVelaDisplay) {
        let targets = linkDisplays ? displays : [display]
        for target in targets {
            setBrightness(level, for: target)
        }
    }

    func setBrightness(_ level: Double, for display: EchoVelaDisplay, slow: Bool = false) {
        guard !display.isChecking else { return }
        let level = Level.clamped(level)
        display.brightness = level
        display.slowTransition = slow
        if display.kind != .native {
            defaults.set(level, forKey: Preferences.displayKey(display.storageKey, "brightness"))
        }
        if smoothChanges {
            startAnimating()
        } else {
            display.shownBrightness = level
            apply(display, level: level, sendToMonitor: true)
        }
    }

    /// One brightness step up or down; returns the new level.
    @discardableResult
    func stepBrightness(_ display: EchoVelaDisplay, up: Bool, fine: Bool) -> Double {
        if display.kind == .native, display.shownBrightness == display.brightness,
           let current = SystemDisplayFunctions.nativeBrightness(of: display.id) {
            display.brightness = current
            display.shownBrightness = current
        }
        let next = LevelStepping.next(from: display.brightness, up: up, fine: fine)
        setBrightness(next, for: display)
        return next
    }

    func setContrast(_ level: Double, for display: EchoVelaDisplay) {
        guard display.contrast != nil, let connection = display.connection else { return }
        let level = Level.clamped(level)
        display.contrast = level
        connection.submit(.contrast, value: DDCLevelMapping.rawValue(for: level, maximum: display.contrastMaximum), always: true)
    }

    func setVolume(_ level: Double, for display: EchoVelaDisplay) {
        guard display.volume != nil, let connection = display.connection else { return }
        let level = Level.clamped(level)
        display.volume = level
        if level > 0 {
            display.volumeBeforeMute = level
        }
        let raw = DDCLevelMapping.rawValue(for: level, maximum: display.volumeMaximum, keepAudible: true)
        display.sentVolume = raw
        connection.submit(.volume, value: raw, always: true)
        confirmVolume(display, sentAgain: false)
    }

    /// Shortly after the last volume change, asks the monitor whether it took it. A different
    /// answer is sent again once; no answer at all reconnects the monitor.
    private func confirmVolume(_ display: EchoVelaDisplay, sentAgain: Bool) {
        let key = display.storageKey
        let expectedGeneration = generation
        volumeChecks[key]?.cancel()
        volumeChecks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(VolumeConfirmation.delay))
            guard !Task.isCancelled, let self, expectedGeneration == self.generation,
                  let connection = display.connection, let wanted = display.sentVolume else { return }
            let reading = await connection.read(.volume)
            guard !Task.isCancelled, expectedGeneration == self.generation, display.sentVolume == wanted else { return }
            self.volumeChecks[key] = nil
            switch VolumeConfirmation.outcome(wanted: wanted, reading: reading, alreadySentAgain: sentAgain) {
            case .confirmed:
                display.isNotAnswering = false
            case .sendAgain:
                connection.submit(.volume, value: wanted, always: true)
                self.confirmVolume(display, sentAgain: true)
            case .noAnswer:
                self.reconnect(display)
            }
        }
    }

    @discardableResult
    func stepVolume(_ display: EchoVelaDisplay, up: Bool, fine: Bool) -> Double {
        let next = LevelStepping.next(from: display.volume ?? 0, up: up, fine: fine)
        setVolume(next, for: display)
        return next
    }

    /// Mutes, or puts the volume back where it was.
    @discardableResult
    func toggleMute(_ display: EchoVelaDisplay) -> Double {
        let next = (display.volume ?? 0) > 0 ? 0 : max(display.volumeBeforeMute, LevelStepping.minimumRestoredLevel)
        setVolume(next, for: display)
        return next
    }

    func setControlMode(_ mode: DisplayControlMode, for display: EchoVelaDisplay) {
        defaults.set(mode.rawValue, forKey: Preferences.displayKey(display.storageKey, "controlMode"))
        overlays.setOpacity(0, for: display.id)
        followUps.removeValue(forKey: display.storageKey)?.cancel()
        display.isAskingAgain = false
        let currentGeneration = generation
        let previousLevel = display.brightness
        Task { await prepare(display, generation: currentGeneration, previousLevel: previousLevel) }
    }

    func controlMode(for display: EchoVelaDisplay) -> DisplayControlMode {
        DisplayControlMode.stored(defaults.string(forKey: Preferences.displayKey(display.storageKey, "controlMode")))
    }

    /// Re-sends every level, after extra dimming is switched on or off.
    func reapplyAll() {
        for display in displays where !display.isChecking && display.kind != .native {
            display.shownBrightness = display.brightness
            apply(display, level: display.brightness, sendToMonitor: true)
        }
    }

    /// Picks up brightness changes macOS made on its own displays (keys, ambient light).
    func refreshNativeLevels() {
        for display in displays where display.kind == .native && display.shownBrightness == display.brightness {
            if let current = SystemDisplayFunctions.nativeBrightness(of: display.id) {
                display.brightness = current
                display.shownBrightness = current
            }
        }
    }

    // MARK: Applying

    private func apply(_ display: EchoVelaDisplay, level: Double, sendToMonitor: Bool) {
        switch display.kind {
        case .native:
            SystemDisplayFunctions.setNativeBrightness(level, of: display.id)
        case .hardware:
            let split = ExtraDimming.split(level, isEnabled: extraDimming)
            if sendToMonitor {
                display.connection?.submit(.brightness, value: DDCLevelMapping.rawValue(for: split.hardware, maximum: display.brightnessMaximum))
            }
            overlays.setOpacity(ExtraDimming.overlayOpacity(software: split.software), for: display.id)
        case .software:
            overlays.setOpacity(ExtraDimming.overlayOpacity(software: level), for: display.id)
        }
    }

    private func startAnimating() {
        guard animationTask == nil else { return }
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.advanceAnimations() else { break }
                try? await Task.sleep(for: SmoothTransition.frameInterval)
            }
            self?.animationTask = nil
        }
    }

    /// Moves every changing display one frame closer; returns true while any is still moving.
    private func advanceAnimations() -> Bool {
        var stillMoving = false
        for display in displays where !display.isChecking && display.shownBrightness != display.brightness {
            let next = SmoothTransition.nextLevel(current: display.shownBrightness, target: display.brightness, slow: display.slowTransition)
            display.shownBrightness = next
            apply(display, level: next, sendToMonitor: true)
            if next != display.brightness {
                stillMoving = true
            }
        }
        return stillMoving
    }

    // MARK: Display details

    private func savedBrightness(forKey key: String) -> Double? {
        (defaults.object(forKey: Preferences.displayKey(key, "brightness")) as? NSNumber)?.doubleValue
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
        // A display that mirrors another shows the same picture; EchoVela controls the original.
        return ids.prefix(Int(count)).filter { $0 != 0 && CGDisplayMirrorsDisplay($0) == 0 }
    }

    private func isVirtual(_ info: [String: Any]) -> Bool {
        (info["kCGDisplayIsVirtualDevice"] as? NSNumber)?.boolValue == true
            || (info["kCGDisplayIsAirPlay"] as? NSNumber)?.boolValue == true
    }

    /// Built-in displays and Apple displays use macOS's own brightness. Some non-Apple HDR
    /// monitors also answer macOS's brightness call but ignore it, so they're excluded.
    private func isNative(_ id: CGDirectDisplayID) -> Bool {
        if CGDisplayIsBuiltin(id) != 0 { return true }
        guard SystemDisplayFunctions.nativeBrightness(of: id) != nil else { return false }
        let appleVendorID: UInt32 = 0x610
        return CGDisplayVendorNumber(id) == appleVendorID || !SystemDisplayFunctions.isHDROn(id)
    }

    private func displayName(_ id: CGDirectDisplayID, info: [String: Any]) -> String {
        if let screen = NSScreen.screen(for: id) {
            return screen.localizedName
        }
        if let names = info["DisplayProductName"] as? [String: String], let name = names["en_US"] ?? names.values.first {
            return name
        }
        return CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display"
    }

    private func identity(_ id: CGDirectDisplayID, info: [String: Any], name: String) -> DisplayIdentity {
        func number(_ key: String) -> Int {
            (info[key] as? NSNumber)?.intValue ?? 0
        }
        var productName = name
        if let names = info["DisplayProductName"] as? [String: String], let english = names["en_US"] ?? names.values.first {
            productName = english
        }
        return DisplayIdentity(
            displayID: id,
            vendorID: number("DisplayVendorID") != 0 ? number("DisplayVendorID") : Int(CGDisplayVendorNumber(id)),
            productID: number("DisplayProductID") != 0 ? number("DisplayProductID") : Int(CGDisplayModelNumber(id)),
            serialNumber: number("DisplaySerialNumber"),
            weekOfManufacture: number("DisplayWeekManufacture"),
            yearOfManufacture: number("DisplayYearManufacture"),
            horizontalSize: number("DisplayHorizontalImageSize"),
            verticalSize: number("DisplayVerticalImageSize"),
            productName: productName,
            registryLocation: info["IODisplayLocation"] as? String ?? ""
        )
    }
}
