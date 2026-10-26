import Foundation

/// UserDefaults keys for EchoVela's settings.
enum Preferences {
    static let extraDimmingKey = "EchoVela.extraDimming"
    static let smoothChangesKey = "EchoVela.smoothChanges"
    static let linkDisplaysKey = "EchoVela.linkDisplays"
    static let showIndicatorKey = "EchoVela.showIndicator"
    static let brightnessKeysKey = "EchoVela.brightnessKeys"
    static let brightnessKeyTargetKey = "EchoVela.brightnessKeyTarget"
    static let volumeKeysKey = "EchoVela.volumeKeys"
    static let presetsKey = "EchoVela.presets"
    static let brighterShortcutKey = "EchoVela.shortcut.brighter"
    static let dimmerShortcutKey = "EchoVela.shortcut.dimmer"
    static let hasLaunchedKey = "EchoVela.hasLaunched"
    static let launchAtLoginKey = "EchoVela.launchAtLogin"

    static func displayKey(_ storageKey: String, _ setting: String) -> String {
        "EchoVela.display.\(storageKey).\(setting)"
    }

    /// A Bool setting that's on until the user turns it off.
    static func isOn(_ key: String, defaultValue: Bool = true, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
