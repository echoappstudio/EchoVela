import Foundation

/// The next level for a brightness or volume key press. Levels move 5% at a time (100, 95, 90 and
/// so on down to 5), then one percent at a time below that (4, 3, 2, 1, 0), so the quiet end of the
/// scale has fine steps. With Option-Shift every press moves one percent. A level that's very close
/// to the next step skips past it, so every press makes a visible change.
public enum LevelStepping {
    /// Up to this percentage, a press moves one percent; above it, five.
    public static let singleStepLimit = 5.0
    /// The size of a normal step above the limit, in percent.
    public static let stepPercent = 5.0
    /// Where unmuting lands when there is nothing better to go back to.
    public static let minimumRestoredLevel = 0.05

    public static func next(from level: Double, up: Bool, fine: Bool) -> Double {
        let percent = Level.clamped(level) * 100
        let target: Double
        if up {
            let shifted = percent + 0.25
            if fine || shifted < singleStepLimit {
                target = shifted.rounded(.down) + 1
            } else {
                target = (shifted / stepPercent).rounded(.down) * stepPercent + stepPercent
            }
        } else {
            let shifted = percent - 0.25
            if fine || shifted <= singleStepLimit {
                target = shifted.rounded(.up) - 1
            } else {
                target = (shifted / stepPercent).rounded(.up) * stepPercent - stepPercent
            }
        }
        return Level.clamped(target / 100)
    }
}

/// Moves a level toward its target a little each animation frame, quickly at first and gently
/// at the end.
public enum SmoothTransition {
    /// Time between frames.
    public static let frameInterval: Duration = .milliseconds(20)

    public static func nextLevel(current: Double, target: Double, slow: Bool) -> Double {
        let gap = target - current
        guard abs(gap) > 0.01 else { return target }
        let step = max(abs(gap) / (slow ? 16 : 6), 0.01)
        return current + (gap > 0 ? step : -step)
    }
}
