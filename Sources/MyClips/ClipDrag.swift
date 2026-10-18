import AppKit
import MyClipsCore
import MyKit
import SwiftUI

/// Dragging cards out of the shelf: the pressed card, or the whole selection when the pressed card is in it.
extension PanelModel {
    /// After a press: the drag that press would start, made now, so the drag itself starts at once.
    func prepareDrag(at point: CGPoint, onScreen: (CGRect) -> NSImage?) {
        preparedDrag = drag(at: point, onScreen: onScreen)
    }

    /// The drag items for a press at this point (SwiftUI coordinates): the prepared ones, else made now.
    func dragItems(at point: CGPoint, onScreen: (CGRect) -> NSImage?) -> [DragItem] {
        defer { preparedDrag = nil }
        if let preparedDrag, let pressed = clip(at: point), preparedDrag.ids == targets(for: pressed) { return preparedDrag.items }
        return drag(at: point, onScreen: onScreen)?.items ?? []
    }

    private func clip(at point: CGPoint) -> Clip? {
        clips.first { cardFrames[$0.id]?.contains(point) == true }
    }

    /// One item per pasteboard item of each clip, in shelf order, as the clip was copied; text and images are files
    /// too. `onScreen` gives a card's picture from the screen; cards out of view are drawn.
    private func drag(at point: CGPoint, onScreen: (CGRect) -> NSImage?) -> PreparedDrag? {
        guard let pressed = clip(at: point) else { return nil }
        let ids = targets(for: pressed)
        let clipsByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        let reps = representationsNow(ids)
        let items = ids.compactMap { clipsByID[$0] }.flatMap { clip in
            let image = cardFrames[clip.id].flatMap(onScreen) ?? snapshot(of: clip)
            return Paster.items(reps[clip.id] ?? []).map { item in
                DragItem(writer: ClipFilePromise(item: item, clip: clip) ?? item, image: image)
            }
        }
        return PreparedDrag(ids: ids, items: items)
    }

    /// The store is an actor; a drag needs its data at once. Reads take milliseconds; after a second the clips that
    /// are not read yet are left out.
    private func representationsNow(_ ids: [Int64]) -> [Int64: [Representation]] {
        let result = DragReads()
        let done = DispatchSemaphore(value: 0)
        Task.detached { [store] in
            for id in ids { result.set(id, (try? await store.representations(of: id)) ?? []) }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
        return result.value
    }

    /// The card as it looks in the shelf, without the selection ring and a little see-through.
    private func snapshot(of clip: Clip) -> NSImage {
        let card = ClipCard(
            clip: clip, shortcut: nil, selected: false, model: self,
            thumbnail: thumbnails.object(forKey: NSNumber(value: clip.id))
        )
        .opacity(0.8)
        let renderer = ImageRenderer(content: card)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage()
    }
}

/// Representations read off the main actor, for `representationsNow`.
nonisolated private final class DragReads: @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [Int64: [Representation]] = [:]

    func set(_ id: Int64, _ reps: [Representation]) {
        lock.withLock { reads[id] = reps }
    }

    var value: [Int64: [Representation]] { lock.withLock { reads } }
}

/// The drag a press would start: which clips, and their items.
struct PreparedDrag {
    let ids: [Int64]
    let items: [DragItem]
}
