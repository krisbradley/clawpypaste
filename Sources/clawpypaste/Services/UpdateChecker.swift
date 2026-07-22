import AppKit
import Foundation

// Polls the GitHub releases API for a newer version and exposes it to the
// UI. No auto-download — the update action either opens a Terminal running
// `brew upgrade` (for cask installs) or opens the releases page.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    // Set only when the remote version is strictly newer than the running one.
    @Published private(set) var availableVersion: String?

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
        if isBrewInstall {
            Terminal.runInNewWindow(
                "brew update && brew upgrade --cask clawpypaste && open -a clawpypaste"
            )
        } else {
            NSWorkspace.shared.open(Self.releasesPage)
        }
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
