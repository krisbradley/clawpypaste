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
        applyAppearancePreference()
        setupStatusItem()
        setupPopover()
        wireAutoDismiss()
        wireInject()
        wireGlobalHotKey()
        UpdateChecker.shared.startAutomaticChecks()
        // Look-and-feel observer: re-apply menu bar icon + appearance when
        // any preference changes (it's a single notification stream).
        NotificationCenter.default.addObserver(
            forName: .preferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearancePreference()
            self?.refreshStatusItemIcon()
        }
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
        button.image = CrabIcon.menuBarImage(style: currentIconStyle)
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
        guard Preferences.shared.showNotifications else { return }
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
        Self.fileLog("sendToClaudeTerminal: target = \(target?.localizedName ?? "<nil>"), bundleID = \(target?.bundleIdentifier ?? "<nil>")")
        guard let app = target,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let bundleID = app.bundleIdentifier
        else {
            Self.fileLog("sendToClaudeTerminal: bailing — no usable target")
            return
        }

        let source = "tell application id \"\(bundleID)\" to activate"
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            Self.fileLog("AppleScript result: descriptorType=\(result.descriptorType), error=\(error.map { "\($0)" } ?? "<nil>")")
        } else {
            Self.fileLog("NSAppleScript init returned nil")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if useControlV {
                Self.postControlV()
                Self.fileLog("posted ⌃V")
            } else {
                Self.postCommandV()
                Self.fileLog("posted ⌘V")
            }
        }
    }

    // NSLog from notarized Swift apps is filtered out of `log show`, so we
    // write diagnostic output to a file we can tail.
    static func fileLog(_ msg: String) {
        let path = NSString(string: "~/Library/Logs/clawpypaste.log").expandingTildeInPath
        let line = "[\(Date())] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // Ordered by preference. Terminal.app is last because macOS often has it
    // running in the background even when the user is actually working in
    // iTerm2 / Warp / Ghostty / etc. — picking it would activate an
    // invisible Terminal window and silently swallow the paste.
    private static let preferredTerminalBundleIDs: [String] = [
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.apple.Terminal",
    ]

    private func findTerminalApp() -> NSRunningApplication? {
        // Honor an explicit user preference if it's actually running.
        let preferred = Preferences.shared.preferredTerminalBundleID
        if !preferred.isEmpty,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == preferred })
        {
            return app
        }
        // If the frontmost app is itself a terminal (rare during a drag,
        // common for the inject + popover paths), honor that.
        if let front = NSWorkspace.shared.frontmostApplication,
           let id = front.bundleIdentifier,
           Self.preferredTerminalBundleIDs.contains(id)
        {
            return front
        }
        let running = NSWorkspace.shared.runningApplications
        for bundleID in Self.preferredTerminalBundleIDs {
            if let app = running.first(where: { $0.bundleIdentifier == bundleID }) {
                return app
            }
        }
        return nil
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

    // MARK: - Look & feel

    private var currentIconStyle: Preferences.IconStyle {
        Preferences.IconStyle(rawValue: Preferences.shared.menuBarIconStyle) ?? .silhouette
    }

    private func refreshStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let img = CrabIcon.menuBarImage(style: currentIconStyle)
        img.accessibilityDescription = "clawpypaste"
        button.image = img
    }

    private func applyAppearancePreference() {
        let raw = Preferences.shared.appearance
        let style = Preferences.AppearanceStyle(rawValue: raw) ?? .system
        switch style {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        if let v = UpdateChecker.shared.availableVersion {
            menu.addItem(withTitle: "Update available — v\(v)…", action: #selector(performUpdate), keyEquivalent: "")
                .target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Send window to Claude…", action: #selector(sendWindowToClaude), keyEquivalent: "s")
            .target = self
        menu.addItem(withTitle: "Send region to Claude…", action: #selector(sendRegionToClaude), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open window", action: #selector(openDetachedWindow), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "About clawpypaste", action: #selector(openAbout), keyEquivalent: "")
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

    @objc private func performUpdate() {
        UpdateChecker.shared.performUpdate()
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    // MARK: - Popover

    private func setupPopover() {
        let content = MenuBarContent(
            store: store,
            onRequestOpenWindow: { [weak self] in self?.openDetachedWindow() },
            onOpenPreferences: { [weak self] in self?.openPreferences() }
        )
        popover = NSPopover()
        popover.contentSize = popoverSize()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: content)
    }

    private func popoverSize() -> NSSize {
        Preferences.shared.compactPopover
            ? NSSize(width: 380, height: 440)
            : NSSize(width: 420, height: 520)
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
        applyHotkeyPreferences()
        NotificationCenter.default.addObserver(
            forName: .preferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyHotkeyPreferences()
        }
    }

    // Second hotkey for region screenshot.
    private var regionScreenshotHotKey: GlobalHotKey?
    private var copyLatestHotKey: GlobalHotKey?

    private func applyHotkeyPreferences() {
        let prefs = Preferences.shared

        if let h = prefs.popoverHotkey {
            hotKey = GlobalHotKey(keyCode: h.keyCode, modifiers: Int(h.modifiers)) { [weak self] in
                DispatchQueue.main.async { self?.togglePopover() }
            }
        } else {
            hotKey = nil
        }

        if let h = prefs.windowScreenshotHotkey {
            screenshotHotKey = GlobalHotKey(keyCode: h.keyCode, modifiers: Int(h.modifiers)) { [weak self] in
                DispatchQueue.main.async {
                    self?.captureFrontmostApp()
                    self?.sendWindowToClaude()
                }
            }
        } else {
            screenshotHotKey = nil
        }

        if let h = prefs.regionScreenshotHotkey {
            regionScreenshotHotKey = GlobalHotKey(keyCode: h.keyCode, modifiers: Int(h.modifiers)) { [weak self] in
                DispatchQueue.main.async {
                    self?.captureFrontmostApp()
                    self?.sendRegionToClaude()
                }
            }
        } else {
            regionScreenshotHotKey = nil
        }

        if let h = prefs.copyLatestHotkey {
            copyLatestHotKey = GlobalHotKey(keyCode: h.keyCode, modifiers: Int(h.modifiers)) { [weak self] in
                DispatchQueue.main.async {
                    self?.store.copyLatestMatching(kindRaw: prefs.copyLatestKind)
                }
            }
        } else {
            copyLatestHotKey = nil
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
        let host = NSHostingController(rootView: SessionBrowserView(store: store))
        let w = NSWindow(contentViewController: host)
        w.title = "clawpypaste"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 1000, height: 640))
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

    // MARK: - Preferences window

    private var preferencesWindow: NSWindow?

    @objc private func openAbout() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let credits = NSAttributedString(
            string: """
            Menu bar block picker and session browser for Claude Code.

            github.com/krisbradley/clawpypaste
            MIT License
            """,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "clawpypaste",
            .applicationVersion: version,
            .credits: credits,
        ])
    }

    @objc private func openPreferences() {
        if let w = preferencesWindow {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: PreferencesView())
        let w = NSWindow(contentViewController: host)
        w.title = "clawpypaste — Preferences"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 520, height: 360))
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = WindowDelegate.shared
        preferencesWindow = w
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
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
