import MyClipsCore
import MyKit
import SwiftUI

/// One clip, as a square card. A header in the source app's color says what the clip is (Text, Link, Image, File,
/// Color) and how old it is, with the app's icon large in its corner; the content fills the rest. At the bottom, the
/// size, and ⌘1–⌘9 on the first nine cards. The accent ring marks the selection.
struct ClipCard: View {
    static let size = CGSize(width: 232, height: 232)
    static let spacing: CGFloat = .space6
    static let radius: CGFloat = 16
    static let headerHeight: CGFloat = 48
    /// The icon image, with its transparent margin: the visible shape is about 80 % of it.
    static let iconSize: CGFloat = 78
    /// How far the icon image reaches past the header's top and trailing edges; the header cuts the shape too.
    static let iconOverhang: CGFloat = 15
    static let footerHeight: CGFloat = 34

    let clip: Clip
    let shortcut: Int?
    let selected: Bool
    let model: PanelModel
    @State private var thumbnail: NSImage?

    /// `thumbnail`: an image card's picture when it is already loaded (a drag's snapshot does not wait for it).
    init(clip: Clip, shortcut: Int?, selected: Bool, model: PanelModel, thumbnail: NSImage? = nil) {
        self.clip = clip
        self.shortcut = shortcut
        self.selected = selected
        self.model = model
        _thumbnail = State(initialValue: thumbnail)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { footer }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(.rect(cornerRadius: Self.radius))
        .selectionRing(selected, cornerRadius: Self.radius)
        .contentShape(.rect)
        .help("\(kindTitle), \(detailText)")
        .task(id: clip.id) {
            thumbnail = await model.thumbnail(for: clip)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: .space1) {
                if clip.isPinned { Image(systemName: "pin.fill").font(.textCaption).accessibilityLabel("Pinned") }
                Text(kindTitle).font(.textTitle.weight(.semibold))
            }
            Text(age).font(.textBody).opacity(0.8)
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.leading, .space3)
        .padding(.trailing, Self.iconSize - Self.iconOverhang)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frame(height: Self.headerHeight)
        .background {
            let rgb = model.headerColor(for: clip.sourceBundleID)
            // The source app's own color, not a UI color.
            // swiftlint:disable:next raw_color
            Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
        .overlay(alignment: .topTrailing) {
            if let icon = model.icon(for: clip.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .offset(x: Self.iconOverhang, y: -Self.iconOverhang)
            }
        }
        .clipped()
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch clip.kind {
        case .image:
            if let thumbnail {
                // In an overlay, so a wide image fills the card without widening it.
                Color.clear.overlay { Image(nsImage: thumbnail).resizable().scaledToFill() }.clipped()
            } else {
                placeholder("photo")
            }
        case .file:
            VStack(spacing: .space2) {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    placeholder("doc.fill")
                }
                Text(fileNames).font(.textCaption.weight(.medium)).lineLimit(1)
            }
            .padding(.space3)
            .padding(.bottom, Self.footerHeight)
        case .link:
            placeholder("link").padding(.bottom, Self.footerHeight)
        case .text:
            if let color = hexColor {
                color.overlay {
                    Text(clip.preview.uppercased())
                        .font(.textBody.monospaced().weight(.semibold))
                        .foregroundStyle(clip.hexIsLight ? .black : .white)
                }
            } else {
                Text(clip.preview.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.textBody)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding([.horizontal, .top], .space3)
                    // Long text fades out above the footer.
                    .mask {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 0.88)],
                            startPoint: .top, endPoint: .bottom)
                    }
            }
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        // swiftlint:disable:next system_font
        Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary)  // a symbol used as a picture
    }

    // MARK: Footer

    /// The size in the middle (a link's host and address on the left), the shortcut badge on the right.
    private var footer: some View {
        ZStack {
            if clip.kind == .link {
                VStack(alignment: .leading, spacing: 0) {
                    Text(URL(string: clip.preview)?.host() ?? clip.preview).font(.textHeadline)
                    Text(clip.preview).font(.textCallout.weight(.regular)).foregroundStyle(.secondary)
                }
                .padding(.trailing, shortcut == nil ? 0 : .space8 + .space2)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !isSwatch {
                Text(detailText)
                    .font(.textCallout.weight(.regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, .space2)
                    .background(onImage ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear), in: .capsule)
            }
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.textCallout.weight(.regular))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, .space1)
                    .frame(height: 18)
                    .background(.chrome(0.1), in: .rect(cornerRadius: .radiusSmall))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, .space3)
        .padding(.bottom, .space2)
    }

    // MARK: Words

    private var isSwatch: Bool { hexColor != nil }
    private var onImage: Bool { clip.kind == .image && thumbnail != nil }
    private var age: String { clip.usedAt.formatted(.relative(presentation: .named)) }

    private var kindTitle: String {
        switch clip.kind {
        case .text: isSwatch ? "Color" : "Text"
        case .link: "Link"
        case .image: "Image"
        case .file: fileCount == 1 ? "File" : "\(fileCount) Files"
        }
    }

    private var detailText: String {
        switch clip.kind {
        case .text where isSwatch: clip.preview.uppercased()
        case .text, .link: "\(clip.preview.count >= 1000 ? "1000+" : String(clip.preview.count)) characters"
        case .image: ByteCountFormatter.string(fromByteCount: Int64(clip.byteSize), countStyle: .file)
        case .file: clip.fileSizeText
        }
    }

    private var fileCount: Int { clip.preview.split(separator: "\n").count }

    private var fileNames: String {
        clip.preview.split(separator: "\n").map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    private var hexColor: Color? { clip.hexColor }
}

extension Clip {
    /// "#4F46E5" or "4F46E5" renders as a swatch.
    var hexColor: Color? {
        // The user's own color, not a UI color.
        // swiftlint:disable:next raw_color
        hexRGB.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }
}
