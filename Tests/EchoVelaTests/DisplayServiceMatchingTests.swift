import XCTest
@testable import EchoVelaCore

final class DisplayServiceMatchingTests: XCTestCase {
    // A Dell monitor: vendor 0x10AC, product 0xA0C4 (stored low byte first), week 12 of 2021,
    // 600 × 340 mm.
    private let dell = DisplayIdentity(
        displayID: 2,
        vendorID: 0x10AC,
        productID: 0xA0C4,
        serialNumber: 12345,
        weekOfManufacture: 12,
        yearOfManufacture: 2021,
        horizontalSize: 600,
        verticalSize: 340,
        productName: "DELL U2720Q",
        registryLocation: "IOService:/AppleARMPE/arm-io/disp0"
    )

    func testEDIDPartsMatchTheUUIDLayout() {
        XCTAssertEqual(DisplayServiceMatching.edidParts(of: dell).map { $0.hex }, ["10AC", "C4A0", "0C1F", "3C22"])
        XCTAssertEqual(DisplayServiceMatching.edidParts(of: dell).map { $0.offset }, [0, 4, 19, 30])
        XCTAssertEqual(DisplayServiceMatching.edidSegment("10acc4a0-0000-0000-0c1f-01043c22", at: 0), "10AC")
        XCTAssertNil(DisplayServiceMatching.edidSegment("10AC", at: 4))
    }

    func testScoresEveryMatchingDetail() {
        let full = DDCServiceCandidate(
            index: 1,
            edidUUID: "10ACC4A0-0000-0000-0C1F-0104B53C2278",
            productName: "dell u2720q",
            serialNumber: 12345,
            registryLocation: "IOService:/AppleARMPE/arm-io/disp0"
        )
        XCTAssertEqual(DisplayServiceMatching.score(dell, full), 16)
        XCTAssertEqual(DisplayServiceMatching.score(dell, DDCServiceCandidate(index: 2, edidUUID: "10ACC4A0-0000-0000-0000-000000000000")), 2)
        XCTAssertEqual(DisplayServiceMatching.score(dell, DDCServiceCandidate(index: 3)), 0)
    }

    func testIgnoresEmptyEDIDParts() {
        let blank = DisplayIdentity(displayID: 9)
        XCTAssertEqual(DisplayServiceMatching.score(blank, DDCServiceCandidate(index: 1, edidUUID: "00000000-0000-0000-0000-000000000000")), 0)
    }

    func testAssignsBestPairsFirstAndUsesEachConnectionOnce() {
        let lg = DisplayIdentity(displayID: 3, vendorID: 0x1E6D, productID: 0x5B10, productName: "LG HDR 4K")
        let dellConnection = DDCServiceCandidate(index: 1, edidUUID: "10ACC4A0-0000-0000-0C1F-01043C22780A", productName: "DELL U2720Q")
        let lgConnection = DDCServiceCandidate(index: 2, edidUUID: "1E6D105B-0000-0000-0000-000000000000", productName: "LG HDR 4K")
        let result = DisplayServiceMatching.assign(displays: [dell, lg], candidates: [lgConnection, dellConnection])
        XCTAssertEqual(result, [2: 1, 3: 2])
    }

    func testTwoIdenticalMonitorsSplitByLocation() {
        var left = dell
        left.displayID = 4
        left.registryLocation = "disp0"
        var right = dell
        right.displayID = 5
        right.registryLocation = "dispext0"
        let first = DDCServiceCandidate(index: 1, edidUUID: "10ACC4A0", registryLocation: "dispext0")
        let second = DDCServiceCandidate(index: 2, edidUUID: "10ACC4A0", registryLocation: "disp0")
        XCTAssertEqual(DisplayServiceMatching.assign(displays: [left, right], candidates: [first, second]), [4: 2, 5: 1])
    }

    func testNoPairWithoutAnythingInCommon() {
        XCTAssertEqual(DisplayServiceMatching.assign(displays: [dell], candidates: [DDCServiceCandidate(index: 1)]), [:])
    }
}
