import Foundation
import Carbon.HIToolbox

// User-configurable settings, backed by UserDefaults. Anything that lives
// here can be reset via PreferencesView and is observed by AppDelegate so
// global hotkeys re-register the instant the user changes them.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    struct Hotkey: Codable, Equatable {
        let keyCode: UInt32
        let modifiers: UInt32   // Carbon modifier mask (cmdKey | optionKey | ...)
        let keyName: String     // pretty display name, e.g. "V", "Space"
    }

    @Published var popoverHotkey: Hotkey? {
        didSet { write(popoverHotkey, for: .popover); didChange() }
    }
    @Published var windowScreenshotHotkey: Hotkey? {
        didSet { write(windowScreenshotHotkey, for: .windowShot); didChange() }
    }
    @Published var regionScreenshotHotkey: Hotkey? {
        didSet { write(regionScreenshotHotkey, for: .regionShot); didChange() }
    }

    @Published var autoDismissPopover: Bool {
        didSet { UserDefaults.standard.set(autoDismissPopover, forKey: "autoDismissPopover"); didChange() }
    }
    @Published var showNotifications: Bool {
        didSet { UserDefaults.standard.set(showNotifications, forKey: "showNotifications"); didChange() }
    }
    @Published var defaultBlockFilter: String {
        didSet { UserDefaults.standard.set(defaultBlockFilter, forKey: "defaultBlockFilter"); didChange() }
    }
    @Published var preferredTerminalBundleID: String {
        didSet { UserDefaults.standard.set(preferredTerminalBundleID, forKey: "preferredTerminalBundleID"); didChange() }
    }
    @Published var runCommandTerminal: String {
        didSet { UserDefaults.standard.set(runCommandTerminal, forKey: "runCommandTerminal"); didChange() }
    }
    @Published var menuBarIconStyle: String {
        didSet { UserDefaults.standard.set(menuBarIconStyle, forKey: "menuBarIconStyle"); didChange() }
    }
    @Published var compactPopover: Bool {
        didSet { UserDefaults.standard.set(compactPopover, forKey: "compactPopover"); didChange() }
    }
    @Published var defaultBrowserMode: String {
        didSet { UserDefaults.standard.set(defaultBrowserMode, forKey: "defaultBrowserMode"); didChange() }
    }
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); didChange() }
    }
    @Published var copyLatestHotkey: Hotkey? {
        didSet { write(copyLatestHotkey, for: .copyLatest); didChange() }
    }
    @Published var copyLatestKind: String {
        didSet { UserDefaults.standard.set(copyLatestKind, forKey: "copyLatestKind"); didChange() }
    }
    @Published var checkForUpdates: Bool {
        didSet { UserDefaults.standard.set(checkForUpdates, forKey: "checkForUpdates"); didChange() }
    }
    @Published var recentSessionsLimit: Int {
        didSet { UserDefaults.standard.set(recentSessionsLimit, forKey: "recentSessionsLimit"); didChange() }
    }
    @Published var autoPinPatterns: [String] {
        didSet {
            UserDefaults.standard.set(autoPinPatterns, forKey: "autoPinPatterns")
            didChange()
        }
    }

    enum Key: String, CaseIterable {
        case popover     = "popoverHotkey"
        case windowShot  = "windowScreenshotHotkey"
        case regionShot  = "regionScreenshotHotkey"
        case copyLatest  = "copyLatestHotkey"
    }

    static let allBlockFilterSentinel = ""    // empty string == "All"
    static let autoTerminalSentinel    = ""    // empty string == auto-detect

    enum IconStyle: String, CaseIterable {
        case silhouette  // template black crab (default)
        case color       // 🦀 emoji rendered with native color
        case clipboard   // SF Symbol "doc.on.clipboard" (original)
    }

    enum AppearanceStyle: String, CaseIterable {
        case system
        case light
        case dark
    }

    static let defaultPopover    = Hotkey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), keyName: "V")
    static let defaultWindowShot = Hotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), keyName: "S")

    private init() {
        popoverHotkey          = Self.read(.popover)    ?? Self.defaultPopover
        windowScreenshotHotkey = Self.read(.windowShot) ?? Self.defaultWindowShot
        regionScreenshotHotkey = Self.read(.regionShot)

        let d = UserDefaults.standard
        autoDismissPopover        = d.object(forKey: "autoDismissPopover") as? Bool ?? true
        showNotifications         = d.object(forKey: "showNotifications") as? Bool ?? true
        defaultBlockFilter        = d.string(forKey: "defaultBlockFilter") ?? Self.allBlockFilterSentinel
        preferredTerminalBundleID = d.string(forKey: "preferredTerminalBundleID") ?? Self.autoTerminalSentinel
        runCommandTerminal        = d.string(forKey: "runCommandTerminal") ?? "com.apple.Terminal"
        menuBarIconStyle          = d.string(forKey: "menuBarIconStyle") ?? IconStyle.silhouette.rawValue
        compactPopover            = d.object(forKey: "compactPopover") as? Bool ?? false
        defaultBrowserMode        = d.string(forKey: "defaultBrowserMode") ?? "blocks"
        appearance                = d.string(forKey: "appearance") ?? AppearanceStyle.system.rawValue
        copyLatestHotkey          = Self.read(.copyLatest)
        copyLatestKind            = d.string(forKey: "copyLatestKind") ?? "code"
        checkForUpdates           = d.object(forKey: "checkForUpdates") as? Bool ?? true
        recentSessionsLimit       = d.object(forKey: "recentSessionsLimit") as? Int ?? 10
        autoPinPatterns           = d.stringArray(forKey: "autoPinPatterns") ?? []
    }

    func resetToDefaults() {
        popoverHotkey             = Self.defaultPopover
        windowScreenshotHotkey    = Self.defaultWindowShot
        regionScreenshotHotkey    = nil
        autoDismissPopover        = true
        showNotifications         = true
        defaultBlockFilter        = Self.allBlockFilterSentinel
        preferredTerminalBundleID = Self.autoTerminalSentinel
        runCommandTerminal        = "com.apple.Terminal"
        menuBarIconStyle          = IconStyle.silhouette.rawValue
        compactPopover            = false
        defaultBrowserMode        = "blocks"
        appearance                = AppearanceStyle.system.rawValue
        copyLatestHotkey          = nil
        copyLatestKind            = "code"
        checkForUpdates           = true
        recentSessionsLimit       = 10
        autoPinPatterns           = []
    }

    // MARK: - Storage

    private static func read(_ key: Key) -> Hotkey? {
        guard let data = UserDefaults.standard.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    private func write(_ hotkey: Hotkey?, for key: Key) {
        if let hotkey, let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: key.rawValue)
        } else {
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        }
    }

    private func didChange() {
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    // MARK: - Display helpers

    static func displayString(for hotkey: Hotkey?) -> String {
        guard let hotkey else { return "Not set" }
        return modifierString(hotkey.modifiers) + hotkey.keyName
    }

    static func modifierString(_ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey)  != 0 { s += "⌥" }
        if mods & UInt32(shiftKey)   != 0 { s += "⇧" }
        if mods & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("clawpypaste.preferencesChanged")
}
