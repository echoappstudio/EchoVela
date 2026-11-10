import Foundation

/// An external monitor EchoVela knows, as far as sound goes.
public struct SoundMonitor: Equatable, Sendable {
    public let id: UInt32
    public let name: String
    /// EchoVela can change this monitor's speaker volume over DDC.
    public let hasVolume: Bool

    public init(id: UInt32, name: String, hasVolume: Bool) {
        self.id = id
        self.name = name
        self.hasVolume = hasVolume
    }
}

/// Where the Mac's sound is going, and so what EchoVela's volume slider and keys change.
public enum SoundRoute: Equatable, Sendable {
    /// A monitor's own speakers, changed over DDC.
    case monitor(UInt32)
    /// A device macOS sets the volume of itself (the Mac's speakers, headphones, AirPods).
    case mac
    /// A monitor whose volume EchoVela can't reach right now.
    case monitorWithoutVolume(UInt32)
    /// A device with no volume control at all.
    case fixed
    /// No sound output.
    case none
}

public enum SoundRouting {
    /// - Parameters:
    ///   - outputName: The name of the Mac's sound output, or nil when there is none.
    ///   - outputHasVolume: macOS can set that output's volume itself.
    ///   - monitors: The external monitors EchoVela controls.
    public static func route(outputName: String?, outputHasVolume: Bool, monitors: [SoundMonitor]) -> SoundRoute {
        guard let outputName else { return .none }
        let monitor = monitors.first { AudioDeviceMatching.matches(outputDevice: outputName, displayName: $0.name) }
        if let monitor, monitor.hasVolume {
            return .monitor(monitor.id)
        }
        if outputHasVolume {
            return .mac
        }
        if let monitor {
            return .monitorWithoutVolume(monitor.id)
        }
        return .fixed
    }
}
