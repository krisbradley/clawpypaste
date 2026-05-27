import SwiftUI
import AppKit

// All menu bar / popover / window lifecycle lives in AppDelegate so we can
// drive it from a global hotkey and an NSMenu context menu without fighting
// SwiftUI's Scene lifecycle. The Settings scene below is just a sink so the
// SwiftUI runtime is happy; the visible UI is all AppKit-hosted.
@main
struct ClawpypasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if CommandLine.arguments.contains("--dump") {
            DebugDump.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--enable-login") {
            LoginItem.setEnabled(true)
            print("launch-at-login: \(LoginItem.isEnabled ? "enabled" : "FAILED — must run from .app bundle")")
            exit(LoginItem.isEnabled ? 0 : 1)
        }
        if CommandLine.arguments.contains("--disable-login") {
            LoginItem.setEnabled(false)
            print("launch-at-login: \(LoginItem.isEnabled ? "STILL enabled" : "disabled")")
            exit(0)
        }
        // CLI subcommands (clawpypaste last / search / paste / list / etc.).
        // Returns true if a subcommand was handled — we exit instead of
        // booting the SwiftUI runtime.
        if CLI.runIfPresent() {
            exit(0)
        }
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}
