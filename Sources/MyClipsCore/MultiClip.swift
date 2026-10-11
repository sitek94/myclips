import AppKit
import UniformTypeIdentifiers

/// Combines several clips into one clipboard item: plain text for any app, plus rich text with
/// images embedded in order for apps that accept it. Images used to be dropped from multi-clip pastes.
public enum MultiClip {
    public enum Part: Sendable, Equatable {
        case text(String)
        case image(Data, type: String)
    }

    public struct Composition {
        /// Texts joined by newlines; images are left out.
        public let plainText: String
        /// RTFD with texts and images in order; nil when there are no images (plain text says it all).
        public let rtfd: Data?
    }

    /// The part a clip contributes: its text, else its image, else nothing.
    public static func part(of reps: [Representation], fallbackText: String?) -> Part? {
        if let text = reps.first(where: { $0.type == "public.utf8-plain-text" }).flatMap({ String(data: $0.data, encoding: .utf8) }) {
            return .text(text)
        }
        for type in ["public.png", "public.jpeg", "public.heic", "public.tiff"] {
            if let rep = reps.first(where: { $0.type == type }) { return .image(rep.data, type: type) }
        }
        return fallbackText.map(Part.text)
    }

    public static func compose(_ parts: [Part]) -> Composition {
        let texts = parts.compactMap { if case .text(let text) = $0 { text } else { nil } }
        let plainText = texts.joined(separator: "\n")
        guard parts.contains(where: { if case .image = $0 { true } else { false } }) else {
            return Composition(plainText: plainText, rtfd: nil)
        }
        let rich = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { rich.append(NSAttributedString(string: "\n")) }
            switch part {
            case .text(let text):
                rich.append(NSAttributedString(string: text))
            case .image(let data, let type):
                let ext = UTType(type)?.preferredFilenameExtension ?? "png"
                let wrapper = FileWrapper(regularFileWithContents: data)
                wrapper.preferredFilename = "image\(index).\(ext)"
                rich.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
            }
        }
        let rtfd = rich.rtfd(from: NSRange(location: 0, length: rich.length), documentAttributes: [:])
        return Composition(plainText: plainText, rtfd: rtfd)
    }
}
