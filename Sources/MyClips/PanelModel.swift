import AppKit
import ImageIO
import MyClipsCore
import Observation
import QuickLookThumbnailing

@Observable
final class PanelModel {
    var query = "" {
        didSet { if query != oldValue { reload(selectFirst: true) } }
    }
    /// nil shows history; otherwise a pinboard id.
    var board: Int64? {
        didSet { if board != oldValue { reload(selectFirst: true) } }
    }
    /// Type filter; nil shows all. Reset every time the shelf opens.
    var kind: ClipKind? {
        didSet { if kind != oldValue { reload(selectFirst: true) } }
    }
    /// The card the keyboard is on; always part of `selected` when anything is selected.
    private(set) var cursor: Int64?
    private(set) var selected: Set<Int64> = []
    @ObservationIgnored private var anchor: Int64?
    private(set) var clips: [Clip] = []
    private(set) var pinboards: [Pinboard] = []
    /// Incremented each time the panel opens, so the view can refocus the search field.
    private(set) var openCount = 0
    /// Non-nil while the user types a new pinboard's name; keys go to that field.
    var newBoardName: String?
    /// Large preview of the cursor clip.
    var previewing = false
    /// Short confirmation shown in the shelf, e.g. after ⌘C.
    private(set) var flash: String?
    @ObservationIgnored var pendingPin: [Int64] = []

    @ObservationIgnored var onPaste: ([Clip], _ plainText: Bool) -> Void = { _, _ in }
    @ObservationIgnored var onCopy: ([Clip]) -> Void = { _ in }
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored let thumbnails = NSCache<NSNumber, NSImage>()
    @ObservationIgnored let store: Store
    /// Where each visible card is, in the shelf's SwiftUI coordinates: a drag starts on the card under the press.
    @ObservationIgnored var cardFrames: [Int64: CGRect] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var headerColors: [String: RGB] = [:]

    init(store: Store) {
        self.store = store
    }

    func prepareForOpen() {
        newBoardName = nil
        previewing = false
        query = ""
        board = nil
        kind = nil
        openCount += 1
        reload(selectFirst: true)
    }

    /// `selectFirst` after a new query or pinboard; otherwise keep what is still listed.
    func reload(selectFirst: Bool = false) {
        loadTask?.cancel()
        let query = query, board = board, kind = kind
        loadTask = Task {
            let clips = (try? await store.clips(matching: query, in: board, kind: kind)) ?? []
            let pinboards = (try? await store.pinboards()) ?? []
            guard !Task.isCancelled else { return }
            self.clips = clips
            self.pinboards = pinboards
            let listed = Set(clips.map(\.id))
            if selectFirst || cursor.map({ !listed.contains($0) }) ?? true {
                select(clips.first?.id)
            } else {
                selected.formIntersection(listed)
            }
        }
    }

    var cursorClip: Clip? { clips.first { $0.id == cursor } }

    /// Selected clips in list order.
    var selectedClips: [Clip] { clips.filter { selected.contains($0.id) } }

    // MARK: Selection

    enum Extend { case none, toggle, range }

    func select(_ id: Int64?, extend: Extend = .none) {
        guard let id else {
            cursor = nil; anchor = nil; selected = []
            return
        }
        switch extend {
        case .none:
            selected = [id]
            anchor = id
        case .toggle:
            if selected.contains(id), selected.count > 1 {
                selected.remove(id)
                if cursor == id { cursor = selectedClips.first?.id }
                return
            }
            selected.insert(id)
            anchor = id
        case .range:
            guard let from = clips.firstIndex(where: { $0.id == (anchor ?? cursor) }),
                let to = clips.firstIndex(where: { $0.id == id })
            else { return select(id) }
            selected = Set(clips[min(from, to)...max(from, to)].map(\.id))
        }
        cursor = id
    }

    func moveCursor(by offset: Int, extending: Bool) {
        guard !clips.isEmpty else { return }
        let current = clips.firstIndex { $0.id == cursor } ?? 0
        select(clips[max(0, min(clips.count - 1, current + offset))].id, extend: extending ? .range : .none)
    }

    func selectAll() {
        selected = Set(clips.map(\.id))
        anchor = clips.first?.id
        if cursor == nil { cursor = clips.first?.id }
    }

    /// What a context-menu action on `clip` applies to: the whole selection if the clip is in it.
    func targets(for clip: Clip) -> [Int64] {
        selected.contains(clip.id) ? selectedClips.map(\.id) : [clip.id]
    }

    // MARK: Actions

    func cycleBoard(by offset: Int) {
        let boards: [Int64?] = [nil] + pinboards.map(\.id)
        let current = boards.firstIndex(of: board) ?? 0
        board = boards[(current + offset + boards.count) % boards.count]
    }

    func pasteSelection(plainText: Bool) {
        let clips = selectedClips
        if !clips.isEmpty { onPaste(clips, plainText) }
    }

    /// ⌘C: puts the selection on the clipboard and keeps the shelf open.
    func copySelection() {
        let clips = selectedClips
        guard !clips.isEmpty else { return }
        onCopy(clips)
        show(clips.count == 1 ? "Copied" : "Copied \(clips.count) clips")
    }

    func show(_ message: String) {
        flash = message
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { flash = nil }
        }
    }

    func paste(at index: Int) {
        if clips.indices.contains(index) { onPaste([clips[index]], false) }
    }

    func delete(_ ids: [Int64]) {
        let gone = Set(ids)
        // Keep the cursor where the first deleted card was.
        let index = clips.firstIndex { gone.contains($0.id) } ?? 0
        let remaining = clips.filter { !gone.contains($0.id) }
        select(remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id)
        perform { try await $0.delete(ids) }
    }

    func deleteSelection() {
        delete(selectedClips.map(\.id))
    }

    /// Pins the selection to the top of history, or unpins it when every selected clip is already pinned.
    func togglePinnedSelection() {
        let clips = selectedClips
        guard !clips.isEmpty else { return }
        setPinned(clips.map(\.id), !clips.allSatisfy(\.isPinned))
    }

    func setPinned(_ ids: [Int64], _ pinned: Bool) {
        perform { try await $0.setPinned(ids, pinned) }
    }

    // MARK: Pinboards

    func add(_ ids: [Int64], to board: Int64) {
        perform { store in
            for id in ids { try await store.pin(id, to: board) }
        }
    }

    func remove(_ ids: [Int64]) {
        guard let board else { return }
        perform { store in
            for id in ids { try await store.unpin(id, from: board) }
        }
    }

    func startNewBoard(adding ids: [Int64] = []) {
        pendingPin = ids
        newBoardName = ""
    }

    func commitNewBoard() {
        let name = newBoardName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ids = pendingPin
        newBoardName = nil
        pendingPin = []
        guard !name.isEmpty else { return }
        perform { store in
            let board = try await store.createPinboard(named: name)
            for id in ids { try await store.pin(id, to: board) }
        }
    }

    func deleteBoard(_ id: Int64) {
        if board == id { board = nil }
        perform { try await $0.deletePinboard(id) }
    }

    // MARK: Display

    func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icons[bundleID] = icon
        return icon
    }

    /// Card-sized image: decoded small from the stored data, or a Quick Look thumbnail for files. Cached.
    func thumbnail(for clip: Clip) async -> NSImage? {
        let key = NSNumber(value: clip.id)
        if let cached = thumbnails.object(forKey: key) { return cached }
        var image: NSImage?
        switch clip.kind {
        case .image:
            if let data = await imageData(for: clip) {
                image = await Task.detached { Self.downsample(data, maxPixels: 480) }.value
            }
        case .file:
            guard let path = clip.preview.split(separator: "\n").first.map(String.init),
                FileManager.default.fileExists(atPath: path)
            else { return nil }
            let request = QLThumbnailGenerator.Request(
                fileAt: URL(filePath: path), size: CGSize(width: 208, height: 140), scale: 2, representationTypes: .thumbnail
            )
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        case .text, .link:
            return nil
        }
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    private nonisolated static func downsample(_ data: Data, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private func imageData(for clip: Clip) async -> Data? {
        guard let reps = try? await store.representations(of: clip.id) else { return nil }
        return ["public.png", "public.jpeg", "public.heic", "public.tiff"].lazy
            .compactMap { type in reps.first { $0.type == type }?.data }
            .first
    }

    /// Full-size image, for the preview.
    func image(for clip: Clip) async -> NSImage? {
        guard clip.kind == .image else { return nil }
        return await imageData(for: clip).flatMap(NSImage.init(data:))
    }

    /// Full text for the preview; the list only carries the first 1,000 characters.
    func fullText(for clip: Clip) async -> String {
        guard let reps = try? await store.representations(of: clip.id),
            let rep = reps.first(where: { $0.type == NSPasteboard.PasteboardType.string.rawValue }),
            let text = String(data: rep.data, encoding: .utf8)
        else { return clip.preview }
        return text
    }

    private func perform(_ change: @escaping (Store) async throws -> Void) {
        Task {
            try? await change(store)
            reload()
        }
    }
}

extension PanelModel {
    /// A card header's color for the source app: from its icon, else gray. Cached per app.
    func headerColor(for bundleID: String?) -> RGB {
        guard let bundleID else { return IconColor.gray }
        if let cached = headerColors[bundleID] { return cached }
        let color = icon(for: bundleID).flatMap(Self.iconPixels).flatMap(IconColor.pick) ?? IconColor.gray
        headerColors[bundleID] = color
        return color
    }

    /// The icon drawn at 128 × 128, as RGBA bytes. Premultiplied (AppKit draws into no other kind), which is the same
    /// for the opaque pixels `IconColor` reads.
    private static func iconPixels(_ icon: NSImage) -> [UInt8]? {
        let side = 128
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4,
                bitsPerPixel: 32),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.bitmapData else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: side * side * 4))
    }
}
