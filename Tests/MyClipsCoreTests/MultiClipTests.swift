import AppKit
import Testing
@testable import MyClipsCore

@Suite struct MultiClipTests {
    private let png: Data = {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }()

    /// Regression: an image in a multi-clip paste was silently dropped.
    @Test func keepsImagesInOrderAsRichText() throws {
        let result = MultiClip.compose([.image(png, type: "public.png"), .text("first"), .text("second")])
        #expect(result.plainText == "first\nsecond")
        let rtfd = try #require(result.rtfd)
        let rich = try #require(NSAttributedString(rtfd: rtfd, documentAttributes: nil))
        var attachments = 0
        rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        #expect(attachments == 1)
        #expect(rich.string.hasSuffix("first\nsecond"))
    }

    @Test func textOnlyNeedsNoRichText() {
        let result = MultiClip.compose([.text("a"), .text("b")])
        #expect(result.plainText == "a\nb")
        #expect(result.rtfd == nil)
    }

    @Test func partPrefersTextThenImageThenFallback() {
        let text = Representation(item: 0, type: "public.utf8-plain-text", data: Data("hi".utf8))
        let image = Representation(item: 0, type: "public.png", data: png)
        #expect(MultiClip.part(of: [image, text], fallbackText: nil) == .text("hi"))
        #expect(MultiClip.part(of: [image], fallbackText: "/tmp/x.png") == .image(png, type: "public.png"))
        #expect(MultiClip.part(of: [], fallbackText: "/tmp/doc.pdf") == .text("/tmp/doc.pdf"))
    }
}
