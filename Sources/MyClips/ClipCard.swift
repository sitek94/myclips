import MyClipsCore
import MyKit
import SwiftUI

struct ClipCard: View {
    let clip: Clip
    let shortcut: Int?
    let selected: Bool
    let model: PanelModel
    @State private var thumbnail: NSImage?
    private var isCursor: Bool { model.cursor == clip.id }

    static let size = CGSize(width: 232, height: 232)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.space3)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .contentSurface()
        .clipShape(.rect(cornerRadius: .radiusCard))
        .overlay {
            RoundedRectangle(cornerRadius: .radiusCard)
                .strokeBorder(selected ? Color.brand : .primary.opacity(0.08), lineWidth: selected ? (isCursor ? 3.5 : 2.5) : 1)
        }
        .shadow(color: .black.opacity(selected ? 0.25 : 0.12), radius: selected ? 10 : 5, y: 3)
        .scaleEffect(selected ? 1.0 : 0.97)
        .animation(.quick, value: selected)
        .task(id: clip.id) {
            thumbnail = await model.thumbnail(for: clip)
        }
    }

    private var header: some View {
        HStack(spacing: .space2) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: .space1) {
                    if clip.isPinned { Image(systemName: "pin.fill").font(.textCaption) }
                    Text(kindTitle).font(.textHeadline)
                }
                Text(clip.usedAt.formatted(.relative(presentation: .named)))
                    .font(.textCaption)
                    .foregroundStyle(.white.secondary)
            }
            Spacer(minLength: 0)
            if let icon = model.icon(for: clip.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 30, height: 30)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, .space3)
        .padding(.vertical, .space2)
        .background(accent.gradient)
    }

    @ViewBuilder
    private var content: some View {
        switch clip.kind {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // swiftlint:disable:next system_font
                Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(.secondary)  // a symbol used as a picture
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .file:
            VStack(alignment: .leading, spacing: .space2) {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 110)
                } else {
                    // swiftlint:disable:next system_font
                    Image(systemName: "doc.fill").font(.system(size: 34)).foregroundStyle(.secondary)  // a symbol used as a picture
                }
                Text(fileNames).font(.textCallout.weight(.medium)).lineLimit(thumbnail == nil ? 3 : 1)
            }
        case .link:
            VStack(alignment: .leading, spacing: .space2) {
                Text(URL(string: clip.preview)?.host() ?? clip.preview).font(.textCallout.weight(.semibold)).lineLimit(1)
                Text(clip.preview).font(.textCaption).foregroundStyle(.tint).lineLimit(5)
            }
        case .text:
            if let color = hexColor {
                RoundedRectangle(cornerRadius: .radiusInner).fill(color)
                    .overlay(
                        Text(clip.preview.uppercased()).font(.textCallout.monospaced().weight(.semibold)).foregroundStyle(.white).shadow(radius: 2))
            } else {
                Text(clip.preview.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.textCallout)
                    .lineLimit(8)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText)
            Spacer()
            if let shortcut { Text("⌘\(shortcut)") }
        }
        .font(.textCaption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, .space3)
        .padding(.bottom, .space2)
    }

    private var kindTitle: String {
        switch clip.kind {
        case .text: hexColor == nil ? "Text" : "Color"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        }
    }

    private var accent: Color {
        switch clip.kind {
        case .text: hexColor ?? .indigo
        case .link: .teal
        case .image: .pink
        case .file: .brown
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
        guard kind == .text else { return nil }
        let hex = preview.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        // The user's own color, not a UI color.
        // swiftlint:disable:next raw_color
        return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
