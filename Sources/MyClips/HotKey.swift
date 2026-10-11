import Carbon.HIToolbox

/// A system-wide shortcut via Carbon, which still needs no extra permission.
final class HotKey {
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot key events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        let id = EventHotKeyID(signature: OSType(0x434C_5053), id: 1) // "CLPS"
        let registered = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard installed == noErr, registered == noErr else { return nil }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
