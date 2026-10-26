import XCTest
@testable import EchoVelaCore

final class LevelChangesTests: XCTestCase {
    private func press(_ start: Double, up: Bool, times: Int, fine: Bool = false) -> [Double] {
        var level = start
        return (0 ..< times).map { _ in
            level = LevelStepping.next(from: level, up: up, fine: fine)
            return level
        }
    }

    func testPressesMoveFivePercentAtATime() {
        XCTAssertEqual(LevelStepping.next(from: 0.5, up: true, fine: false), 0.55)
        XCTAssertEqual(LevelStepping.next(from: 0.5, up: false, fine: false), 0.45)
        XCTAssertEqual(LevelStepping.next(from: 1, up: true, fine: false), 1)
        XCTAssertEqual(LevelStepping.next(from: 0, up: false, fine: false), 0)
        XCTAssertEqual(press(1, up: false, times: 5), [0.95, 0.9, 0.85, 0.8, 0.75])
    }

    func testBelowFivePercentEachPressMovesOnePercent() {
        // Volume used to jump from 6% straight to 0; now it goes 10, 5, 4, 3, 2, 1, 0.
        XCTAssertEqual(press(0.1, up: false, times: 6), [0.05, 0.04, 0.03, 0.02, 0.01, 0])
        XCTAssertEqual(press(0, up: true, times: 7), [0.01, 0.02, 0.03, 0.04, 0.05, 0.1, 0.15])
    }

    func testOffGridLevelsSnapAndNeverMakeATinyStep() {
        XCTAssertEqual(LevelStepping.next(from: 0.53, up: true, fine: false), 0.55)
        XCTAssertEqual(LevelStepping.next(from: 0.53, up: false, fine: false), 0.5)
        // Just under 55%: up skips to 60% rather than moving a hair.
        XCTAssertEqual(LevelStepping.next(from: 0.549, up: true, fine: false), 0.6)
        // Just over 50%: down skips to 45%.
        XCTAssertEqual(LevelStepping.next(from: 0.501, up: false, fine: false), 0.45)
        XCTAssertEqual(LevelStepping.next(from: 0.049, up: true, fine: false), 0.1)
        XCTAssertEqual(LevelStepping.next(from: 0.051, up: false, fine: false), 0.04)
    }

    func testFineStepsMoveOnePercent() {
        XCTAssertEqual(LevelStepping.next(from: 0.5, up: true, fine: true), 0.51)
        XCTAssertEqual(LevelStepping.next(from: 0.5, up: false, fine: true), 0.49)
        XCTAssertEqual(LevelStepping.next(from: 0.1, up: false, fine: true), 0.09)
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
