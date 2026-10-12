import Foundation
import Testing

@testable import MyClipsCore

@Suite struct CaptureRulesTests {
    @Test func skipsConcealedAndTransientContent() {
        #expect(CaptureRules.shouldSkip(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(CaptureRules.shouldSkip(types: ["de.petermaurer.TransientPasteboardType"]))
        #expect(!CaptureRules.shouldSkip(types: ["public.utf8-plain-text"]))
    }

    @Test func dropsDynamicTypes() {
        #expect(!CaptureRules.isStorable(type: "dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu"))
        #expect(CaptureRules.isStorable(type: "public.html"))
    }

    @Test(
        arguments: [
            (["public.file-url", "public.utf8-plain-text"], "report.pdf", ClipKind.file),
            // Regression: screenshots arrive as a file reference plus PNG data and showed as files.
            (["public.file-url", "public.png"], nil, .image),
            (["public.file-url", "public.tiff", "public.utf8-plain-text"], "photo.png", .file),
            (["public.utf8-plain-text"], "https://example.com/a?b=1", .link),
            (["public.utf8-plain-text"], "see https://example.com", .text),
            (["public.utf8-plain-text"], "mailto:me@example.com", .text),
            (["public.png"], nil, .image),
            (["public.tiff", "public.utf8-plain-text"], "caption", .text),
        ] as [([String], String?, ClipKind)])
    func classifies(types: [String], string: String?, expected: ClipKind) {
        #expect(CaptureRules.kind(types: Set(types), string: string) == expected)
    }

    @Test func readsPNGInsteadOfTIFFAndSkipsLegacyAliases() {
        let screenshot = ["public.png", "public.tiff", "Apple PNG pasteboard type", "NeXT TIFF v4.0 pasteboard type"]
        #expect(CaptureRules.typesToRead(screenshot) == ["public.png"])
        #expect(CaptureRules.typesToRead(["public.tiff"]) == ["public.tiff"])
        #expect(CaptureRules.typesToRead(["NSStringPboardType"]) == ["NSStringPboardType"])
    }

    /// Regression: one oversized type used to drop the whole clip, losing its text too.
    @Test func oversizedRepresentationDoesNotDropTheClip() {
        let huge = Representation(item: 0, type: "com.apple.pdf", data: Data(count: CaptureRules.maxRepresentationBytes + 1))
        let text = Representation(item: 0, type: "public.utf8-plain-text", data: Data("slide title".utf8))
        #expect(CaptureRules.withinBudget([huge, text]) == [text])

        let big = Data(count: CaptureRules.maxRepresentationBytes)
        let reps = (0..<3).map { Representation(item: $0, type: "public.png", data: big) }
        #expect(CaptureRules.withinBudget(reps).count == 2)
    }

    @Test func hashIgnoresRepresentationOrder() {
        let a = Representation(item: 0, type: "public.html", data: Data("<b>x</b>".utf8))
        let b = Representation(item: 0, type: "public.utf8-plain-text", data: Data("x".utf8))
        #expect(CaptureRules.contentHash([a, b]) == CaptureRules.contentHash([b, a]))
        #expect(CaptureRules.contentHash([a]) != CaptureRules.contentHash([b]))
    }
}
