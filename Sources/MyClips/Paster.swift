import AppKit
import Carbon.HIToolbox
import MyClipsCore

/// Puts a clip back on the pasteboard and sends Cmd+V to the frontmost app.
enum Paster {
    static func write(_ reps: [Representation], plainText: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let plainText {
            pasteboard.setString(plainText, forType: .string)
            return
        }
        let items = Dictionary(grouping: reps, by: \.item).sorted { $0.key < $1.key }.map { _, reps in
            let item = NSPasteboardItem()
            for rep in reps {
                item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    /// One item with plain text, and rich text when given.
    static func write(plainText: String, rtfd: Data?) {
        let item = NSPasteboardItem()
        item.setString(plainText, forType: .string)
        if let rtfd { item.setData(rtfd, forType: .rtfd) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    /// Requires Accessibility permission; without it the event is silently dropped.
    static func sendPasteKeystroke() {
        let key = keyCode(for: "v") ?? CGKeyCode(kVK_ANSI_V)
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            // Explicit flags so modifiers still held from the panel (e.g. Shift) don't leak into the paste.
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
    }

    /// The key that types `character` in the current layout, so Cmd+V works on Dvorak, AZERTY, etc.
    private static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        let target = Array(String(character).utf16)
        return layoutData.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
                )
                if status == noErr, Array(chars.prefix(length)) == target { return CGKeyCode(code) }
            }
            return nil
        }
    }
}
