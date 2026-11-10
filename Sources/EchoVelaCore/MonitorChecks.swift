import Foundation

/// What a monitor reported over DDC in one check. A nil reading means it gave no clean answer.
public struct MonitorReadings: Equatable, Sendable {
    public var brightness: DDCReading?
    public var contrast: DDCReading?
    public var volume: DDCReading?

    public init(brightness: DDCReading? = nil, contrast: DDCReading? = nil, volume: DDCReading? = nil) {
        self.brightness = brightness
        self.contrast = contrast
        self.volume = volume
    }

    public subscript(control: DDCControl) -> DDCReading? {
        get {
            switch control {
            case .brightness: brightness
            case .contrast: contrast
            case .volume: volume
            }
        }
        set {
            switch control {
            case .brightness: brightness = newValue
            case .contrast: contrast = newValue
            case .volume: volume = newValue
            }
        }
    }

    /// The controls that got no clean answer, in the order EchoVela asks about them.
    public var unanswered: [DDCControl] {
        DDCControl.allCases.filter { self[$0] == nil }
    }

    public var isEmpty: Bool {
        brightness == nil && contrast == nil && volume == nil
    }
}

/// How EchoVela checks a monitor again after the displays change or the Mac wakes. A monitor can
/// miss a question now and then, and one waking from standby can take several seconds to answer,
/// so one missed answer must not make a slider disappear.
public enum MonitorRecheck {
    /// Seconds to wait before each new try at the questions a monitor didn't answer.
    public static let followUpDelays: [Double] = [2, 5, 15]
    /// Opening the menu-bar panel asks a monitor about its missing settings at most this often, in seconds.
    public static let panelRecheckInterval: Double = 60
    /// How many times opening the panel asks a monitor about missing settings while EchoVela runs.
    public static let panelRecheckLimit = 3

    /// What to use after a check: the monitor's new answers, and for any question it didn't answer
    /// this time, what it reported before.
    public static func merged(fresh: MonitorReadings, known: MonitorReadings?) -> MonitorReadings {
        guard let known else { return fresh }
        var result = fresh
        for control in DDCControl.allCases where result[control] == nil {
            result[control] = known[control]
        }
        return result
    }

    /// True when the monitor has stopped answering: after every try, a setting it reported before
    /// still has no answer. Settings a monitor never reported (no speakers, say) don't count.
    public static func stoppedAnswering(stillUnanswered: [DDCControl], known: MonitorReadings?) -> Bool {
        guard let known else { return false }
        return stillUnanswered.contains { known[$0] != nil }
    }
}

/// After the volume changes, EchoVela asks the monitor what its volume is, to catch a monitor that
/// quietly stopped taking changes.
public enum VolumeConfirmation {
    /// Seconds after the last volume change before EchoVela asks.
    public static let delay: Double = 0.8
    /// Seconds before a monitor that didn't answer is reconnected again.
    public static let reconnectInterval: Double = 10

    public enum Outcome: Equatable, Sendable {
        /// The monitor has the volume EchoVela sent.
        case confirmed
        /// The monitor answered with another volume: send it once more.
        case sendAgain
        /// The monitor didn't answer at all.
        case noAnswer
    }

    /// - Parameters:
    ///   - wanted: The DDC value EchoVela last sent.
    ///   - reading: What the monitor reported, or nil when it didn't answer.
    ///   - alreadySentAgain: True when the value was already sent a second time. Some monitors
    ///     report their volume on a slightly different scale, so a second difference is accepted.
    public static func outcome(wanted: UInt16, reading: DDCReading?, alreadySentAgain: Bool) -> Outcome {
        guard let reading else { return .noAnswer }
        if reading.current == wanted || alreadySentAgain {
            return .confirmed
        }
        return .sendAgain
    }
}
