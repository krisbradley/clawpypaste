import Foundation
import AppKit

// Opens a fresh terminal window and runs the given command in it.
// Used by the "Run in new Terminal" right-click action on bash-like blocks.
//
// Implementation note: we write the command to a one-shot temp script so
// multi-line commands (heredocs, conditionals, loops) survive the AppleScript
// string boundary without quoting hazards. The temp file deletes itself on
// the first line of the script so nothing lingers in /tmp.
enum Terminal {
    enum RunApp: String, CaseIterable {
        case terminal = "com.apple.Terminal"
        case iterm    = "com.googlecode.iterm2"

        var displayName: String {
            switch self {
            case .terminal: return "Terminal"
            case .iterm:    return "iTerm2"
            }
        }
    }

    // Patterns that warrant a confirmation dialog before executing. This is
    // a heuristic tripwire, not a security boundary — the goal is to catch
    // the classic foot-guns before a stray right-click runs them.
    private static let dangerousPatterns: [NSRegularExpression] = [
        #"\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+"#,      // rm -rf / rm -r / rm -f
        #"\bsudo\b"#,
        #"\bdd\s+(if|of)="#,
        #"\bmkfs\b"#,
        #">\s*/dev/(sd[a-z]|r?disk\d)"#,                // writing to raw devices
        #"\bgit\s+push\b.*(--force\b|\s-f\b)"#,
        #"\bgit\s+(reset\s+--hard|clean\s+-[a-zA-Z]*f)"#,
        #"\b(shutdown|reboot|halt)\b"#,
        #"\bkillall\b"#,
        #"\bchmod\s+(-[a-zA-Z]+\s+)*777\b"#,
        #"\bchown\s+-R\b"#,
        #"curl[^|\n]*\|\s*(ba|z)?sh\b"#,                // pipe-to-shell
        #"wget[^|\n]*\|\s*(ba|z)?sh\b"#,
        #":\(\)\s*\{"#,                                 // fork bomb
        #"\btruncate\b.*-s\s*0"#,
        #"\bdiskutil\s+(erase|partition)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    // True when the command matches a destructive pattern and the caller
    // should ask the user to confirm before running.
    static func isDangerous(_ command: String) -> Bool {
        let range = NSRange(command.startIndex..., in: command)
        return dangerousPatterns.contains { $0.firstMatch(in: command, range: range) != nil }
    }

    static func runInNewWindow(_ command: String) {
        let stripped = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawpypaste-\(UUID().uuidString).sh")

        // Script self-deletes immediately so users don't accumulate /tmp files.
        let script = """
        #!/bin/bash
        rm -f "\(tmp.path)"
        \(stripped)
        """

        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        } catch {
            return
        }

        let escapedPath = tmp.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let app = RunApp(rawValue: Preferences.shared.runCommandTerminal) ?? .terminal
        let appleScript: String
        switch app {
        case .iterm:
            appleScript = """
            tell application id "com.googlecode.iterm2"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(escapedPath)"
                end tell
            end tell
            """
        case .terminal:
            appleScript = """
            tell application "Terminal"
                activate
                do script "\(escapedPath)"
            end tell
            """
        }

        if let scriptObj = NSAppleScript(source: appleScript) {
            var error: NSDictionary?
            scriptObj.executeAndReturnError(&error)
        }
    }
}
