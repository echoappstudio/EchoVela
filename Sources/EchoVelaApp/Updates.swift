import AppKit
import EchoVelaCore
import Observation
import Sparkle

/// EchoVela's automatic updates, through Sparkle.
///
/// Sparkle checks every hour (set in Info.plist) and once right after launch. When automatic
/// installs are on, a downloaded update is installed and EchoVela relaunched as soon as no
/// brightness change is under way. The settings live in Sparkle's own saved preferences.
@MainActor
@Observable
final class UpdateController: NSObject {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecks = false
    private(set) var automaticallyInstalls = false
    private(set) var lastCheckDate: Date?
    /// A background check found an update and EchoVela is waiting for the user to look at it.
    private(set) var updateWaiting: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var installWaitTask: Task<Void, Never>?
    @ObservationIgnored private var pendingInstall: (() -> Void)?
    @ObservationIgnored private let displays: DisplayController

    init(displays: DisplayController) {
        self.displays = displays
        super.init()
    }

    private var updater: SPUUpdater? { controller?.updater }

    /// Starts the updater, then checks right away if automatic checks are on.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.refresh(from: updater) }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.refresh(from: updater) }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.refresh(from: updater) }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.refresh(from: updater) }
            }
        ]
        refresh(from: updater)
        if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyInstalls(_ enabled: Bool) {
        updater?.automaticallyDownloadsUpdates = enabled
    }

    private func refresh(from updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyInstalls = updater.automaticallyDownloadsUpdates
        lastCheckDate = updater.lastUpdateCheckDate
    }

    /// Runs `install` once EchoVela isn't in the middle of changing brightness.
    private func installWhenIdle(_ install: @escaping () -> Void) {
        pendingInstall = install
        installWaitTask?.cancel()
        let started = Date()
        installWaitTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if UpdateInstallPolicy.canInstallNow(
                    isChangingLevels: self.displays.isChangingLevels,
                    isCheckingDisplays: self.displays.isCheckingDisplays,
                    waitedSeconds: Date().timeIntervalSince(started)
                ) {
                    self.installWaitTask = nil
                    let install = self.pendingInstall
                    self.pendingInstall = nil
                    install?()
                    return
                }
                try? await Task.sleep(for: .seconds(UpdateInstallPolicy.retryInterval))
            }
        }
    }
}

extension UpdateController: SPUUpdaterDelegate {
    /// With automatic installs on, Sparkle hands over the downloaded update; EchoVela installs and
    /// relaunches as soon as it's idle instead of waiting for the next quit.
    @objc(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installWhenIdle(immediateInstallHandler)
        return true
    }

    /// An update the user chose to install also waits for a brightness change to finish.
    @objc(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        if UpdateInstallPolicy.canInstallNow(isChangingLevels: displays.isChangingLevels, isCheckingDisplays: displays.isCheckingDisplays, waitedSeconds: 0) {
            return false
        }
        installWhenIdle(installHandler)
        return true
    }
}

/// EchoVela lives in the menu bar, so updates found in the background are shown gently: in the
/// menu bar panel instead of a window that may open behind other apps.
extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    @objc var supportsGentleScheduledUpdateReminders: Bool { true }

    @objc(standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:)
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    @objc(standardUserDriverWillHandleShowingUpdate:forUpdate:state:)
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            updateWaiting = update.displayVersionString
        }
    }

    @objc(standardUserDriverDidReceiveUserAttentionForUpdate:)
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateWaiting = nil
    }

    @objc func standardUserDriverWillFinishUpdateSession() {
        updateWaiting = nil
    }
}
