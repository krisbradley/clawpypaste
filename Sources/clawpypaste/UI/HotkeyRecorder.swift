import SwiftUI
import AppKit
import Carbon.HIToolbox

// "Type a shortcut…" recorder field. Click to enter record mode, press a
// modifier+key combo to capture, press Escape to clear, click away to bail.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Preferences.Hotkey?

    func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.onCapture = { newValue in
            hotkey = newValue
        }
        field.refresh(hotkey: hotkey)
        return field
    }

    func updateNSView(_ nsView: HotkeyRecorderField, context: Context) {
        nsView.refresh(hotkey: hotkey)
    }
}

final class HotkeyRecorderField: NSView {
    var onCapture: ((Preferences.Hotkey?) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private var isRecording = false { didSet { needsDisplay = true; refreshLabel() } }
    private var currentHotkey: Preferences.Hotkey?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        clearButton.title = "×"
        clearButton.bezelStyle = .accessoryBarAction
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clear)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -2),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.widthAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    func refresh(hotkey: Preferences.Hotkey?) {
        currentHotkey = hotkey
        refreshLabel()
    }

    private func refreshLabel() {
        if isRecording {
            label.stringValue = "Press shortcut…"
            label.textColor = .secondaryLabelColor
            clearButton.isHidden = true
        } else {
            label.stringValue = Preferences.displayString(for: currentHotkey)
            label.textColor = currentHotkey == nil ? .secondaryLabelColor : .labelColor
            clearButton.isHidden = currentHotkey == nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        window.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        // Escape clears the current binding.
        if event.keyCode == UInt16(kVK_Escape) {
            currentHotkey = nil
            onCapture?(nil)
            isRecording = false
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let activeModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let mods = flags.intersection(activeModifiers)
        guard !mods.isEmpty else {
            NSSound.beep()
            return
        }
        let carbonMods = Self.carbonModifiers(mods)
        let keyName = Self.displayName(forKeyCode: UInt32(event.keyCode), event: event)
        let hotkey = Preferences.Hotkey(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonMods,
            keyName: keyName
        )
        currentHotkey = hotkey
        onCapture?(hotkey)
        isRecording = false
    }

    @objc private func clear() {
        currentHotkey = nil
        onCapture?(nil)
        refreshLabel()
    }

    // MARK: - Translation helpers

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    private static func displayName(forKeyCode keyCode: UInt32, event: NSEvent) -> String {
        if let name = namedKey(forKeyCode: keyCode) { return name }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.uppercased()
        }
        return "?"
    }

    private static func namedKey(forKeyCode keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_Return:        return "↩"
        case kVK_Tab:           return "⇥"
        case kVK_Space:         return "Space"
        case kVK_Delete:        return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape:        return "⎋"
        case kVK_LeftArrow:     return "←"
        case kVK_RightArrow:    return "→"
        case kVK_DownArrow:     return "↓"
        case kVK_UpArrow:       return "↑"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }
}
