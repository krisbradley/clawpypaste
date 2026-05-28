import AppKit
import Carbon.HIToolbox
import ApplicationServices

// "Send window to Claude" without needing Screen Recording permission.
//
// Synthesizes the system shortcut Ctrl+Shift+Cmd+4 + Space (the built-in
// macOS "window screenshot to clipboard" combo). The OS handles the actual
// pixel reading — we never call any screen-capture API — so the only
// permission needed is Accessibility, which we already use for the Inject
// feature.
//
// Flow:
//   1. Note the current pasteboard changeCount
//   2. Post Ctrl+Shift+Cmd+4 (system enters "select region/window" mode)
//   3. After a short delay, post Space (mode switches to window selection)
//   4. User clicks a window; macOS captures it to the clipboard
//   5. Poll pasteboard for changeCount to bump AND for image data
//   6. On detection, activate the saved target app and paste with Cmd+V
@MainActor
final class WindowScreenshotCoordinator {
    private var timer: Timer?
    private var initialChangeCount: Int = 0
    private var deadline: Date = Date()
    private weak var targetApp: NSRunningApplication?

    func capture(target: NSRunningApplication?) {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            NSLog("screenshot: accessibility not granted")
            return
        }

        cancel()
        targetApp = target
        initialChangeCount = NSPasteboard.general.changeCount
        deadline = Date().addingTimeInterval(20)

        postCtrlShiftCmd4()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.postSpace()
        }

        // Poll clipboard every 200ms looking for the resulting image.
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.tick()
        }
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let pb = NSPasteboard.general
        if pb.changeCount != initialChangeCount, hasImageOnPasteboard() {
            cancel()
            pasteToTarget()
            return
        }
        if Date() > deadline {
            cancel()  // user probably cancelled or never clicked a window
        }
    }

    private func hasImageOnPasteboard() -> Bool {
        let pb = NSPasteboard.general
        guard let types = pb.types else { return false }
        return types.contains(.png) || types.contains(.tiff)
    }

    private func pasteToTarget() {
        if let app = targetApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate(options: [])
        }
        // Give the focus shift a tick before pasting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Self.postCommandV()
        }
    }

    // MARK: - Synthetic key events

    private func postCtrlShiftCmd4() {
        let src = CGEventSource(stateID: .hidSystemState)
        let mods: CGEventFlags = [.maskCommand, .maskShift, .maskControl]
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_4), keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_4), keyDown: false)
        else { return }
        down.flags = mods
        up.flags = mods
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postSpace() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Space), keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Space), keyDown: false)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
    }
}
