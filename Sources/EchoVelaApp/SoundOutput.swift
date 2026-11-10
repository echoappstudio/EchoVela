import AudioToolbox
import CoreAudio
import Observation

/// The Mac's current sound output and its volume, kept up to date as you switch outputs
/// (speakers, headphones, a monitor) or change the volume elsewhere.
@MainActor
@Observable
final class SoundOutputController {
    /// The output's name, such as "MacBook Pro Speakers"; nil when there is no output.
    private(set) var deviceName: String?
    /// macOS can set this output's volume itself (monitors over HDMI or DisplayPort usually can't).
    private(set) var hasVolume = false
    /// 0–1.
    private(set) var volume: Double = 0
    private(set) var isMuted = false

    @ObservationIgnored private var deviceID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var canMute = false
    @ObservationIgnored private var volumeBeforeMute = 0.25
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var deviceListeners: [(selector: AudioObjectPropertySelector, block: AudioObjectPropertyListenerBlock)] = []

    private static let watchedDeviceProperties: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyMute
    ]

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Reads the current output and its volume again.
    func refresh() {
        let current = Self.defaultOutputDevice()
        if current != deviceID {
            stopWatchingDevice()
            deviceID = current
            watchDevice()
        }
        guard current != kAudioObjectUnknown else {
            deviceName = nil
            hasVolume = false
            isMuted = false
            return
        }
        deviceName = Self.name(of: current)
        hasVolume = Self.isSettable(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, of: current)
        canMute = Self.isSettable(kAudioDevicePropertyMute, of: current)
        if let level = Self.float(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, of: current) {
            volume = Double(min(max(level, 0), 1))
            if volume > 0 {
                volumeBeforeMute = volume
            }
        }
        isMuted = canMute ? (Self.uint(kAudioDevicePropertyMute, of: current) ?? 0) != 0 : volume == 0
    }

    func setVolume(_ level: Double) {
        guard hasVolume else { return }
        let level = min(max(level, 0), 1)
        Self.setFloat(Float32(level), kAudioHardwareServiceDeviceProperty_VirtualMainVolume, of: deviceID)
        if level > 0, canMute, isMuted {
            Self.setUInt(0, kAudioDevicePropertyMute, of: deviceID)
        }
        refresh()
    }

    func toggleMute() {
        if canMute {
            Self.setUInt(isMuted ? 0 : 1, kAudioDevicePropertyMute, of: deviceID)
            refresh()
        } else if hasVolume {
            setVolume(volume > 0 ? 0 : max(volumeBeforeMute, 0.05))
        }
    }

    // MARK: Watching the current output

    private func watchDevice() {
        guard deviceID != kAudioObjectUnknown else { return }
        for selector in Self.watchedDeviceProperties {
            var address = Self.address(selector)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block) == noErr {
                deviceListeners.append((selector, block))
            }
        }
    }

    private func stopWatchingDevice() {
        for listener in deviceListeners {
            var address = Self.address(listener.selector)
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, listener.block)
        }
        deviceListeners.removeAll()
    }

    // MARK: Core Audio

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return AudioObjectID(kAudioObjectUnknown)
        }
        return deviceID
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func isSettable(_ selector: AudioObjectPropertySelector, of device: AudioObjectID) -> Bool {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private static func float(_ selector: AudioObjectPropertySelector, of device: AudioObjectID) -> Float32? {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func uint(_ selector: AudioObjectPropertySelector, of device: AudioObjectID) -> UInt32? {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func setFloat(_ value: Float32, _ selector: AudioObjectPropertySelector, of device: AudioObjectID) {
        var address = address(selector)
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private static func setUInt(_ value: UInt32, _ selector: AudioObjectPropertySelector, of device: AudioObjectID) {
        var address = address(selector)
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
