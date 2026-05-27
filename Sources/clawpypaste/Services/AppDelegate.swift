import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices

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
    }

    // The app that was frontmost just before our popover stole focus. The
    // "Inject into Claude prompt" action activates this app and pastes there.
    private var previousFrontmostApp: NSRunningApplication?

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = CrabIcon.menuBarImage()
        button.image?.accessibilityDescription = "clawpypaste"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
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
