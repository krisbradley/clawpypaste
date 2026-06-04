import Foundation
import AppKit

// Opens a fresh Terminal.app window and runs the given command in it.
// Used by the "Run in new Terminal" right-click action on bash-like blocks.
//
// Implementation note: we write the command to a one-shot temp script so
// multi-line commands (heredocs, conditionals, loops) survive the AppleScript
// string boundary without quoting hazards. The temp file deletes itself on
// the first line of the script so nothing lingers in /tmp.
enum Terminal {
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

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(escapedPath)"
        end tell
        """

        if let scriptObj = NSAppleScript(source: appleScript) {
            var error: NSDictionary?
            scriptObj.executeAndReturnError(&error)
        }
    }
}
