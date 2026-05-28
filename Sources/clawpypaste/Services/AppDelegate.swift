import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = CrabIcon.dockImage()
        setupStatusItem()
        setupPopover()
        wireAutoDismiss()
        wireInject()
        wireGlobalHotKey()
        // Request notification permission up front so the "Screenshot ready"
        // banner can actually appear later without an inline auth race.
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    // The app that was frontmost just before our popover/menu stole focus.
    // Used by the Inject action and the "Send window screenshot" action to
    // figure out where to paste.
    private var previousFrontmostApp: NSRunningApplication?

    // Coordinator for the no-Screen-Recording-permission window-shot flow.
    private let screenshotCoordinator = WindowScreenshotCoordinator()

    // Second hotkey, for the screenshot-to-Claude shortcut.
    private var screenshotHotKey: GlobalHotKey?

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = CrabIcon.menuBarImage()
        button.image?.accessibilityDescription = "clawpypaste"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Drop target overlay — turns the icon into a "send to Claude" sink.
        // Constrained to fully cover the button at all times so drag events
        // hit the overlay regardless of when the status bar lays it out.
        let drop = MenuBarDropTarget()
        drop.onDropImage = { [weak self] img in self?.handleDroppedImage(img) }
        drop.onDropText = { [weak self] text in self?.handleDroppedText(text) }
        drop.onDropFileURL = { [weak self] url in self?.handleDroppedFileURL(url) }
        button.addSubview(drop)
        NSLayoutConstraint.activate([
            drop.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            drop.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            drop.topAnchor.constraint(equalTo: button.topAnchor),
            drop.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    // MARK: - Drop handlers

    private func handleDroppedImage(_ image: NSImage) {
        NSLog("drop: handleDroppedImage")
        notifyDrop(action: "Image")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        sendToClaudeTerminal(useControlV: true)
    }

    private func handleDroppedText(_ text: String) {
        NSLog("drop: handleDroppedText (\(text.count) chars)")
        notifyDrop(action: "Text")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        sendToClaudeTerminal(useControlV: false)
    }

    private func handleDroppedFileURL(_ url: URL) {
        NSLog("drop: handleDroppedFileURL: \(url.path)")
        notifyDrop(action: "File @-reference")
        let pb = NSPasteboard.general
        pb.clearContents()
        // Claude Code's TUI uses the `@path` convention to actually *read*
        // a referenced file. Without the leading `@` the pasted path is
        // just literal characters in the prompt. With the `@`, Claude
        // attaches the file (text, PDF, docx, etc.) as context.
        pb.setString("@\(url.path) ", forType: .string)
        sendToClaudeTerminal(useControlV: false)
    }

    private func notifyDrop(action: String) {
        let content = UNMutableNotificationContent()
        content.title = "Sending to Claude"
        content.body = "\(action) on clipboard; pasting into your terminal."
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    // Find a running terminal app and route paste there. Falls back to the
    // previously-frontmost app, then to whatever's frontmost right now.
    private func sendToClaudeTerminal(useControlV: Bool) {
        let target = findTerminalApp() ?? previousFrontmostApp ?? NSWorkspace.shared.frontmostApplication
        NSLog("drop: target = \(target?.localizedName ?? "<nil>"), useControlV = \(useControlV)")
        guard let app = target,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            NSLog("drop: no target app available; clipboard ready for manual paste")
            return
        }
        let ok = app.activate(options: [.activateAllWindows])
        NSLog("drop: activate(\(app.localizedName ?? "?")) returned \(ok)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if useControlV {
                Self.postControlV()
                NSLog("drop: ⌃V posted")
            } else {
                Self.postCommandV()
                NSLog("drop: ⌘V posted")
            }
        }
    }

    private func findTerminalApp() -> NSRunningApplication? {
        let bundles: Set<String> = [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp",
            "com.mitchellh.ghostty",
            "io.alacritty",
            "net.kovidgoyal.kitty",
            "co.zeit.hyper",
        ]
        return NSWorkspace.shared.runningApplications.first { running in
            guard let id = running.bundleIdentifier else { return false }
            return bundles.contains(id)
        }
    }

    private static func postControlV() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }
        vDown.flags = .maskControl
        vUp.flags = .maskControl
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            captureFrontmostApp()
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func captureFrontmostApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostApp = frontmost
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Send window to Claude…", action: #selector(sendWindowToClaude), keyEquivalent: "s")
            .target = self
        menu.addItem(withTitle: "Send region to Claude…", action: #selector(sendRegionToClaude), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open window", action: #selector(openDetachedWindow), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Rescan", action: #selector(rescan), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        if LoginItem.isSupported {
            let title = LoginItem.isEnabled ? "Launch at login ✓" : "Launch at login"
            menu.addItem(withTitle: title, action: #selector(toggleLoginItem), keyEquivalent: "")
                .target = self
        } else {
            let stub = menu.addItem(withTitle: "Launch at login (needs .app bundle)", action: nil, keyEquivalent: "")
            stub.isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit clawpypaste", action: #selector(quit), keyEquivalent: "q")
            .target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // detach so left-click reverts to popover
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    // MARK: - Popover

    private func setupPopover() {
        let content = MenuBarContent(
            store: store,
            onRequestOpenWindow: { [weak self] in self?.openDetachedWindow() }
        )
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: content)
    }

    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Remember what was frontmost so we can paste back into it.
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousFrontmostApp = frontmost
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Auto-dismiss on copy

    private func wireAutoDismiss() {
        store.onCopy = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.popover.performClose(nil)
            }
        }
    }

    // MARK: - Inject into previously focused app

    private func wireInject() {
        store.onInject = { [weak self] text in
            self?.injectIntoPreviousApp(text)
        }
    }

    private func injectIntoPreviousApp(_ text: String) {
        // Accessibility / Input Monitoring permission is required to post
        // synthetic key events. The first call prompts the user.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            NSLog("inject: accessibility not granted, skipping")
            // Still close the popover so the user isn't left dangling.
            popover.performClose(nil)
            return
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        popover.performClose(nil)

        let target = previousFrontmostApp
        if let target = target, target.bundleIdentifier != Bundle.main.bundleIdentifier {
            target.activate(options: [])
        }

        // Give the focus change a tick to land, then post Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Self.postCommandV()
        }
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let vUp   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
    }

    // MARK: - Global hotkey

    private func wireGlobalHotKey() {
        // Ctrl+Opt+V — easy to chord, unlikely to clash.
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: controlKey | optionKey) { [weak self] in
            DispatchQueue.main.async { self?.togglePopover() }
        }
        // Ctrl+Opt+S — send window screenshot to Claude.
        screenshotHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: controlKey | optionKey) { [weak self] in
            DispatchQueue.main.async {
                self?.captureFrontmostApp()
                self?.sendWindowToClaude()
            }
        }
    }

    // MARK: - Detached window

    private var detachedWindow: NSWindow?

    @objc func openDetachedWindow() {
        popover.performClose(nil)
        if let w = detachedWindow {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: MainView(store: store, compact: false))
        let w = NSWindow(contentViewController: host)
        w.title = "clawpypaste"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 600, height: 720))
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = WindowDelegate.shared
        detachedWindow = w
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @objc private func rescan() { store.rescan() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func sendWindowToClaude() {
        screenshotCoordinator.capture(target: previousFrontmostApp, mode: .window)
    }

    @objc private func sendRegionToClaude() {
        screenshotCoordinator.capture(target: previousFrontmostApp, mode: .region)
    }
}

// When the detached window closes, drop the activation policy back so the
// dock icon goes away again and we're a pure menu bar app once more.
final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()
    func windowWillClose(_ notification: Notification) {
        // Only flip back to accessory if no other window is open.
        if NSApp.windows.filter({ $0.isVisible }).count <= 1 {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
