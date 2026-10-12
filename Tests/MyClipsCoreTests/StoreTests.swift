import Foundation
import Testing

@testable import MyClipsCore

private func makeStore() throws -> Store {
    let dir = FileManager.default.temporaryDirectory.appending(path: "clips-tests-\(UUID().uuidString)")
    return try Store(url: dir.appending(path: "clips.sqlite"))
}

private func text(_ string: String, app: String? = nil) -> ClipPayload {
    ClipPayload(
        kind: CaptureRules.kind(types: ["public.utf8-plain-text"], string: string),
        text: string,
        representations: [Representation(item: 0, type: "public.utf8-plain-text", data: Data(string.utf8))],
        sourceBundleID: app
    )
}

@Suite struct StoreTests {
    @Test func recordsNewestFirst() async throws {
        let store = try makeStore()
        try await store.record(text("first"), at: Date(timeIntervalSince1970: 1))
        try await store.record(text("second"), at: Date(timeIntervalSince1970: 2))
        let previews = try await store.clips().map(\.preview)
        #expect(previews == ["second", "first"])
    }

    @Test func duplicateMovesToTopInsteadOfInserting() async throws {
        let store = try makeStore()
        try await store.record(text("same"), at: Date(timeIntervalSince1970: 1))
        try await store.record(text("other"), at: Date(timeIntervalSince1970: 2))
        try await store.record(text("same", app: "com.example.b"), at: Date(timeIntervalSince1970: 3))
        #expect(try await store.count() == 2)
        let clips = try await store.clips()
        #expect(clips.map(\.preview) == ["same", "other"])
        #expect(clips.first?.sourceBundleID == "com.example.b")
    }

    @Test func searchesSubstringsCaseAndAccentInsensitively() async throws {
        let store = try makeStore()
        try await store.record(text("Meeting notes from the Café Strategy review"))
        try await store.record(text("grocery list: milk, eggs"))
        #expect(try await store.clips(matching: "strat").map(\.preview) == ["Meeting notes from the Café Strategy review"])
        #expect(try await store.clips(matching: "cafe").count == 1)
        #expect(try await store.clips(matching: "EGGS").count == 1)
        #expect(try await store.clips(matching: "notes review").count == 1)
        #expect(try await store.clips(matching: "notes milk").isEmpty)
    }

    @Test func shortTokensFallBackToSubstringMatch() async throws {
        let store = try makeStore()
        try await store.record(text("x = 42"))
        try await store.record(text("nothing here"))
        #expect(try await store.clips(matching: "42").map(\.preview) == ["x = 42"])
        #expect(try await store.clips(matching: "%").isEmpty)
    }

    @Test func quotesInQueryDoNotBreakSearch() async throws {
        let store = try makeStore()
        try await store.record(text(#"say "hello" now"#))
        #expect(try await store.clips(matching: #""hello""#).count == 1)
    }

    @Test func pruneKeepsPinnedClips() async throws {
        let store = try makeStore()
        let old = try await store.record(text("pinned old"), at: Date(timeIntervalSince1970: 1))
        try await store.record(text("b"), at: Date(timeIntervalSince1970: 2))
        try await store.record(text("c"), at: Date(timeIntervalSince1970: 3))
        let board = try await store.createPinboard(named: "Keep")
        try await store.pin(old, to: board)
        try await store.prune(keep: 1)
        #expect(Set(try await store.clips().map(\.preview)) == ["pinned old", "c"])
    }

    @Test func clearHistoryKeepsPinnedClips() async throws {
        let store = try makeStore()
        let kept = try await store.record(text("kept"))
        try await store.record(text("gone"))
        try await store.pin(kept, to: try await store.createPinboard(named: "Board"))
        try await store.clearHistory()
        #expect(try await store.clips().map(\.preview) == ["kept"])
        #expect(try await store.clips(matching: "gone").isEmpty)
    }

    @Test func pinboardListsOnlyItsClips() async throws {
        let store = try makeStore()
        let alpha = try await store.record(text("alpha"))
        try await store.record(text("beta"))
        let board = try await store.createPinboard(named: "Snippets")
        try await store.pin(alpha, to: board)
        try await store.pin(alpha, to: board)
        #expect(try await store.clips(in: board).map(\.preview) == ["alpha"])
        #expect(try await store.pinboards().map(\.itemCount) == [1])
        try await store.unpin(alpha, from: board)
        #expect(try await store.clips(in: board).isEmpty)
    }

    @Test func deletingPinboardKeepsItsClipsInHistory() async throws {
        let store = try makeStore()
        let alpha = try await store.record(text("alpha"))
        let board = try await store.createPinboard(named: "Temp")
        try await store.pin(alpha, to: board)
        try await store.deletePinboard(board)
        #expect(try await store.pinboards().isEmpty)
        #expect(try await store.clips().count == 1)
    }

    @Test func reuseMovesToTopKeepingPinsRepsAndSearch() async throws {
        let store = try makeStore()
        let old = try await store.record(text("reused snippet"))
        try await store.record(text("newer"))
        let board = try await store.createPinboard(named: "Board")
        try await store.pin(old, to: board)

        let moved = try await store.markUsed(old)
        #expect(try await store.clips().map(\.preview) == ["reused snippet", "newer"])
        #expect(try await store.clips(in: board).map(\.id) == [moved])
        #expect(try await store.representations(of: moved).count == 1)
        #expect(try await store.clips(matching: "snippet").map(\.id) == [moved])
        #expect(try await store.clips(matching: "newer").count == 1)
    }

    @Test func searchReturnsNewestMatchesWhenOverLimit() async throws {
        let store = try makeStore()
        for i in 0..<10 { try await store.record(text("match \(i)")) }
        let first = try await store.clips(matching: "match").last!.id
        try await store.markUsed(first)
        #expect(try await store.clips(matching: "match", limit: 3).map(\.preview) == ["match 0", "match 9", "match 8"])
    }

    @Test func pinnedClipsLeadHistoryAndSearch() async throws {
        let store = try makeStore()
        let old = try await store.record(text("old pinned note"))
        try await store.record(text("newer note"))
        try await store.record(text("newest"))
        try await store.setPinned([old], true)
        #expect(try await store.clips().map(\.preview) == ["old pinned note", "newest", "newer note"])
        #expect(try await store.clips().first?.isPinned == true)
        #expect(try await store.clips(matching: "note").map(\.preview) == ["old pinned note", "newer note"])
        #expect(try await store.clips(matching: "newest").map(\.preview) == ["newest"])
        #expect(try await store.clips(limit: 2).map(\.preview) == ["old pinned note", "newest"])

        try await store.setPinned([old], false)
        #expect(try await store.clips().map(\.preview) == ["newest", "newer note", "old pinned note"])
    }

    @Test func pinnedClipsSurvivePruneClearAndReuse() async throws {
        let store = try makeStore()
        let pinned = try await store.record(text("keep me"), at: Date(timeIntervalSince1970: 1))
        try await store.record(text("b"), at: Date(timeIntervalSince1970: 2))
        try await store.setPinned([pinned], true)
        try await store.prune(keep: 0)
        #expect(try await store.clips().map(\.preview) == ["keep me"])
        try await store.record(text("c"))
        try await store.clearHistory()
        let moved = try await store.markUsed(pinned)
        #expect(try await store.clips().map(\.id) == [moved])
        #expect(try await store.clips().first?.isPinned == true)
    }

    @Test func upgradeReclassifiesScreenshotFilesAsImages() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "clips-v2-\(UUID().uuidString).sqlite")
        do {
            let db = try Database(path: url.path)
            try Store.createV1(db)
            try db.execute(
                """
                INSERT INTO items (id, hash, kind, text, created_at, used_at, byte_size) VALUES
                    (1, 'a', 'file', '/tmp/Screenshot.png', 1, 1, 9), (2, 'b', 'file', '/tmp/doc.pdf', 2, 2, 9);
                INSERT INTO reps VALUES (1, 0, 'public.file-url', x'00'), (1, 0, 'public.png', x'89'),
                    (2, 0, 'public.file-url', x'00'), (2, 0, 'public.tiff', x'4d');
                """)
        }
        let kinds = try await Store(url: url).clips().map { "\($0.preview) \($0.kind)" }
        #expect(kinds == ["/tmp/doc.pdf file", "/tmp/Screenshot.png image"])
    }

    @Test func filtersByKind() async throws {
        let store = try makeStore()
        try await store.record(text("https://example.com/a"))
        try await store.record(text("plain words about example"))
        #expect(try await store.clips(kind: .link).map(\.preview) == ["https://example.com/a"])
        #expect(try await store.clips(matching: "example", kind: .text).map(\.preview) == ["plain words about example"])
        #expect(try await store.clips(kind: .image).isEmpty)
    }

    @Test func batchDeleteRemovesAll() async throws {
        let store = try makeStore()
        let first = try await store.record(text("a1"))
        let second = try await store.record(text("b1"))
        try await store.record(text("c1"))
        try await store.delete([first, second])
        #expect(try await store.clips().map(\.preview) == ["c1"])
    }

    @Test func upgradesVersion1Database() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "clips-v1-\(UUID().uuidString).sqlite")
        do {
            let db = try Database(path: url.path)
            try Store.createV1(db)
            try db.run(
                "INSERT INTO items (hash, kind, text, created_at, used_at, byte_size) VALUES ('h', 'text', 'from v1', 1, 1, 7)"
            )
        }
        let store = try Store(url: url)
        let clip = try #require(try await store.clips().first)
        #expect(clip.preview == "from v1" && !clip.isPinned)
        #expect(clip.kind == .text)
        try await store.setPinned([clip.id], true)
        #expect(try await store.clips().first?.isPinned == true)
    }

    @Test func representationsRoundTrip() async throws {
        let store = try makeStore()
        let reps = [
            Representation(item: 0, type: "public.utf8-plain-text", data: Data("hi".utf8)),
            Representation(item: 0, type: "public.html", data: Data("<b>hi</b>".utf8)),
            Representation(item: 1, type: "public.png", data: Data([0x89, 0x50])),
        ]
        let id = try await store.record(ClipPayload(kind: .text, text: "hi", representations: reps))
        #expect(Set(try await store.representations(of: id)) == Set(reps))
        try await store.delete([id])
        #expect(try await store.representations(of: id).isEmpty)
    }
}
