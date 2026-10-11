// UI test driver for myClips. Runs as its own signed app so Screen Recording and Accessibility
// are granted to it alone, not to the terminal. One long-lived process (`serve <dir>`) executes
// request files, so commands don't launch new processes that disturb keyboard focus.
// Fixed verbs only; see scripts/drive.sh.
//
//   setup                         request both permissions
//   status                        print permission state
//   windows <owner>               list the owner's windows
//   screenshot <png> [owner]      capture only the owner's on-screen windows (default myClips)
//   key <combo>                   to the myClips process only, e.g. esc, right, shift+return
//   type <text>                   to the myClips process only
//   globalkey <combo>             system-wide; only while the user is hands-off
//   globalclick <x> <y> [right] [cmd] [shift]   system-wide click; only while the user is hands-off
//   toggle                        open/close the shelf of a myClips launched with -uiTest YES
//   click <x> <y>                 to the myClips process only; global top-left coordinates
//   front                         frontmost app
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ScreenCaptureKit

let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
    "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
    "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
    "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "0": kVK_ANSI_0,
    "esc": kVK_Escape, "return": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "delete": kVK_Delete,
    "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash,
    "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
]

/// Target for key/type: myClips only, so test keystrokes can never reach the user's apps.
func clipsPID() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "dev.maciek.myclips").first?.processIdentifier
}

func deliver(_ event: CGEvent?, to pid: pid_t?) {
    if let pid { event?.postToPid(pid) } else { event?.post(tap: .cghidEventTap) }
}

func postKey(_ combo: String, to pid: pid_t?) -> Bool {
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    guard let keyName = parts.last, let code = keyCodes[keyName] else { return false }
    var flags: CGEventFlags = []
    for modifier in parts.dropLast() {
        switch modifier {
        case "cmd": flags.insert(.maskCommand)
        case "ctrl": flags.insert(.maskControl)
        case "opt", "alt": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        default: return false
        }
    }
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
        event?.flags = flags
        deliver(event, to: pid)
        usleep(15_000)
    }
    return true
}

func typeText(_ text: String, to pid: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    for unit in text.utf16 {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            var char = unit
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            event?.flags = [] // don't inherit modifiers from an earlier combo
            deliver(event, to: pid)
            usleep(8_000)
        }
    }
}

func windowList(owner: String) -> String {
    let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return all.filter { $0[kCGWindowOwnerName as String] as? String == owner }.map { w in
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        return "id=\(w[kCGWindowNumber as String] ?? "?") layer=\(w[kCGWindowLayer as String] ?? "?") "
            + "onscreen=\(w[kCGWindowIsOnscreen as String] ?? false) "
            + "frame=\(b["X"] ?? 0),\(b["Y"] ?? 0),\(b["Width"] ?? 0),\(b["Height"] ?? 0)"
    }.joined(separator: "\n")
}

func screenshot(path: String, owner: String) async -> (String, Int32) {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let mine = content.windows.filter { $0.owningApplication?.applicationName == owner && $0.isOnScreen && $0.frame.height > 30 }
        guard let first = mine.first,
              let display = content.displays.first(where: { $0.frame.intersects(first.frame) }) ?? content.displays.first
        else { return ("no on-screen windows for \(owner)", 1) }
        let filter = SCContentFilter(display: display, including: mine)
        let union = mine.map(\.frame).reduce(first.frame) { $0.union($1) }
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.sourceRect = union.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = Int(union.width * scale)
        config.height = Int(union.height * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        return ("saved \(path) \(image.width)x\(image.height) from \(mine.count) window(s)", 0)
    } catch {
        return ("screenshot failed: \(error.localizedDescription)", 1)
    }
}

var busy = false

@MainActor func run(_ verb: String, _ args: [String]) async -> (String, Int32) {
    switch verb {
    case "setup":
        _ = CGRequestScreenCaptureAccess()
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        fallthrough
    case "status":
        return ("screen recording: \(CGPreflightScreenCaptureAccess()) accessibility: \(AXIsProcessTrusted())", 0)
    case "windows":
        return (windowList(owner: args.first ?? "myClips"), 0)
    case "screenshot":
        guard let path = args.first else { return ("missing path", 2) }
        return await screenshot(path: path, owner: args.count > 1 ? args[1] : "myClips")
    case "key":
        guard let pid = clipsPID() else { return ("myClips is not running", 1) }
        guard let combo = args.first, postKey(combo, to: pid) else { return ("unknown key combo", 2) }
        return ("ok", 0)
    case "globalkey":
        guard let combo = args.first, postKey(combo, to: nil) else { return ("unknown key combo", 2) }
        return ("ok", 0)
    case "type":
        guard let pid = clipsPID() else { return ("myClips is not running", 1) }
        typeText(args.joined(separator: " "), to: pid)
        return ("ok", 0)
    case "globalclick":
        guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]) else { return ("usage: globalclick x y [right] [cmd] [shift]", 2) }
        let options = Set(args.dropFirst(2))
        let right = options.contains("right")
        var flags: CGEventFlags = []
        if options.contains("cmd") { flags.insert(.maskCommand) }
        if options.contains("shift") { flags.insert(.maskShift) }
        let types: [CGEventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y),
                                mouseButton: right ? .right : .left)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            usleep(40_000)
        }
        return ("ok", 0)
    case "toggle":
        DistributedNotificationCenter.default().postNotificationName(.init("dev.maciek.myclips.toggle"), object: nil, deliverImmediately: true)
        return ("ok", 0)
    case "click":
        guard let pid = clipsPID() else { return ("myClips is not running", 1) }
        guard args.count == 2, let x = Double(args[0]), let y = Double(args[1]) else { return ("usage: click x y", 2) }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            deliver(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left), to: pid)
            usleep(30_000)
        }
        return ("ok", 0)
    case "front":
        let app = NSWorkspace.shared.frontmostApplication
        return ("\(app?.bundleIdentifier ?? "nil") pid=\(app?.processIdentifier ?? 0)", 0)
    default:
        return ("unknown verb \(verb)", 2)
    }
}

/// Request: <dir>/req/<id>.json = ["verb", "arg", ...]; response: <dir>/res/<id>.txt, first line is the exit code.
@MainActor func serve(_ dir: URL) {
    let req = dir.appending(path: "req"), res = dir.appending(path: "res")
    try? FileManager.default.createDirectory(at: req, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated {
            guard !busy, let name = (try? FileManager.default.contentsOfDirectory(atPath: req.path))?
                .filter({ $0.hasSuffix(".json") }).sorted().first else { return }
            let file = req.appending(path: name)
            let command = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: file))) ?? []
            try? FileManager.default.removeItem(at: file)
            busy = true
            Task { @MainActor in
                let (output, code) = await run(command.first ?? "", Array(command.dropFirst()))
                let out = res.appending(path: name.replacingOccurrences(of: ".json", with: ".txt"))
                try? "\(code)\n\(output)".write(to: out, atomically: true, encoding: .utf8)
                busy = false
            }
        }
    }
}

/// `sinkapp <result> <seconds>`: a separate, normally launched (so frontmost) process with a text
/// window to paste into; writes the window's text to <result> when time is up.
@MainActor func sinkApp(result: URL, seconds: Double) {
    let window = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 420, height: 160),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "myClipsDriver sink"
    // Above other apps' windows, so a click on it reaches it and activates it.
    window.level = .floating
    let text = NSTextView(frame: window.contentLayoutRect)
    text.isRichText = false
    window.contentView = text
    window.orderFrontRegardless()
    window.makeKey()
    window.makeFirstResponder(text)
    NSApp.activate()
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        try? text.string.write(to: result, atomically: true, encoding: .utf8)
        exit(0)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let app = NSApplication.shared
switch (args.first, args.count) {
case ("serve", 2):
    app.setActivationPolicy(.accessory)
    serve(URL(filePath: args[1]))
case ("sinkapp", 3):
    app.setActivationPolicy(.regular)
    // ⌘V reaches NSTextView's paste: only through a menu key equivalent.
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    let mainMenu = NSMenu()
    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editItem.submenu = edit
    mainMenu.addItem(editItem)
    app.mainMenu = mainMenu
    sinkApp(result: URL(filePath: args[1]), seconds: Double(args[2]) ?? 30)
default:
    FileHandle.standardError.write(Data("usage: myClipsDriver serve <dir> | sinkapp <result> <seconds>\n".utf8))
    exit(2)
}
app.run()
