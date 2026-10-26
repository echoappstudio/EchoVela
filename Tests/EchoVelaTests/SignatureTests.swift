import XCTest
@testable import EchoVelaCore

final class SignatureTests: XCTestCase {
    func testHexColoursConvert() {
        let colour = RGB(hex: 0xE6E7EA)
        XCTAssertEqual(colour.red, 230.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(colour.green, 231.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(colour.blue, 234.0 / 255, accuracy: 0.0001)
    }

    func testContrastRunsFromOneToTwentyOne() {
        let black = RGB(hex: 0x000000)
        let white = RGB(hex: 0xFFFFFF)
        XCTAssertEqual(RGB.contrast(black, white), 21, accuracy: 0.001)
        XCTAssertEqual(RGB.contrast(white, white), 1, accuracy: 0.001)
    }

    func testEveryPairIsReadableInLightAndDark() {
        for dark in [true, false] {
            let palette = Signature.palette(dark: dark)
            // Text on an accent surface, and the accent itself on each background it sits on.
            XCTAssertGreaterThanOrEqual(RGB.contrast(palette.accent, palette.onAccent), 7, "text on accent, dark: \(dark)")
            for background in [palette.window, palette.surface, palette.sidebar] {
                XCTAssertGreaterThanOrEqual(RGB.contrast(palette.accent, background), 7, "accent on background, dark: \(dark)")
            }
        }
    }

    func testDarkAndLightAreDifferent() {
        XCTAssertNotEqual(Signature.palette(dark: true), Signature.palette(dark: false))
        XCTAssertEqual(Signature.palette(dark: true).accent, RGB(hex: 0xE6E7EA))
        XCTAssertEqual(Signature.palette(dark: false).window, RGB(hex: 0xF3F3F4))
    }
}
