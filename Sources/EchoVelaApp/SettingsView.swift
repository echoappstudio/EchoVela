import AppKit
import EchoVelaCore
import SwiftUI

struct SettingsView: View {
    @Environment(EchoVelaRuntime.self) private var runtime
    @AppStorage(Preferences.smoothChangesKey) private var smoothChanges = true
    @AppStorage(Preferences.extraDimmingKey) private var extraDimming = true
    @AppStorage(Preferences.linkDisplaysKey) private var linkDisplays = false
    @AppStorage(Preferences.showIndicatorKey) private var showIndicator = true

    private var launchAtLogin: LaunchAtLoginController { runtime.launchAtLogin }
    private var updates: UpdateController { runtime.updates }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "EchoVela \(version) (build \(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    PageTitle("Settings")
                    Text("Choose how EchoVela starts and how brightness changes.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                generalSettings
                brightnessSettings
                updateSettings
                aboutSection

                Label("EchoVela works entirely on this Mac. It has no accounts and no tracking. It only goes online to check GitHub for a new version of EchoVela.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(EchoVelaTheme.background)
        .frame(minWidth: 640, minHeight: 540)
        .onAppear { launchAtLogin.refreshStatus() }
        .onChange(of: extraDimming) { runtime.displays.reapplyAll() }
    }

    private var generalSettings: some View {
        GroupBox("General") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Open EchoVela when you log in", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                Text("EchoVela stays in the menu bar. Its window and Dock icon only appear when you open them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = launchAtLogin.statusMessage {
                    HStack(alignment: .firstTextBaseline) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var brightnessSettings: some View {
        GroupBox("Brightness") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Smooth brightness changes", isOn: $smoothChanges)
                Text("Brightness glides to its new level instead of jumping.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Dim below the monitor's lowest setting", isOn: $extraDimming)
                Text("The bottom quarter of the slider dims the picture further once the monitor's own brightness reaches its minimum. The screen never goes fully black.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Toggle("Move all displays together", isOn: $linkDisplays)
                Text("Any brightness slider or key changes every display to the same level.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Show the brightness indicator", isOn: $showIndicator)
                Text("A small bar in the top-right corner of the screen you changed, when you use keys, shortcuts or presets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var updateSettings: some View {
        GroupBox("Updates") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.automaticallyChecks },
                    set: { updates.setAutomaticallyChecks($0) }
                ))
                Text("EchoVela looks for a new version when it starts and then every hour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Download and install updates automatically", isOn: Binding(
                    get: { updates.automaticallyInstalls },
                    set: { updates.setAutomaticallyInstalls($0) }
                ))
                .disabled(!updates.automaticallyChecks)
                Text("EchoVela installs a new version and reopens by itself, after any brightness change has finished. Your settings and presets stay as they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text(lastCheckText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var lastCheckText: String {
        guard let date = updates.lastCheckDate else { return "Not checked yet." }
        return "Last checked \(date.formatted(date: .abbreviated, time: .shortened))."
    }

    private var aboutSection: some View {
        GroupBox("About") {
            VStack(alignment: .leading, spacing: 6) {
                Text(versionText)
                    .font(.headline)
                Text("Brightness, contrast and volume for every display on your Mac. Monitors are controlled directly over DDC where they support it, and dimmed in software where they don't.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("EchoVela on GitHub", destination: URL(string: "https://github.com/echoappstudio/EchoVela")!)
                    .font(.caption)
                Button("Acknowledgements") { Acknowledgements.open() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

/// Licenses of the code EchoVela includes, shipped in the app's Resources folder.
@MainActor
enum Acknowledgements {
    static func open() {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") else { return }
        NSWorkspace.shared.open(url)
    }
}
