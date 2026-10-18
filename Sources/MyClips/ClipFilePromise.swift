import AppKit
import MyClipsCore
import UniformTypeIdentifiers

/// A dragged text or image clip that is also a file: Finder (and any app that takes files) gets a .txt or a .png
/// instead of a clipping, or nothing for an image. Every other app still gets the clip's own data, listed first.
/// Not on the main actor: AppKit asks for the file on a background queue.
nonisolated final class ClipFilePromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    private let item: NSPasteboardItem
    private let name: String
    private let contents: Data

    /// Nil for clips Finder already turns into a good file (links, file copies) and for empty data.
    init?(item: NSPasteboardItem, clip: Clip) {
        guard let file = Self.file(of: item, clip: clip) else { return nil }
        self.item = item
        name = file.name
        contents = file.contents
        super.init()
        fileType = file.type.identifier
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        item.types + super.writableTypes(for: pasteboard)
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        item.types.contains(type) ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        item.types.contains(type) ? item.data(forType: type) : super.pasteboardPropertyList(forType: type)
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        name
    }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void
    ) {
        // Two clips of a drag can share a name: the second becomes "name 2".
        do {
            try contents.write(to: Self.free(url), options: .withoutOverwriting)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    // MARK: File

    private struct File {
        let name: String
        let type: UTType
        let contents: Data
    }

    private static func file(of item: NSPasteboardItem, clip: Clip) -> File? {
        switch clip.kind {
        case .text:
            guard let text = item.string(forType: .string), !text.isEmpty else { return nil }
            return File(name: fileName(text) + ".txt", type: .plainText, contents: Data(text.utf8))
        case .image:
            guard let png = item.data(forType: .png) ?? item.data(forType: .tiff).flatMap(Self.png) else { return nil }
            return File(name: "Image \(stamp(clip.createdAt)).png", type: .png, contents: png)
        case .link, .file:
            return nil
        }
    }

    /// Like the macOS screenshot names: "2026-10-18 at 15.40.12".
    static func stamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return day + String(format: " at %02d.%02d.%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// The text's first line, without characters a file name cannot hold, at most 40 characters.
    static func fileName(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = line.replacing(/[\/:\\]/, with: "-").trimmingCharacters(in: .whitespaces)
        let short = String(cleaned.prefix(40)).trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? "Text" : short
    }

    private static func png(_ tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    /// The URL, or "name 2", "name 3" … next to it when a file is already there.
    private static func free(_ url: URL) -> URL {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return url }
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for number in 2... {
            let candidate = folder.appending(path: "\(base) \(number)").appendingPathExtension(ext)
            if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
        }
        return url
    }
}
