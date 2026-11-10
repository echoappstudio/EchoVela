import XCTest
@testable import EchoVelaCore

final class SoundRoutingTests: XCTestCase {
    private let dell = SoundMonitor(id: 2, name: "DELL S2725QC", hasVolume: true)

    func testSoundOnTheMonitorUsesItsSpeakers() {
        XCTAssertEqual(SoundRouting.route(outputName: "DELL S2725QC", outputHasVolume: false, monitors: [dell]), .monitor(2))
    }

    func testSoundOnTheMacUsesTheMacsVolume() {
        XCTAssertEqual(SoundRouting.route(outputName: "MacBook Pro Speakers", outputHasVolume: true, monitors: [dell]), .mac)
        XCTAssertEqual(SoundRouting.route(outputName: "AirPods Pro", outputHasVolume: true, monitors: []), .mac)
    }

    func testAMonitorWithoutVolumeFallsBackToMacOSWhenItCanChangeIt() {
        let noVolume = SoundMonitor(id: 2, name: "DELL S2725QC", hasVolume: false)
        XCTAssertEqual(SoundRouting.route(outputName: "DELL S2725QC", outputHasVolume: true, monitors: [noVolume]), .mac)
        XCTAssertEqual(SoundRouting.route(outputName: "DELL S2725QC", outputHasVolume: false, monitors: [noVolume]), .monitorWithoutVolume(2))
    }

    func testOutputsWithoutAnyVolume() {
        XCTAssertEqual(SoundRouting.route(outputName: "HDMI", outputHasVolume: false, monitors: [dell]), .fixed)
        XCTAssertEqual(SoundRouting.route(outputName: nil, outputHasVolume: false, monitors: [dell]), .none)
    }

    func testNamesMatchLikeTheVolumeKeysAlwaysDid() {
        let second = SoundMonitor(id: 3, name: "DELL S2725QC (2)", hasVolume: true)
        XCTAssertEqual(SoundRouting.route(outputName: "Dell S2725QC", outputHasVolume: false, monitors: [second]), .monitor(3))
    }
}
