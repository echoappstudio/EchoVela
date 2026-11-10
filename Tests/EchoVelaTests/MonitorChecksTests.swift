import XCTest
@testable import EchoVelaCore

final class MonitorChecksTests: XCTestCase {
    private let brightness = DDCReading(current: 40, maximum: 100)
    private let contrast = DDCReading(current: 75, maximum: 100)
    private let volume = DDCReading(current: 30, maximum: 100)

    func testReadingsListWhatWasNotAnswered() {
        let readings = MonitorReadings(brightness: brightness, volume: nil)
        XCTAssertEqual(readings.unanswered, [.contrast, .volume])
        XCTAssertEqual(MonitorReadings().unanswered, [.brightness, .contrast, .volume])
        XCTAssertTrue(MonitorReadings().isEmpty)
        XCTAssertFalse(readings.isEmpty)
    }

    func testSubscriptReadsAndWritesEachControl() {
        var readings = MonitorReadings()
        readings[.volume] = volume
        XCTAssertEqual(readings.volume, volume)
        XCTAssertEqual(readings[.volume], volume)
        XCTAssertNil(readings[.contrast])
    }

    func testAMissedVolumeAnswerKeepsTheLastKnownVolume() {
        let known = MonitorReadings(brightness: brightness, contrast: contrast, volume: volume)
        let fresh = MonitorReadings(brightness: DDCReading(current: 50, maximum: 100), contrast: contrast, volume: nil)
        let merged = MonitorRecheck.merged(fresh: fresh, known: known)
        XCTAssertEqual(merged.volume, volume)
        // New answers win over old ones.
        XCTAssertEqual(merged.brightness, DDCReading(current: 50, maximum: 100))
    }

    func testFirstCheckUsesOnlyWhatTheMonitorSaid() {
        let fresh = MonitorReadings(brightness: brightness)
        XCTAssertEqual(MonitorRecheck.merged(fresh: fresh, known: nil), fresh)
    }

    func testAMonitorThatNeverHadVolumeDoesNotGainIt() {
        let known = MonitorReadings(brightness: brightness, contrast: contrast)
        let merged = MonitorRecheck.merged(fresh: MonitorReadings(), known: known)
        XCTAssertNil(merged.volume)
        XCTAssertEqual(merged.brightness, brightness)
    }

    func testStoppedAnsweringOnlyForSettingsItReportedBefore() {
        let known = MonitorReadings(brightness: brightness, contrast: contrast)
        XCTAssertTrue(MonitorRecheck.stoppedAnswering(stillUnanswered: [.brightness], known: known))
        // It never had speakers, so a missing volume answer is normal.
        XCTAssertFalse(MonitorRecheck.stoppedAnswering(stillUnanswered: [.volume], known: known))
        XCTAssertFalse(MonitorRecheck.stoppedAnswering(stillUnanswered: [], known: known))
        // Never answered at all: it may simply not support DDC.
        XCTAssertFalse(MonitorRecheck.stoppedAnswering(stillUnanswered: [.brightness, .contrast, .volume], known: nil))
    }

    func testFollowUpsAreSpacedOutForAMonitorWakingUp() {
        XCTAssertEqual(MonitorRecheck.followUpDelays, [2, 5, 15])
        XCTAssertEqual(MonitorRecheck.followUpDelays, MonitorRecheck.followUpDelays.sorted())
    }

    func testVolumeConfirmation() {
        XCTAssertEqual(VolumeConfirmation.outcome(wanted: 30, reading: volume, alreadySentAgain: false), .confirmed)
        XCTAssertEqual(VolumeConfirmation.outcome(wanted: 45, reading: volume, alreadySentAgain: false), .sendAgain)
        // A second difference is accepted: the monitor answered, so it's listening.
        XCTAssertEqual(VolumeConfirmation.outcome(wanted: 45, reading: volume, alreadySentAgain: true), .confirmed)
        XCTAssertEqual(VolumeConfirmation.outcome(wanted: 45, reading: nil, alreadySentAgain: false), .noAnswer)
        XCTAssertEqual(VolumeConfirmation.outcome(wanted: 45, reading: nil, alreadySentAgain: true), .noAnswer)
    }

    func testBrightnessStaysPutWhenAKnownMonitorMissesTheQuestion() {
        XCTAssertEqual(StartupBrightnessPolicy.afterMissedReading(previous: 0.4, saved: 0.9), .init(level: 0.4, needsWrite: false))
        XCTAssertEqual(StartupBrightnessPolicy.afterMissedReading(previous: nil, saved: 0.9), .init(level: 0.9, needsWrite: false))
        XCTAssertEqual(StartupBrightnessPolicy.afterMissedReading(previous: nil, saved: nil), .init(level: 1, needsWrite: false))
    }
}
