import Carbon.HIToolbox
import AppKit

// Registers a single Carbon EventHotKey. The Carbon APIs are deprecated in
// name only — they're still the supported path for system-wide hotkeys on
// macOS, including for sandboxed and SwiftUI apps.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onTrigger: () -> Void

    init(keyCode: UInt32, modifiers: Int, onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        register(keyCode: keyCode, modifiers: UInt32(modifiers))
    }

    deinit {
        if let ref = ref { UnregisterEventHotKey(ref) }
        if let handlerRef = handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let userData = userData, let eventRef = eventRef else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status == noErr {
                    let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                    me.onTrigger()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4157), id: 1)  // 'CLAW'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
    }
}
