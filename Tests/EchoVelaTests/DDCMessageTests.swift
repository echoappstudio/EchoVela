import XCTest
@testable import EchoVelaCore

final class DDCMessageTests: XCTestCase {
    func testSetRequestHasLengthOpcodeValueAndChecksumIncludingBothAddresses() {
        XCTAssertEqual(DDCMessage.setRequest(control: 0x10, value: 50), [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        XCTAssertEqual(DDCMessage.setRequest(control: 0x62, value: 0x0102), [0x84, 0x03, 0x62, 0x01, 0x02, 0xD9])
    }

    func testGetRequestsUseTheStandardAndTheLenientChecksum() {
        XCTAssertEqual(DDCMessage.getRequest(control: 0x10), [0x82, 0x01, 0x10, 0xAC])
        XCTAssertEqual(DDCMessage.lenientGetRequest(control: 0x10), [0x82, 0x01, 0x10, 0xFD])
    }

    func testParsesAValidReply() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]
        XCTAssertEqual(DDCMessage.parseReply(reply, for: 0x10), DDCReading(current: 50, maximum: 100))
    }

    func testRejectsDamagedErrorAndEmptyReplies() {
        let valid: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]
        var badChecksum = valid
        badChecksum[10] ^= 0xFF
        XCTAssertNil(DDCMessage.parseReply(badChecksum, for: 0x10))
        XCTAssertNil(DDCMessage.parseReply(Array(valid.dropLast()), for: 0x10))

        // The monitor says "unsupported control" (result code 1); checksum is correct.
        let unsupported: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF3]
        XCTAssertNil(DDCMessage.parseReply(unsupported, for: 0x10))

        // A range of zero can't be used.
        let noRange: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA4]
        XCTAssertNil(DDCMessage.parseReply(noRange, for: 0x10))
    }

    func testRejectsAReplyAboutAnotherControl() {
        // A valid brightness reply (control 0x10) arriving while EchoVela asked about volume (0x62).
        let brightnessReply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]
        XCTAssertNil(DDCMessage.parseReply(brightnessReply, for: DDCControl.volume.rawValue))
        XCTAssertNotNil(DDCMessage.parseReply(brightnessReply, for: DDCControl.brightness.rawValue))
    }
}
