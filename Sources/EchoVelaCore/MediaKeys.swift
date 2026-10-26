import Foundation

/// The special keys on Apple keyboards that EchoVela can take over.
public enum MediaKey: Int, Sendable {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7

    public var isBrightness: Bool {
        self == .brightnessUp || self == .brightnessDown
    }
}

public struct MediaKeyPress: Equatable, Sendable {
    public let key: MediaKey
    public let isDown: Bool
    public let isRepeat: Bool

    public init(key: MediaKey, isDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }
}

/// Reads media key presses out of macOS "system defined" keyboard events.
public enum MediaKeyDecoder {
    /// The event subtype macOS uses for the special keys.
    public static let auxiliaryKeySubtype = 8

    /// `data1` packs the key in its upper 16 bits, the key state (0x0A down, 0x0B up) in bits
    /// 8–15, and a repeat flag in bit 0.
    public static func decode(subtype: Int, data1: Int) -> MediaKeyPress? {
        guard subtype == auxiliaryKeySubtype else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: keyCode), state == 0x0A || state == 0x0B else { return nil }
        return MediaKeyPress(key: key, isDown: state == 0x0A, isRepeat: data1 & 0x1 == 1)
    }
}

/// Which displays the brightness keys change.
public enum BrightnessKeyTarget: String, CaseIterable, Sendable {
    case pointerDisplay
    case allDisplays
}

public struct RoutableDisplay: Equatable, Sendable {
    public let id: UInt32
    /// macOS adjusts this display itself (a built-in or Apple display).
    public let isNativelyControlled: Bool

    public init(id: UInt32, isNativelyControlled: Bool) {
        self.id = id
        self.isNativelyControlled = isNativelyControlled
    }
}

/// Decides who handles a brightness key: EchoVela changes the displays macOS can't, and macOS keeps
/// handling its own displays, so its own brightness indicator still appears for them.
public enum MediaKeyRouting {
    public struct Route: Equatable, Sendable {
        public let echoVelaDisplayIDs: [UInt32]
        public let passToSystem: Bool

        public init(echoVelaDisplayIDs: [UInt32], passToSystem: Bool) {
            self.echoVelaDisplayIDs = echoVelaDisplayIDs
            self.passToSystem = passToSystem
        }
    }

    public static func route(target: BrightnessKeyTarget, pointerDisplayID: UInt32?, displays: [RoutableDisplay]) -> Route {
        let chosen: [RoutableDisplay]
        switch target {
        case .allDisplays:
            chosen = displays
        case .pointerDisplay:
            chosen = displays.filter { $0.id == pointerDisplayID }
        }
        let echoVelaIDs = chosen.filter { !$0.isNativelyControlled }.map(\.id)
        let passToSystem = echoVelaIDs.isEmpty || chosen.contains { $0.isNativelyControlled }
        return Route(echoVelaDisplayIDs: echoVelaIDs, passToSystem: passToSystem)
    }
}

/// Matches the Mac's sound output to a monitor, so the volume keys only change the monitor's
/// speakers when sound is actually playing through them.
public enum AudioDeviceMatching {
    /// Lowercased letters only, so "DELL U2720Q (2)" and "Dell U2720Q" compare equal.
    public static func normalized(_ name: String) -> String {
        var letters = String.UnicodeScalarView()
        for scalar in name.lowercased().unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters.append(scalar)
        }
        return String(letters)
    }

    public static func matches(outputDevice: String, displayName: String) -> Bool {
        let device = normalized(outputDevice)
        return !device.isEmpty && device == normalized(displayName)
    }
}
