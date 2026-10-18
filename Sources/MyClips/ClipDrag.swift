import AppKit
import MyClipsCore
import MyKit
import SwiftUI

/// Dragging cards out of the shelf: the pressed card, or the whole selection when the pressed card is in it.
extension PanelModel {
    /// The drag items for a press at this point (SwiftUI coordinates): one per pasteboard item of each clip, in
    /// shelf order, as the clip was copied.
    func dragItems(at point: CGPoint) -> [DragItem] {
        guard let pressed = clips.first(where: { cardFrames[$0.id]?.contains(point) == true }) else { return [] }
        let ids = targets(for: pressed)
        let clipsByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        let reps = representationsNow(ids)
        return ids.compactMap { clipsByID[$0] }.flatMap { clip in
            let image = snapshot(of: clip)
            return Paster.items(reps[clip.id] ?? []).map { DragItem(writer: $0, image: image) }
        }
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
