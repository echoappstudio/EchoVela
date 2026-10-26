import Foundation

/// Modifier keys a EchoVela shortcut can require.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let control = Self(rawValue: 1 << 3)

    static let supported: Self = [.command, .shift, .option, .control]

    /// "⌃⌥⇧⌘", in the order macOS shows them.
    public var symbols: String {
        let ordered: [(modifier: ShortcutModifiers, symbol: String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")
        ]
        return ordered.filter { contains($0.modifier) }.map { $0.symbol }.joined()
    }
}

/// A key and the modifiers that must be held with it.
public struct KeyboardShortcut: Codable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers
    /// What the key prints, such as "L" or "Space".
    public let keyName: String

    /// Returns nil without a modifier, or with modifiers EchoVela can't register.
    public init?(keyCode: UInt16, modifiers: ShortcutModifiers, keyName: String) {
        guard !modifiers.isEmpty, modifiers.isSubset(of: .supported) else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    /// "⌃⌥L".
    public var displayText: String {
        modifiers.symbols + keyName
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
        case keyName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let modifiers = try container.decode(ShortcutModifiers.self, forKey: .modifiers)
        let keyName = try container.decode(String.self, forKey: .keyName)
        guard let shortcut = Self(keyCode: keyCode, modifiers: modifiers, keyName: keyName) else {
            throw DecodingError.dataCorruptedError(forKey: .modifiers, in: container, debugDescription: "A shortcut needs at least one supported modifier.")
        }
        self = shortcut
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(keyName, forKey: .keyName)
    }
}

/// The things a EchoVela shortcut can do.
public enum ShortcutAction: Hashable, Sendable {
    case brighter
    case dimmer
    case preset(UUID)
}

public enum ShortcutConflicts {
    /// The other action already using `shortcut`, if any.
    public static func owner(
        of shortcut: KeyboardShortcut,
        excluding action: ShortcutAction,
        in assignments: [ShortcutAction: KeyboardShortcut]
    ) -> ShortcutAction? {
        assignments
            .filter { $0.key != action && $0.value.keyCode == shortcut.keyCode && $0.value.modifiers == shortcut.modifiers }
            .map { $0.key }
            .sorted { String(describing: $0) < String(describing: $1) }
            .first
    }
}
