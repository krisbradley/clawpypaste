import AppKit
import Foundation

// Polls the GitHub releases API for a newer version and exposes it to the
// UI. For cask installs the update action runs `brew upgrade` silently in
// the background and relaunches the app; otherwise it opens the releases page.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    // Set only when the remote version is strictly newer than the running one.
    @Published private(set) var availableVersion: String?

    enum UpdateState: Equatable { case idle, updating, failed(String) }
    @Published private(set) var state: UpdateState = .idle

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/clawpypaste-update.log")

    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/krisbradley/clawpypaste/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/krisbradley/clawpypaste/releases/latest")!
    private static let checkInterval: TimeInterval = 6 * 3600
    private static let lastCheckKey = "lastUpdateCheck"

    private var timer: Timer?

    private init() {}

    var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // Called once at launch. Checks immediately if the last check is stale,
    // then keeps checking on a timer while the app runs.
    func startAutomaticChecks() {
        guard Preferences.shared.checkForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if last == nil || Date().timeIntervalSince(last!) > Self.checkInterval {
            checkNow()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor in
                guard Preferences.shared.checkForUpdates else { return }
                UpdateChecker.shared.checkNow()
            }
        }
    }

    func checkNow() {
        // Running via `swift run` / CLI has no bundle version — nothing to compare.
        guard let current = currentVersion else { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else { return }
            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            Task { @MainActor in
                UpdateChecker.shared.availableVersion =
                    Self.isVersion(remote, newerThan: current) ? remote : nil
            }
        }.resume()
    }

    // True when the app was installed through the Homebrew cask, in which
    // case `brew upgrade` is the right update path (a manual drag-install
    // over a cask copy would drift from what brew thinks is installed).
    var isBrewInstall: Bool {
        ["/opt/homebrew/Caskroom/clawpypaste", "/usr/local/Caskroom/clawpypaste"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    func performUpdate() {
        guard isBrewInstall else {
            NSWorkspace.shared.open(Self.releasesPage)
            return
        }
        if case .failed = state {
            // Second click after a failure: show the output interactively.
            Terminal.runInNewWindow("brew update && brew upgrade --cask clawpypaste && open -a clawpypaste")
            state = .idle
            return
        }
        guard state != .updating, let brew = Self.brewPath else { return }
        state = .updating

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "'\(brew)' update && HOMEBREW_NO_AUTO_UPDATE=1 '\(brew)' upgrade --cask clawpypaste"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\((brew as NSString).deletingLastPathComponent):/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        task.environment = env
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        if let log = try? FileHandle(forWritingTo: Self.logURL) {
            task.standardOutput = log
            task.standardError = log
        }
        task.terminationHandler = { proc in
            let ok = proc.terminationStatus == 0
            Task { @MainActor in UpdateChecker.shared.finishUpdate(success: ok) }
        }
        do {
            try task.run()
        } catch {
            state = .failed("Couldn't run brew: \(error.localizedDescription)")
        }
    }

    private func finishUpdate(success: Bool) {
        let installed = Self.installedVersion()
        guard success, let installed, let current = currentVersion,
              Self.isVersion(installed, newerThan: current)
        else {
            state = .failed("brew upgrade failed — see \(Self.logURL.path). Click to retry in Terminal.")
            return
        }
        relaunch()
    }

    // Reads the version of the bundle now on disk (brew replaced it while
    // this older copy kept running).
    private static func installedVersion() -> String? {
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    // A detached shell waits for this process to exit, then opens the new copy.
    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open '\(path)'"]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed("Updated, but couldn't relaunch — quit and reopen clawpypaste.")
        }
    }

    private static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // Numeric dot-component comparison; missing components count as 0,
    // non-numeric components compare as 0 (good enough for our x.y.z tags).
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
