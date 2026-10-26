import Foundation

/// When EchoVela may quit to install an update that has already downloaded.
public enum UpdateInstallPolicy {
    /// How often EchoVela asks the waiting installer again once it's busy.
    public static let retryInterval: TimeInterval = 15
    /// A monitor that never finishes answering mustn't hold an update back forever.
    public static let longestDisplayCheckWait: TimeInterval = 10 * 60

    /// Brightness that is still gliding always waits; a slow monitor check only waits for a while.
    public static func canInstallNow(isChangingLevels: Bool, isCheckingDisplays: Bool, waitedSeconds: TimeInterval) -> Bool {
        if isChangingLevels {
            return false
        }
        return !isCheckingDisplays || waitedSeconds >= longestDisplayCheckWait
    }
}
