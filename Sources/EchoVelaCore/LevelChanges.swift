import Foundation

/// The next level for a brightness or volume key press. Levels move on a grid of 16 steps
/// (64 with Option-Shift), and a level that's very close to the next grid line skips past it, so
/// every press makes a visible change.
public enum LevelStepping {
    public static let steps = 16.0
    public static let fineSteps = 64.0

    public static func next(from level: Double, up: Bool, fine: Bool) -> Double {
        let count = fine ? fineSteps : steps
        let position = Level.clamped(level) * count
        let target = up ? (position + 0.25).rounded(.down) + 1 : (position - 0.25).rounded(.up) - 1
        return Level.clamped(target / count)
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
