import XCTest
@testable import EchoVelaCore

final class DisplayLevelsTests: XCTestCase {
    func testDDCValuesRoundAndStayInRange() {
        XCTAssertEqual(DDCLevelMapping.rawValue(for: 0.5, maximum: 100), 50)
        XCTAssertEqual(DDCLevelMapping.rawValue(for: 0.333, maximum: 100), 33)
        XCTAssertEqual(DDCLevelMapping.rawValue(for: 1.4, maximum: 100), 100)
        XCTAssertEqual(DDCLevelMapping.rawValue(for: -1, maximum: 100), 0)
        XCTAssertEqual(DDCLevelMapping.rawValue(for: .nan, maximum: 100), 0)
        XCTAssertEqual(DDCLevelMapping.level(forRaw: 25, maximum: 50), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DDCLevelMapping.level(forRaw: 80, maximum: 50), 1)
    }

    func testVolumeNeverMutesByAccident() {
        XCTAssertEqual(DDCLevelMapping.rawValue(for: 0.002, maximum: 100, keepAudible: true), 1)
        XCTAssertEqual(DDCLevelMapping.rawValue(for: 0, maximum: 100, keepAudible: true), 0)
        XCTAssertEqual(DDCLevelMapping.rawValue(for: 0.002, maximum: 100), 0)
    }

    func testOnlyTrustsSensibleRanges() {
        XCTAssertNil(DDCLevelMapping.usableMaximum(reported: 0))
        XCTAssertEqual(DDCLevelMapping.usableMaximum(reported: 80), 80)
        XCTAssertEqual(DDCLevelMapping.usableMaximum(reported: 65535), 100)
    }

    func testExtraDimmingTakesTheBottomQuarter() {
        XCTAssertEqual(ExtraDimming.split(1, isEnabled: true), BrightnessSplit(hardware: 1, software: 1))
        XCTAssertEqual(ExtraDimming.split(0.25, isEnabled: true), BrightnessSplit(hardware: 0, software: 1))
        let middle = ExtraDimming.split(0.625, isEnabled: true)
        XCTAssertEqual(middle.hardware, 0.5, accuracy: 0.0001)
        XCTAssertEqual(middle.software, 1)
        let dimmed = ExtraDimming.split(0.125, isEnabled: true)
        XCTAssertEqual(dimmed.hardware, 0)
        XCTAssertEqual(dimmed.software, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ExtraDimming.split(0.1, isEnabled: false), BrightnessSplit(hardware: 0.1, software: 1))
    }

    func testHardwareLevelsMapBackOntoTheUpperScale() {
        XCTAssertEqual(ExtraDimming.level(forHardware: 0, isEnabled: true), 0.25, accuracy: 0.0001)
        XCTAssertEqual(ExtraDimming.level(forHardware: 0.5, isEnabled: true), 0.625, accuracy: 0.0001)
        XCTAssertEqual(ExtraDimming.level(forHardware: 1, isEnabled: true), 1, accuracy: 0.0001)
        XCTAssertEqual(ExtraDimming.level(forHardware: 0.4, isEnabled: false), 0.4, accuracy: 0.0001)
    }

    func testTheScreenNeverGoesFullyBlack() {
        XCTAssertEqual(ExtraDimming.overlayOpacity(software: 1), 0)
        XCTAssertEqual(ExtraDimming.overlayOpacity(software: 0), 0.85, accuracy: 0.0001)
        XCTAssertEqual(ExtraDimming.overlayOpacity(software: 0.5), 0.425, accuracy: 0.0001)
        XCTAssertEqual(ExtraDimming.overlayOpacity(software: -3), 0.85, accuracy: 0.0001)
    }

    func testStartupUsesTheMonitorAndKeepsExtraDimming() {
        let fromMonitor = StartupBrightnessPolicy.decide(hardware: 0.5, saved: 0.9, extraDimming: true)
        XCTAssertEqual(fromMonitor.level, 0.625, accuracy: 0.0001)
        XCTAssertFalse(fromMonitor.needsWrite)

        XCTAssertEqual(
            StartupBrightnessPolicy.decide(hardware: 0, saved: 0.1, extraDimming: true),
            .init(level: 0.1, needsWrite: false)
        )
        // At its minimum but EchoVela hadn't dimmed further: the top of the dimming range.
        XCTAssertEqual(
            StartupBrightnessPolicy.decide(hardware: 0, saved: 0.6, extraDimming: true),
            .init(level: 0.25, needsWrite: false)
        )
        XCTAssertEqual(
            StartupBrightnessPolicy.decide(hardware: 0.3, saved: 0.1, extraDimming: false),
            .init(level: 0.3, needsWrite: false)
        )
    }

    func testStartupWithoutAReadingRestoresTheSavedLevel() {
        XCTAssertEqual(StartupBrightnessPolicy.decide(hardware: nil, saved: 0.4, extraDimming: true), .init(level: 0.4, needsWrite: true))
        XCTAssertEqual(StartupBrightnessPolicy.decide(hardware: nil, saved: nil, extraDimming: true), .init(level: 1, needsWrite: false))
    }

    func testPercentText() {
        XCTAssertEqual(Level.percentText(0.6), "60%")
        XCTAssertEqual(Level.percentText(0.005), "1%")
        XCTAssertEqual(Level.percentText(2), "100%")
        XCTAssertTrue(Level.isClose(0.6, 0.61))
        XCTAssertFalse(Level.isClose(0.6, 0.63))
    }
}
