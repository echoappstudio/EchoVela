import AppKit
import EchoVelaCore
import SwiftUI

@main
@MainActor
struct EchoVelaApp: App {
    @NSApplicationDelegateAdaptor(EchoVelaApplicationDelegate.self) private var applicationDelegate
    @State private var runtime = RunningApp.runtime
    /// The window opens by itself only the first time, so people see what EchoVela is.
    private let isFirstLaunch: Bool

    init() {
        let defaults = UserDefaults.standard
        isFirstLaunch = !defaults.bool(forKey: Preferences.hasLaunchedKey)
        defaults.set(true, forKey: Preferences.hasLaunchedKey)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(runtime)
        } label: {
            Image(nsImage: MenuBarGlyph.image)
        }
        .menuBarExtraStyle(.window)

        Window("EchoVela", id: EchoVelaWindow.main) {
            MainWindowView()
                .environment(runtime)
                .onAppear { EchoVelaWindow.didOpen() }
                .onDisappear { EchoVelaWindow.didClose() }
        }
        .defaultSize(width: 980, height: 760)
        .defaultLaunchBehavior(isFirstLaunch ? .presented : .suppressed)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { runtime.updates.checkForUpdates() }
                    .disabled(!runtime.updates.canCheckForUpdates)
            }
        }
    }
}

/// EchoVela lives in the menu bar; it shows a Dock icon only while its window is open.
@MainActor
enum EchoVelaWindow {
    static let main = "main"

    static func didOpen() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func didClose() {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class EchoVelaApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        RunningApp.runtime.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
