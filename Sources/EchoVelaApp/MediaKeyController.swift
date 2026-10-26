import AppKit
import ApplicationServices
import CoreAudio
import EchoVelaCore
import Observation

/// Listens for the brightness and volume keys on Apple keyboards. EchoVela only keeps a key press
/// for itself when it handles it; everything else carries on to macOS untouched.
///
/// Watching these keys needs Accessibility permission. Without it EchoVela keeps checking every
/// two seconds while the keys are switched on, and starts listening as soon as it's allowed.
@MainActor
@Observable
final class MediaKeyController {
    private(set) var hasAccessibilityPermission = AXIsProcessTrusted()
    private(set) var isListening = false

    /// Returns true when EchoVela handled the key, so macOS shouldn't.
    @ObservationIgnored var handler: (@MainActor (MediaKeyPress, _ fine: Bool) -> Bool)?

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var wantsListening = false

    /// Starts or stops listening.
    func setEnabled(_ enabled: Bool) {
        wantsListening = enabled
        if enabled {
            startIfAllowed()
        } else {
            stop()
            permissionTask?.cancel()
            permissionTask = nil
        }
    }

    /// Shows macOS's Accessibility prompt and opens the Accessibility settings.
    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        watchForPermission()
    }

    func refreshPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        if wantsListening, hasAccessibilityPermission, !isListening {
            startIfAllowed()
        }
    }

    private func startIfAllowed() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        guard hasAccessibilityPermission else {
            watchForPermission()
            return
        }
        guard tap == nil else { return }
        let mask = CGEventMask(1) << 14 // NX_SYSDEFINED: the special keys
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            watchForPermission()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        isListening = true
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isListening = false
    }

    private func watchForPermission() {
        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.wantsListening else { break }
                self.hasAccessibilityPermission = AXIsProcessTrusted()
                if self.hasAccessibilityPermission {
                    self.startIfAllowed()
                    if self.isListening { break }
                }
            }
            self?.permissionTask = nil
        }
    }

    fileprivate func reenableTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func handle(_ press: MediaKeyPress, fine: Bool) -> Bool {
        handler?(press, fine) ?? false
    }
}

/// Runs on the main thread, because the tap's run loop source is on the main run loop.
private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<MediaKeyController>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            controller.reenableTap()
        }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let keyEvent = NSEvent(cgEvent: event) else {
        return Unmanaged.passUnretained(event)
    }
    let subtype = Int(keyEvent.subtype.rawValue)
    let data1 = keyEvent.data1
    let modifiers = keyEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let fine = modifiers.contains(.option) && modifiers.contains(.shift)
    guard let press = MediaKeyDecoder.decode(subtype: subtype, data1: data1) else {
        return Unmanaged.passUnretained(event)
    }
    let handled = MainActor.assumeIsolated {
        controller.handle(press, fine: fine)
    }
    return handled ? nil : Unmanaged.passUnretained(event)
}

/// The Mac's current sound output.
enum SoundOutput {
    static func currentDeviceName() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else {
            return nil
        }
        address.mSelector = kAudioObjectPropertyName
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
