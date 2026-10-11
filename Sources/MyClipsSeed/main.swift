// Fills a scratch store with realistic-looking synthetic clips for UI work and screenshots.
// usage: MyClipsSeed <data dir>
import AppKit
import MyClipsCore

guard let dir = CommandLine.arguments.dropFirst().first else {
    print("usage: MyClipsSeed <data dir>")
    exit(2)
}
let url = URL(filePath: dir).appending(path: "clips.sqlite")
guard !url.path.contains("Application Support/dev.maciek.myclips") else {
    print("refusing to seed the real myClips data directory")
    exit(2)
}
for suffix in ["", "-wal", "-shm"] {
    try? FileManager.default.removeItem(atPath: url.path + suffix)
}
let store = try Store(url: url)

func text(_ s: String, _ app: String, _ name: String) -> ClipPayload {
    ClipPayload(
        kind: CaptureRules.kind(types: ["public.utf8-plain-text"], string: s), text: s,
        representations: [Representation(item: 0, type: "public.utf8-plain-text", data: Data(s.utf8))],
        sourceBundleID: app, sourceName: name
    )
}

func png(_ size: NSSize, _ draw: @escaping (NSRect) -> Void) -> Data {
    let img = NSImage(size: size, flipped: false) { rect in draw(rect); return true }
    return NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}

/// A sunset "photo".
let photo = png(NSSize(width: 960, height: 600)) { rect in
    NSGradient(colors: [.systemPurple, .systemPink, .systemOrange])?.draw(in: rect, angle: -90)
    NSColor(white: 1, alpha: 0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: 600, y: 230, width: 150, height: 150)).fill()
    for (color, peaks) in [(NSColor(white: 0.15, alpha: 0.55), [0, 260, 180, 330, 420, 250, 700, 360, 960, 220]),
                           (NSColor(white: 0.08, alpha: 0.85), [0, 150, 240, 210, 520, 120, 760, 190, 960, 110])] {
        let path = NSBezierPath()
        path.move(to: .zero)
        for i in stride(from: 0, to: peaks.count, by: 2) { path.line(to: NSPoint(x: peaks[i], y: peaks[i + 1])) }
        path.line(to: NSPoint(x: 960, y: 0))
        path.close()
        color.setFill()
        path.fill()
    }
}

/// A window-like "screenshot".
let screenshotPNG = png(NSSize(width: 960, height: 600)) { rect in
    NSColor(white: 0.93, alpha: 1).setFill()
    rect.fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 60, dy: 50), xRadius: 18, yRadius: 18).fill()
    for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 90 + i * 28, y: 512, width: 16, height: 16)).fill()
    }
    NSColor(white: 0.85, alpha: 1).setFill()
    for (i, width) in [520, 640, 460, 600, 380].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 100, y: 420 - i * 60, width: width, height: 22), xRadius: 11, yRadius: 11).fill()
    }
    NSColor.systemOrange.setFill()
    NSBezierPath(roundedRect: NSRect(x: 700, y: 120, width: 160, height: 44), xRadius: 12, yRadius: 12).fill()
}

func image(_ data: Data, _ app: String, _ name: String) -> ClipPayload {
    ClipPayload(kind: .image, text: "", representations: [Representation(item: 0, type: "public.png", data: data)],
                sourceBundleID: app, sourceName: name)
}

/// What a screenshot's floating thumbnail puts on the clipboard: a file reference plus the PNG.
let screenshotURL = URL(filePath: dir).appending(path: "Screenshot 2026-10-11 at 12.00.00.png")
try screenshotPNG.write(to: screenshotURL)
func screenshot() -> ClipPayload {
    let reps = [
        Representation(item: 0, type: "public.file-url", data: Data(screenshotURL.absoluteString.utf8)),
        Representation(item: 0, type: "public.png", data: screenshotPNG),
    ]
    return ClipPayload(kind: CaptureRules.kind(types: Set(reps.map(\.type)), string: nil), text: screenshotURL.path,
                       representations: reps, sourceBundleID: "com.apple.finder", sourceName: "Finder")
}

func file(_ path: String) -> ClipPayload {
    ClipPayload(kind: .file, text: path,
                representations: [Representation(item: 0, type: "public.file-url", data: Data(URL(filePath: path).absoluteString.utf8))],
                sourceBundleID: "com.apple.finder", sourceName: "Finder")
}

// Oldest first; the last one shows first in the shelf.
let clips: [ClipPayload] = [
    text("Groceries: oat milk, eggs, coffee beans, basil", "com.apple.Notes", "Notes"),
    text("Café Zürich, Bahnhofstrasse 12, 8001 Zürich", "com.apple.Maps", "Maps"),
    file(screenshotURL.path),
    text("{\n  \"name\": \"myClips\",\n  \"version\": \"0.1.0\"\n}", "com.apple.dt.Xcode", "Xcode"),
    text("hello@example.com", "com.apple.mail", "Mail"),
    text("https://developer.apple.com/documentation/swiftui", "com.apple.Safari", "Safari"),
    text("Meeting moved to Thursday 2 pm — the agenda is in the doc.", "com.apple.mail", "Mail"),
    screenshot(),
    text("git log --oneline --graph -20", "com.apple.Terminal", "Terminal"),
    image(photo, "com.apple.Preview", "Preview"),
    text("#F97316", "com.figma.Desktop", "Figma"),
    text("func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}", "com.apple.dt.Xcode", "Xcode"),
]
for (i, clip) in clips.enumerated() {
    try await store.record(clip, at: Date.now.addingTimeInterval(Double(i - clips.count) * 1500))
}
let snippets = try await store.createPinboard(named: "Snippets")
for id in try await store.clips(matching: "git log").map(\.id) + store.clips(matching: "version").map(\.id) {
    try await store.pin(id, to: snippets)
}
let links = try await store.createPinboard(named: "Links")
for id in try await store.clips(matching: "developer.apple").map(\.id) { try await store.pin(id, to: links) }
try await store.setPinned(store.clips(matching: "hello@").map(\.id), true)
print("seeded \(clips.count) clips into \(url.path)")
