import XCTest
@testable import EchoVelaCore

final class BrightnessPresetTests: XCTestCase {
    func testDefaultsAreDayEveningAndNight() {
        XCTAssertEqual(BrightnessPresets.defaults.map(\.name), ["Day", "Evening", "Night"])
        XCTAssertEqual(BrightnessPresets.defaults.map(\.level), [1, 0.6, 0.2])
        XCTAssertEqual(Set(BrightnessPresets.defaults.map(\.id)).count, 3)
        for preset in BrightnessPresets.defaults {
            XCTAssertTrue(BrightnessPresets.symbolChoices.contains(preset.symbolName))
        }
    }

    func testMissingOrDamagedDataFallsBackToTheDefaults() {
        XCTAssertEqual(BrightnessPresets.load(from: nil), BrightnessPresets.defaults)
        XCTAssertEqual(BrightnessPresets.load(from: Data("not json".utf8)), BrightnessPresets.defaults)
        XCTAssertEqual(BrightnessPresets.load(from: Data("[]".utf8)), BrightnessPresets.defaults)
    }

    func testPresetsSurviveARoundTripWithShortcuts() throws {
        var presets = BrightnessPresets.defaults
        presets[2].shortcut = try XCTUnwrap(KeyboardShortcut(keyCode: 45, modifiers: [.control, .option], keyName: "N"))
        presets.append(BrightnessPreset(name: "Movie", symbolName: "film", level: 0.35))
        XCTAssertEqual(BrightnessPresets.load(from: BrightnessPresets.encode(presets)), presets)
    }

    func testSanitizingFixesBadValues() {
        let id = UUID()
        let messy = [
            BrightnessPreset(id: id, name: "   ", symbolName: "not.a.symbol", level: 3),
            BrightnessPreset(id: id, name: "Duplicate", symbolName: "moon", level: 0.5),
            BrightnessPreset(name: String(repeating: "x", count: 50), symbolName: "moon", level: -1)
        ]
        let cleaned = BrightnessPresets.sanitized(messy)
        XCTAssertEqual(cleaned.count, 2)
        XCTAssertEqual(cleaned[0].name, "Preset")
        XCTAssertEqual(cleaned[0].symbolName, BrightnessPresets.fallbackSymbol)
        XCTAssertEqual(cleaned[0].level, 1)
        XCTAssertEqual(cleaned[1].name.count, 30)
        XCTAssertEqual(cleaned[1].level, 0)

        let tooMany = (0 ..< 20).map { BrightnessPreset(name: "P\($0)", symbolName: "sun.max", level: 0.5) }
        XCTAssertEqual(BrightnessPresets.sanitized(tooMany).count, BrightnessPresets.maximumCount)
    }

    func testNewPresetsGetAFreeName() {
        let first = BrightnessPresets.makeNew(level: 0.42, existing: BrightnessPresets.defaults)
        XCTAssertEqual(first.name, "My Preset")
        XCTAssertEqual(first.level, 0.42)
        let second = BrightnessPresets.makeNew(level: 0.5, existing: BrightnessPresets.defaults + [first])
        XCTAssertEqual(second.name, "My Preset 2")
    }

    func testActivePresetNeedsEveryDisplayToMatch() {
        let presets = BrightnessPresets.defaults
        XCTAssertEqual(BrightnessPresets.active(in: presets, displayLevels: [0.6, 0.605])?.name, "Evening")
        XCTAssertNil(BrightnessPresets.active(in: presets, displayLevels: [0.6, 1]))
        XCTAssertNil(BrightnessPresets.active(in: presets, displayLevels: []))
    }
}
