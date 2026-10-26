import Foundation

public enum LaunchAtLoginPreferencePolicy {
    /// The first launch opts in; an explicit choice is always kept.
    public static func isEnabled(storedValue: Bool?) -> Bool {
        storedValue ?? true
    }
}

/// How EchoVela controls one external monitor.
public enum DisplayControlMode: String, CaseIterable, Sendable {
    /// The monitor's own backlight when it answers DDC messages, otherwise software dimming.
    case automatic
    /// Always the monitor's backlight, for monitors that accept changes but don't report values.
    case hardware
    /// Always software dimming.
    case software

    public static func stored(_ rawValue: String?) -> DisplayControlMode {
        rawValue.flatMap(Self.init(rawValue:)) ?? .automatic
    }

    /// Whether to send DDC messages, given whether the monitor answered.
    public func usesHardware(hasConnection: Bool, monitorAnswered: Bool) -> Bool {
        guard hasConnection else { return false }
        switch self {
        case .automatic: return monitorAnswered
        case .hardware: return true
        case .software: return false
        }
    }
}

/// Names shown for displays, made unique when two monitors are the same model.
public enum DisplayNaming {
    public static func uniqueNames(_ names: [String]) -> [String] {
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Display" : $0 }
        var totals: [String: Int] = [:]
        for name in cleaned {
            totals[name, default: 0] += 1
        }
        var seen: [String: Int] = [:]
        return cleaned.map { name in
            guard totals[name, default: 0] > 1 else { return name }
            seen[name, default: 0] += 1
            return "\(name) (\(seen[name, default: 1]))"
        }
    }

    /// A key that stays the same for a monitor across launches and reconnections.
    public static func storageKey(name: String, vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        let compactName = name.filter { !$0.isWhitespace }
        return "\(compactName)-\(vendor)-\(model)-\(serial)"
    }
}
