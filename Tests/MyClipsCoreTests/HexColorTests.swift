import Foundation
import Testing

@testable import MyClipsCore

@Suite struct HexColorTests {
    private func clip(_ text: String, kind: ClipKind = .text) -> Clip {
        Clip(
            id: 1, kind: kind, preview: text, sourceBundleID: nil, sourceName: nil, createdAt: .now, usedAt: .now,
            byteSize: text.utf8.count, isPinned: false)
    }

    @Test func readsHexWithOrWithoutHash() {
        #expect(clip("#FF8000").hexRGB?.red == 1)
        #expect(clip(" 00ff00\n").hexRGB?.green == 1)
        #expect(clip("#FFF").hexRGB == nil)
        #expect(clip("#FF8000", kind: .link).hexRGB == nil)
    }

    @Test func lightSwatchesGetDarkText() {
        #expect(clip("#FFE600").hexIsLight)
        #expect(clip("#F3F4F6").hexIsLight)
        #expect(!clip("#4F46E5").hexIsLight)
        #expect(!clip("#F97316").hexIsLight)
        #expect(!clip("plain text").hexIsLight)
    }
}
