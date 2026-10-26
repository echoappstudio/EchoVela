import XCTest
@testable import EchoVelaCore

final class LevelChangesTests: XCTestCase {
    func testStepsMoveOneSixteenthOnTheGrid() {
        XCTAssertEqual(LevelStepping.next(from: 0.5, up: true, fine: false), 9.0 / 16)
        XCTAssertEqual(LevelStepping.next(from: 0.5, up: false, fine: false), 7.0 / 16)
        XCTAssertEqual(LevelStepping.next(from: 1, up: true, fine: false), 1)
        XCTAssertEqual(LevelStepping.next(from: 0, up: false, fine: false), 0)
    }

    func testOffGridLevelsSnapAndNeverMakeATinyStep() {
        // Between 8/16 and 9/16: up goes to 9/16, down to 8/16.
        XCTAssertEqual(LevelStepping.next(from: 0.53, up: true, fine: false), 9.0 / 16)
        XCTAssertEqual(LevelStepping.next(from: 0.53, up: false, fine: false), 8.0 / 16)
        // Just under 9/16: up skips to 10/16 rather than moving a hair.
        XCTAssertEqual(LevelStepping.next(from: 0.56, up: true, fine: false), 10.0 / 16)
        // Just over 8/16: down skips to 7/16.
        XCTAssertEqual(LevelStepping.next(from: 0.505, up: false, fine: false), 7.0 / 16)
    }

    func testFineStepsUseSixtyFourths() {
        XCTAssertEqual(LevelStepping.next(from: 0.5, up: true, fine: true), 33.0 / 64)
        XCTAssertEqual(LevelStepping.next(from: 0.5, up: false, fine: true), 31.0 / 64)
    }

    func testSmoothTransitionsReachTheTargetExactly() {
        var level = 0.0
        var frames = 0
        while level != 1, frames < 200 {
            level = SmoothTransition.nextLevel(current: level, target: 1, slow: false)
            frames += 1
        }
        XCTAssertEqual(level, 1)
        XCTAssertLessThan(frames, 60)

        var slowLevel = 1.0
        var slowFrames = 0
        while slowLevel != 0.2, slowFrames < 500 {
            slowLevel = SmoothTransition.nextLevel(current: slowLevel, target: 0.2, slow: true)
            slowFrames += 1
        }
        XCTAssertEqual(slowLevel, 0.2)
        XCTAssertGreaterThan(slowFrames, frames)
    }

    func testSmoothTransitionsMoveAtLeastOnePercentAndNeverOvershoot() {
        XCTAssertEqual(SmoothTransition.nextLevel(current: 0.5, target: 0.505, slow: false), 0.505)
        XCTAssertEqual(SmoothTransition.nextLevel(current: 0.5, target: 0.52, slow: false), 0.51, accuracy: 0.000001)
        XCTAssertEqual(SmoothTransition.nextLevel(current: 0.8, target: 0.2, slow: false), 0.7, accuracy: 0.000001)
    }
}
