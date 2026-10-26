import XCTest
@testable import EchoVelaCore

final class SettingsPolicyTests: XCTestCase {
    func testLaunchAtLoginDefaultsOnButKeepsAChoice() {
        XCTAssertTrue(LaunchAtLoginPreferencePolicy.isEnabled(storedValue: nil))
        XCTAssertFalse(LaunchAtLoginPreferencePolicy.isEnabled(storedValue: false))
    }

    func testControlModes() {
        XCTAssertEqual(DisplayControlMode.stored(nil), .automatic)
        XCTAssertEqual(DisplayControlMode.stored("software"), .software)
        XCTAssertEqual(DisplayControlMode.stored("nonsense"), .automatic)

        XCTAssertTrue(DisplayControlMode.automatic.usesHardware(hasConnection: true, monitorAnswered: true))
        XCTAssertFalse(DisplayControlMode.automatic.usesHardware(hasConnection: true, monitorAnswered: false))
        XCTAssertTrue(DisplayControlMode.hardware.usesHardware(hasConnection: true, monitorAnswered: false))
        XCTAssertFalse(DisplayControlMode.hardware.usesHardware(hasConnection: false, monitorAnswered: false))
        XCTAssertFalse(DisplayControlMode.software.usesHardware(hasConnection: true, monitorAnswered: true))
    }

    func testDuplicateMonitorNamesAreNumbered() {
        XCTAssertEqual(
            DisplayNaming.uniqueNames(["DELL U2720Q", "Built-in Retina Display", "DELL U2720Q", " "]),
            ["DELL U2720Q (1)", "Built-in Retina Display", "DELL U2720Q (2)", "Display"]
        )
    }

    func testStorageKeysIgnoreSpaces() {
        XCTAssertEqual(DisplayNaming.storageKey(name: "DELL U2720Q", vendor: 4268, model: 41156, serial: 0), "DELLU2720Q-4268-41156-0")
    }
}
