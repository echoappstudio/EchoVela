import AppKit
import Observation
import SwiftUI

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    /// The display the pointer is on.
    static var pointerDisplayID: CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) }?.displayID
    }
}

/// Software dimming: a black layer over a whole screen, above everything (menu bar and Dock
/// included). It ignores the mouse, and macOS removes it the moment EchoVela quits.
@MainActor
final class DimmingOverlayController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    func setOpacity(_ opacity: Double, for displayID: CGDirectDisplayID) {
        guard opacity > 0 else {
            windows[displayID]?.orderOut(nil)
            return
        }
        guard let screen = NSScreen.screen(for: displayID) else { return }
        let window = windows[displayID] ?? makeWindow()
        windows[displayID] = window
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
        }
        window.alphaValue = opacity
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    /// Drops layers for displays that are gone and refits the rest after a display change.
    func keepOnly(_ displayIDs: Set<CGDirectDisplayID>) {
        for (displayID, window) in windows {
            if displayIDs.contains(displayID), let screen = NSScreen.screen(for: displayID) {
                window.setFrame(screen.frame, display: false)
            } else {
                window.orderOut(nil)
                windows[displayID] = nil
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Keep the dimming out of screenshots and screen sharing where macOS allows it.
        window.sharingType = .none
        return window
    }
}

// MARK: - Brightness indicator

@MainActor
@Observable
final class LevelIndicatorModel {
    var symbolName = "sun.max.fill"
    var title = ""
    var level = 0.0
}

/// A small glass pill in the top-right corner of the screen that changed, like the macOS 26
/// volume and brightness indicators.
@MainActor
final class LevelIndicatorController {
    private let model = LevelIndicatorModel()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private static let size = NSSize(width: 300, height: 64)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: LevelIndicatorView(model: model))
    }

    func show(symbolName: String, title: String, level: Double, on displayID: CGDirectDisplayID?) {
        model.symbolName = symbolName
        model.title = title
        model.level = level
        let screen = displayID.flatMap { NSScreen.screen(for: $0) } ?? NSScreen.main
        if let screen {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.maxX - Self.size.width - 8, y: area.maxY - Self.size.height - 6))
        }
        hideTask?.cancel()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.panel.animator().alphaValue = 0
            }
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
        }
    }
}

private struct LevelIndicatorView: View {
    let model: LevelIndicatorModel

    private var percentText: String {
        "\(Int((min(max(model.level, 0), 1) * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.symbolName)
                .font(.title2)
                .foregroundStyle(EchoVelaTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(percentText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LevelBar(level: model.level)
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 300, height: 64)
        .glassEffect()
    }
}

/// A rounded bar filled with the accent silver.
struct LevelBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(EchoVelaTheme.accent)
                    .frame(width: proxy.size.width * min(max(level, 0), 1))
            }
        }
    }
}
