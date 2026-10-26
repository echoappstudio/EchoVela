import Foundation

/// A saved brightness that EchoVela applies to every display at once.
public struct BrightnessPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// An SF Symbol name from `BrightnessPresets.symbolChoices`.
    public var symbolName: String
    /// 0–1.
    public var level: Double
    public var shortcut: KeyboardShortcut?

    public init(id: UUID = UUID(), name: String, symbolName: String, level: Double, shortcut: KeyboardShortcut? = nil) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.level = level
        self.shortcut = shortcut
    }
}

public enum BrightnessPresets {
    public static let maximumCount = 12
    public static let fallbackSymbol = "sun.max"
    public static let symbolChoices = [
        "sun.max", "sun.horizon", "sun.min", "moon.stars", "moon", "lightbulb",
        "desktopcomputer", "film", "book", "gamecontroller", "cup.and.saucer", "sparkles"
    ]

    /// Day, Evening and Night. Their IDs never change, so their shortcuts survive a reset.
    public static let defaults: [BrightnessPreset] = [
        BrightnessPreset(id: fixedID("2F1A6C3E-5B7D-4E21-9A0C-1D2E3F405161"), name: "Day", symbolName: "sun.max", level: 1),
        BrightnessPreset(id: fixedID("7C9E2B14-8A3F-4D56-B1E7-2A3B4C5D6E71"), name: "Evening", symbolName: "sun.horizon", level: 0.6),
        BrightnessPreset(id: fixedID("A4D8F0B2-3C6E-4F19-8B2D-3C4D5E6F7081"), name: "Night", symbolName: "moon.stars", level: 0.2)
    ]

    /// The saved presets, or the defaults when nothing usable is saved.
    public static func load(from data: Data?) -> [BrightnessPreset] {
        guard let data, let decoded = try? JSONDecoder().decode([BrightnessPreset].self, from: data) else {
            return defaults
        }
        let cleaned = sanitized(decoded)
        return cleaned.isEmpty ? defaults : cleaned
    }

    public static func encode(_ presets: [BrightnessPreset]) -> Data? {
        try? JSONEncoder().encode(sanitized(presets))
    }

    /// Fixes anything out of range: levels are clamped, names trimmed (blank becomes "Preset"),
    /// unknown symbols replaced, duplicate IDs dropped, and the list capped at `maximumCount`.
    public static func sanitized(_ presets: [BrightnessPreset]) -> [BrightnessPreset] {
        var seen = Set<UUID>()
        var result: [BrightnessPreset] = []
        for preset in presets where result.count < maximumCount && seen.insert(preset.id).inserted {
            var preset = preset
            preset.level = Level.clamped(preset.level)
            let trimmed = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            preset.name = trimmed.isEmpty ? "Preset" : String(trimmed.prefix(30))
            if !symbolChoices.contains(preset.symbolName) {
                preset.symbolName = fallbackSymbol
            }
            result.append(preset)
        }
        return result
    }

    /// A new preset for the Add button: the current brightness, under a name not used yet.
    public static func makeNew(level: Double, existing: [BrightnessPreset]) -> BrightnessPreset {
        let names = Set(existing.map { $0.name.lowercased() })
        var number = 1
        var name = "My Preset"
        while names.contains(name.lowercased()) {
            number += 1
            name = "My Preset \(number)"
        }
        return BrightnessPreset(name: name, symbolName: "lightbulb", level: Level.clamped(level))
    }

    /// The preset every display currently matches, if any.
    public static func active(in presets: [BrightnessPreset], displayLevels: [Double]) -> BrightnessPreset? {
        guard !displayLevels.isEmpty else { return nil }
        return presets.first { preset in
            displayLevels.allSatisfy { Level.isClose($0, preset.level) }
        }
    }

    private static func fixedID(_ text: String) -> UUID {
        UUID(uuidString: text) ?? UUID()
    }
}
