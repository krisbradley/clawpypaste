import AppKit

// Opens a new iTerm2 tab (or window) and runs `claude --resume <id>` in the
// session's original working directory. Uses AppleScript through the existing
// Automation entitlement we set up for the drop activation flow — no new
// permissions needed.
enum SessionResumer {
    static func resume(sessionURL: URL, cwd: String?) {
        let sessionID = sessionURL.deletingPathExtension().lastPathComponent
        let dir = (cwd?.isEmpty == false ? cwd! : (NSString(string: "~") as String))
        let escapedDir = shellEscape(dir)
        let command = "cd \(escapedDir) && claude --resume \(sessionID)"

        // Prefer iTerm2; fall back to Terminal.app if iTerm2 isn't installed.
        if isAppInstalled(bundleID: "com.googlecode.iterm2") {
            runInITerm(command: command)
        } else {
            runInTerminalApp(command: command)
        }
    }

    private static func isAppInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static func runInITerm(command: String) {
        let escaped = appleScriptEscape(command)
        let source = """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                create window with default profile
            else
                tell current window
                    create tab with default profile
                end tell
            end if
            tell current session of current window
                write text "\(escaped)"
            end tell
        end tell
        """
        run(source)
    }

    private static func runInTerminalApp(command: String) {
        let escaped = appleScriptEscape(command)
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        run(source)
    }

    private static func run(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
