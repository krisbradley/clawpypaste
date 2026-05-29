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

    enum Key: String, CaseIterable {
        case popover     = "popoverHotkey"
        case windowShot  = "windowScreenshotHotkey"
        case regionShot  = "regionScreenshotHotkey"
    }

    static let defaultPopover    = Hotkey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), keyName: "V")
    static let defaultWindowShot = Hotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), keyName: "S")

    private init() {
        popoverHotkey          = Self.read(.popover)    ?? Self.defaultPopover
        windowScreenshotHotkey = Self.read(.windowShot) ?? Self.defaultWindowShot
        regionScreenshotHotkey = Self.read(.regionShot)
    }

    func resetToDefaults() {
        popoverHotkey          = Self.defaultPopover
        windowScreenshotHotkey = Self.defaultWindowShot
        regionScreenshotHotkey = nil
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
