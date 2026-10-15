import MyClipsCore
import MyKit
import SwiftUI

/// One clip, as a card: the content in a rounded box with the source app's icon at
/// its corner; under it the time, or Paste on the card the keys act on. The accent ring marks the selection.
struct ClipCard: View {
    static let cell = CGSize(width: 255, height: 210)
    static let box = CGSize(width: 185, height: 130)
    static let boxTop: CGFloat = 25
    static let iconSize: CGFloat = 40
    static let pinSize: CGFloat = 22
    /// The app icon's corner from the box's bottom-right corner.
    static let iconOutset: CGFloat = 15
    static let pasteBottom: CGFloat = 15
    static let timeBottom: CGFloat = 20
    static let timeHeight: CGFloat = 20

    let clip: Clip
    let shortcut: Int?
    let selected: Bool
    let model: PanelModel
    @State private var thumbnail: NSImage?
    private var isCursor: Bool { model.cursor == clip.id }

    var body: some View {
        ZStack(alignment: .top) {
            box.padding(.top, Self.boxTop)
            VStack {
                Spacer()
                if isCursor {
                    Button(model.selected.count > 1 ? "⏎ Paste \(model.selected.count)" : "⏎ Paste") {
                        model.pasteSelection(plainText: false)
                    }
                    .buttonStyle(.smallPrimary)
                    .padding(.bottom, Self.pasteBottom)
                } else {
                    footer
                }
            }
        }
        .contentShape(.rect)
        .help("\(kindTitle), \(footerText)")
        .task(id: clip.id) {
            thumbnail = await model.thumbnail(for: clip)
        }
    }

    private var box: some View {
        content
            .frame(width: Self.box.width, height: Self.box.height)
            .background(.background)
            .clipShape(.rect(cornerRadius: .radiusCard))
            .overlay(RoundedRectangle(cornerRadius: .radiusCard).strokeBorder(.gray.opacity(0.2)))
            .shadow(color: .black.opacity(0.3), radius: 13, y: 5)
            .selectionRing(selected)
            .overlay(alignment: .topLeading) {
                // On the corner, outside the content: a pin inside the box would cover the first letters.
                if clip.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.textCaption)
                        .frame(width: Self.pinSize, height: Self.pinSize)
                        .background(.background, in: .circle)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: -Self.pinSize / 3, y: -Self.pinSize / 3)
                        .accessibilityLabel("Pinned")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let icon = model.icon(for: clip.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                        .offset(x: Self.iconOutset, y: Self.iconOutset)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch clip.kind {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                // swiftlint:disable:next system_font
                Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(.secondary)  // a symbol used as a picture
            }
        case .file:
            VStack(spacing: .space2) {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    // swiftlint:disable:next system_font
                    Image(systemName: "doc.fill").font(.system(size: 34)).foregroundStyle(.secondary)  // a symbol used as a picture
                }
                Text(fileNames).font(.textCaption.weight(.medium)).lineLimit(1)
            }
            .padding(.space3)
        case .link:
            VStack(alignment: .leading, spacing: .space1) {
                Text(URL(string: clip.preview)?.host() ?? clip.preview).font(.textCallout.weight(.semibold)).lineLimit(1)
                Text(clip.preview).font(.textCaption).foregroundStyle(.tint).lineLimit(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.space3)
        case .text:
            if let color = hexColor {
                color.overlay(
                    Text(clip.preview.uppercased()).font(.textCallout.monospaced().weight(.semibold)).foregroundStyle(.white).shadow(radius: 2))
            } else {
                Text(clip.preview.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.textCaption)
                    .lineLimit(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.space3)
            }
        }
    }

    /// The time it was last used, and ⌘1–⌘9 on the first nine cards.
    private var footer: some View {
        HStack(spacing: .space2) {
            if let shortcut { Text("⌘\(shortcut)").monospacedDigit() }
            Text(clip.usedAt.formatted(.relative(presentation: .named)))
        }
        .font(.textBody)
        .foregroundStyle(.primary.opacity(0.5))
        .lineLimit(1)
        .frame(height: Self.timeHeight)
        .padding(.bottom, Self.timeBottom)
    }

    private var kindTitle: String {
        switch clip.kind {
        case .text: hexColor == nil ? "Text" : "Color"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        }
    }

    private var footerText: String {
        switch clip.kind {
        case .text, .link: "\(clip.preview.count >= 1000 ? "1000+" : String(clip.preview.count)) characters"
        case .image: ByteCountFormatter.string(fromByteCount: Int64(clip.byteSize), countStyle: .file)
        case .file: clip.fileSizeText
        }
    }

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
