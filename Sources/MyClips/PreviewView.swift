import AppKit
import MyClipsCore
import MyKit
import QuickLookUI
import SwiftUI

/// Large preview of the shelf's cursor clip, shown above the shelf (⌘Y, or Space with an empty search).
struct PreviewView: View {
    let model: PanelModel
    @State private var image: NSImage?
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let clip = model.cursorClip {
                content(clip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                metadata(clip)
                    .padding(.horizontal, .space4)
                    .padding(.vertical, .space3)
                    .task(id: clip.id) {
                        image = clip.kind == .image ? await model.image(for: clip) : nil
                        text = await model.fullText(for: clip)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panelSurface()
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func content(_ clip: Clip) -> some View {
        switch clip.kind {
        case .image:
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(.space4)
            } else {
                ProgressView()
            }
        case .file where existingFile(clip) != nil:
            QuickLookView(url: existingFile(clip)!)
                .padding(.space3)
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: .space3) {
                    ForEach(clip.preview.split(separator: "\n").map(String.init), id: \.self) { path in
                        Label {
                            VStack(alignment: .leading) {
                                Text((path as NSString).lastPathComponent).font(.textHeadline)
                                Text(path).font(.textCaption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 40, height: 40)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.space4)
            }
        case .text where clip.hexColor != nil:
            RoundedRectangle(cornerRadius: .radiusCard).fill(clip.hexColor!)
                .overlay(Text(clip.preview.uppercased()).font(.textTitle.monospaced().weight(.semibold)).foregroundStyle(.white).shadow(radius: 3))
                .padding(.space4)
        case .text, .link:
            ScrollView {
                Text(text)
                    .font(looksLikeCode(text) ? .textCode : .textBody)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.space4)
            }
        }
    }

    private func metadata(_ clip: Clip) -> some View {
        HStack(spacing: .space3) {
            if let icon = model.icon(for: clip.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            }
            Text(clip.sourceName ?? "Unknown app")
            // Exact times: telling apart versions of something copied repeatedly.
            Text("Copied \(clip.usedAt.formatted(date: .abbreviated, time: .standard))")
            if clip.createdAt.timeIntervalSince(clip.usedAt).magnitude > 1 {
                Text("First \(clip.createdAt.formatted(date: .abbreviated, time: .shortened))")
            }
            Spacer()
            Text(size(clip))
        }
        .font(.textCallout)
        .foregroundStyle(.secondary)
    }

    private func size(_ clip: Clip) -> String {
        if let image, clip.kind == .image {
            let rep = image.representations.first
            return "\(rep?.pixelsWide ?? 0) × \(rep?.pixelsHigh ?? 0) · "
                + ByteCountFormatter.string(fromByteCount: Int64(clip.byteSize), countStyle: .file)
        }
        if clip.kind == .file { return clip.fileSizeText }
        let lines = text.split(whereSeparator: \.isNewline).count
        return "\(text.count) characters · \(lines) \(lines == 1 ? "line" : "lines")"
    }

    private func existingFile(_ clip: Clip) -> URL? {
        let paths = clip.preview.split(separator: "\n")
        guard paths.count == 1, FileManager.default.fileExists(atPath: String(paths[0])) else { return nil }
        return URL(filePath: String(paths[0]))
    }

    private func looksLikeCode(_ text: String) -> Bool {
        text.contains("{") || text.contains(";") || text.contains("    ") || text.hasPrefix("$ ")
    }
}

/// Full Quick Look preview (images, PDFs, documents, video) for a single file.
private struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url { view.previewItem = url as NSURL }
    }
}

extension Clip {
    /// For files the stored bytes are only the file reference; report the files on disk instead.
    var fileSizeText: String {
        let paths = preview.split(separator: "\n").map(String.init)
        let sizes = paths.compactMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int64 }
        guard !sizes.isEmpty else { return paths.count == 1 ? "Missing" : "\(paths.count) files" }
        let total = ByteCountFormatter.string(fromByteCount: sizes.reduce(0, +), countStyle: .file)
        return paths.count == 1 ? total : "\(paths.count) files · \(total)"
    }
}
