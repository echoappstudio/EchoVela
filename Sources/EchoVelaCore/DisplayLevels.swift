import Foundation

/// Converts between EchoVela's 0–1 levels and a monitor's own DDC values.
public enum DDCLevelMapping {
    /// The largest range EchoVela trusts. Monitors that report more than 100 steps usually
    /// report it wrongly, so their scale is treated as 0–100.
    public static let largestTrustedMaximum: UInt16 = 100

    /// The range to use for a monitor's report, or nil when the report is unusable.
    public static func usableMaximum(reported: UInt16) -> UInt16? {
        guard reported > 0 else { return nil }
        return min(reported, largestTrustedMaximum)
    }

    /// The DDC value for a level. With `keepAudible`, any level above zero stays at least 1,
    /// because writing 0 to the volume control mutes some monitors until they're unplugged.
    public static func rawValue(for level: Double, maximum: UInt16, keepAudible: Bool = false) -> UInt16 {
        let clamped = Level.clamped(level)
        var raw = (clamped * Double(maximum)).rounded()
        if keepAudible, clamped > 0 {
            raw = max(raw, 1)
        }
        return UInt16(min(raw, Double(maximum)))
    }

    /// The level for a value the monitor reported.
    public static func level(forRaw raw: UInt16, maximum: UInt16) -> Double {
        guard maximum > 0 else { return 1 }
        return Level.clamped(Double(raw) / Double(maximum))
    }
}

/// The two parts of a brightness level on a monitor EchoVela controls over DDC: the monitor's own
/// backlight, and EchoVela's dimming on top of it.
public struct BrightnessSplit: Equatable, Sendable {
    /// The monitor's backlight, 0–1.
    public let hardware: Double
    /// How much of the picture EchoVela lets through, 0–1 (1 means no extra dimming).
    public let software: Double

    public init(hardware: Double, software: Double) {
        self.hardware = hardware
        self.software = software
    }
}

/// Extra dimming takes over the bottom of the brightness scale, below the monitor's lowest
/// backlight setting.
public enum ExtraDimming {
    /// Above this level the backlight changes; below it the backlight stays at its minimum and
    /// EchoVela dims the picture instead.
    public static let handoverLevel = 0.25
    /// The share of the picture that always stays visible, so a screen is never fully black.
    public static let minimumVisibility = 0.15

    public static func split(_ level: Double, isEnabled: Bool) -> BrightnessSplit {
        let level = Level.clamped(level)
        guard isEnabled else { return BrightnessSplit(hardware: level, software: 1) }
        if level >= handoverLevel {
            return BrightnessSplit(hardware: (level - handoverLevel) / (1 - handoverLevel), software: 1)
        }
        return BrightnessSplit(hardware: 0, software: level / handoverLevel)
    }

    /// The level on EchoVela's scale for a backlight value the monitor reported.
    public static func level(forHardware hardware: Double, isEnabled: Bool) -> Double {
        let hardware = Level.clamped(hardware)
        guard isEnabled else { return hardware }
        return handoverLevel + hardware * (1 - handoverLevel)
    }

    /// How dark the dimming layer over a screen is for a software level (0 = invisible).
    public static func overlayOpacity(software: Double) -> Double {
        let visible = minimumVisibility + (1 - minimumVisibility) * Level.clamped(software)
        let opacity = 1 - visible
        return opacity < 0.0005 ? 0 : opacity
    }
}

/// Where a monitor's brightness starts when EchoVela opens or the monitor reconnects.
public enum StartupBrightnessPolicy {
    public struct Decision: Equatable, Sendable {
        public let level: Double
        /// True when EchoVela must send the level to the monitor (it couldn't read the real value).
        public let needsWrite: Bool

        public init(level: Double, needsWrite: Bool) {
            self.level = level
            self.needsWrite = needsWrite
        }
    }

    /// - Parameters:
    ///   - hardware: The backlight level the monitor reported, or nil when it couldn't be read.
    ///   - saved: The level EchoVela last set on this monitor, if any.
    public static func decide(hardware: Double?, saved: Double?, extraDimming: Bool) -> Decision {
        guard let hardware else {
            if let saved {
                return Decision(level: Level.clamped(saved), needsWrite: true)
            }
            return Decision(level: 1, needsWrite: false)
        }
        // The backlight is at its minimum and EchoVela had dimmed further: keep that dimming.
        if extraDimming, hardware <= 0.001, let saved, saved < ExtraDimming.handoverLevel {
            return Decision(level: Level.clamped(saved), needsWrite: false)
        }
        return Decision(level: ExtraDimming.level(forHardware: hardware, isEnabled: extraDimming), needsWrite: false)
    }
}

/// Small helpers for 0–1 levels.
public enum Level {
    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return value > 0 ? 1 : 0 }
        return min(max(value, 0), 1)
    }

    /// "60%".
    public static func percentText(_ value: Double) -> String {
        "\(Int((clamped(value) * 100).rounded()))%"
    }

    /// True when two levels look the same on a slider.
    public static func isClose(_ first: Double, _ second: Double) -> Bool {
        abs(first - second) < 0.02
    }
}
