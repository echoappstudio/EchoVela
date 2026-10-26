import XCTest
@testable import EchoVelaCore

final class KeyboardTests: XCTestCase {
    func testDecodesBrightnessAndVolumeKeys() {
        XCTAssertEqual(MediaKeyDecoder.decode(subtype: 8, data1: 0x0002_0A00), MediaKeyPress(key: .brightnessUp, isDown: true, isRepeat: false))
        XCTAssertEqual(MediaKeyDecoder.decode(subtype: 8, data1: 0x0003_0B00), MediaKeyPress(key: .brightnessDown, isDown: false, isRepeat: false))
        XCTAssertEqual(MediaKeyDecoder.decode(subtype: 8, data1: 0x0000_0A01), MediaKeyPress(key: .volumeUp, isDown: true, isRepeat: true))
        XCTAssertEqual(MediaKeyDecoder.decode(subtype: 8, data1: 0x0007_0A00)?.key, .mute)
    }

    func testIgnoresOtherEvents() {
        XCTAssertNil(MediaKeyDecoder.decode(subtype: 7, data1: 0x0002_0A00))
        XCTAssertNil(MediaKeyDecoder.decode(subtype: 8, data1: 0x0010_0A00)) // play/pause
        XCTAssertNil(MediaKeyDecoder.decode(subtype: 8, data1: 0x0002_0C00)) // unknown state
    }

    private let builtIn = RoutableDisplay(id: 1, isNativelyControlled: true)
    private let dell = RoutableDisplay(id: 2, isNativelyControlled: false)
    private let lg = RoutableDisplay(id: 3, isNativelyControlled: false)

    func testPointerOnAnExternalMonitorIsEchoVelasAlone() {
        let route = MediaKeyRouting.route(target: .pointerDisplay, pointerDisplayID: 2, displays: [builtIn, dell, lg])
        XCTAssertEqual(route, .init(echoVelaDisplayIDs: [2], passToSystem: false))
    }

    func testPointerOnTheBuiltInDisplayGoesToMacOS() {
        let route = MediaKeyRouting.route(target: .pointerDisplay, pointerDisplayID: 1, displays: [builtIn, dell])
        XCTAssertEqual(route, .init(echoVelaDisplayIDs: [], passToSystem: true))
        XCTAssertEqual(MediaKeyRouting.route(target: .pointerDisplay, pointerDisplayID: nil, displays: [dell]), .init(echoVelaDisplayIDs: [], passToSystem: true))
    }

    func testAllDisplaysSharesTheKeyWithMacOS() {
        XCTAssertEqual(MediaKeyRouting.route(target: .allDisplays, pointerDisplayID: 2, displays: [builtIn, dell, lg]), .init(echoVelaDisplayIDs: [2, 3], passToSystem: true))
        XCTAssertEqual(MediaKeyRouting.route(target: .allDisplays, pointerDisplayID: nil, displays: [dell, lg]), .init(echoVelaDisplayIDs: [2, 3], passToSystem: false))
    }

    func testSoundOutputMatchesMonitorNames() {
        XCTAssertTrue(AudioDeviceMatching.matches(outputDevice: "DELL U2720Q", displayName: "DELL U2720Q (2)"))
        XCTAssertTrue(AudioDeviceMatching.matches(outputDevice: "LG HDR 4K", displayName: "lg hdr 4k"))
        XCTAssertFalse(AudioDeviceMatching.matches(outputDevice: "MacBook Pro Speakers", displayName: "DELL U2720Q"))
        XCTAssertFalse(AudioDeviceMatching.matches(outputDevice: "123", displayName: "456"))
    }

    func testShortcutsNeedAModifierAndDisplayLikeMacOS() throws {
        XCTAssertNil(KeyboardShortcut(keyCode: 37, modifiers: [], keyName: "L"))
        let shortcut = try XCTUnwrap(KeyboardShortcut(keyCode: 37, modifiers: [.command, .control, .option, .shift], keyName: "L"))
        XCTAssertEqual(shortcut.displayText, "⌃⌥⇧⌘L")
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(shortcut))
        XCTAssertEqual(decoded, shortcut)
        XCTAssertThrowsError(try JSONDecoder().decode(KeyboardShortcut.self, from: Data(#"{"keyCode":37,"modifiers":0,"keyName":"L"}"#.utf8)))
    }

    func testFindsWhoAlreadyUsesAShortcut() throws {
        let combo = try XCTUnwrap(KeyboardShortcut(keyCode: 37, modifiers: [.control, .option], keyName: "L"))
        let other = try XCTUnwrap(KeyboardShortcut(keyCode: 38, modifiers: [.control, .option], keyName: "J"))
        let night = UUID()
        let assignments: [ShortcutAction: KeyboardShortcut] = [.brighter: combo, .preset(night): other]
        XCTAssertEqual(ShortcutConflicts.owner(of: combo, excluding: .dimmer, in: assignments), .brighter)
        XCTAssertNil(ShortcutConflicts.owner(of: combo, excluding: .brighter, in: assignments))
        XCTAssertEqual(ShortcutConflicts.owner(of: other, excluding: .dimmer, in: assignments), .preset(night))
    }
}
