import MyClipsCore
import SwiftUI

enum PanelField: Hashable {
    case search, boardName
}

struct PanelView: View {
    @Bindable var model: PanelModel
    let app: AppModel
    let openPreview: () -> Void
    // One focus state for the whole panel; separate ones fought over first responder.
    @FocusState private var focus: PanelField?

    var body: some View {
        VStack(spacing: 12) {
            TopBar(model: model, app: app, focus: $focus)
            if model.clips.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty && model.kind == nil ? "Nothing here yet" : "No matches",
                    systemImage: model.board == nil ? "list.clipboard" : "pin"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CardStrip(model: model, openPreview: openPreview)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if let flash = model.flash {
                Label(flash, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(.green.opacity(0.3)), in: .capsule)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.flash)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .ignoresSafeArea()
        .tint(.brand)
        .onChange(of: model.openCount, initial: true) {
            // Focus may still read .search from the last opening; cycle it so the field really takes focus.
            focus = nil
            Task { focus = .search }
        }
        .onChange(of: model.newBoardName == nil) { _, closed in
            focus = closed ? .search : .boardName
        }
    }
}

// MARK: Top bar

private struct TopBar: View {
    @Bindable var model: PanelModel
    @Bindable var app: AppModel
    var focus: FocusState<PanelField?>.Binding

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused(focus, equals: .search)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(width: 260)
            .glassEffect(.regular, in: .capsule)

            TypeFilter(kind: $model.kind)
            BoardChips(model: model, focus: focus)
            Spacer(minLength: 0)
            PermissionButtons(app: app)
            Menu {
                SettingsMenu(app: app)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 18)
    }
}

/// Resets to All Types every time the shelf opens.
private struct TypeFilter: View {
    @Binding var kind: ClipKind?

    var body: some View {
        Menu {
            Picker("Type", selection: $kind) {
                Label("All Types", systemImage: "square.grid.2x2").tag(ClipKind?.none)
                Divider()
                ForEach(ClipKind.allCases, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(ClipKind?.some(kind))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(kind?.title ?? "All Types", systemImage: kind?.symbol ?? "square.grid.2x2")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .tint(kind == nil ? nil : .brand)
        .fixedSize()
    }
}

extension ClipKind {
    var title: String {
        switch self {
        case .text: "Text"
        case .link: "Links"
        case .image: "Images"
        case .file: "Files"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

private struct PermissionButtons: View {
    let app: AppModel

    var body: some View {
        if app.needsClipboardAccess {
            Button("Allow Clipboard Access", systemImage: "doc.on.clipboard") { app.openPasteboardSettings() }
                .buttonStyle(.glassProminent)
                .tint(.orange)
        }
        if !app.accessibilityTrusted {
            Button("Enable Direct Paste", systemImage: "keyboard") { app.requestAccessibility() }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .help("Lets myClips press ⌘V for you. Without it, clips are copied and you paste yourself.")
        }
    }
}

private struct BoardChips: View {
    @Bindable var model: PanelModel
    var focus: FocusState<PanelField?>.Binding

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("History", systemImage: "clock", selected: model.board == nil) { model.board = nil }
                ForEach(model.pinboards) { board in
                    chip("\(board.name)  \(board.itemCount)", systemImage: "pin", selected: model.board == board.id) {
                        model.board = board.id
                    }
                    .contextMenu {
                        Button("Delete Pinboard", role: .destructive) { model.deleteBoard(board.id) }
                    }
                }
                if model.newBoardName != nil {
                    TextField("Pinboard name", text: Binding(get: { model.newBoardName ?? "" }, set: { model.newBoardName = $0 }))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(width: 170)
                        .glassEffect(.regular, in: .capsule)
                        .focused(focus, equals: .boardName)
                        .onSubmit { model.commitNewBoard() }
                } else {
                    Button { model.startNewBoard() } label: { Image(systemName: "plus") }
                        .buttonStyle(.glass)
                        .help("New pinboard (⌘N)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
        }
        .buttonStyle(.glass)
        .tint(selected ? .brand : nil)
        .fontWeight(selected ? .semibold : .regular)
    }
}

// MARK: Cards

private struct CardStrip: View {
    @Bindable var model: PanelModel
    let openPreview: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        ClipCard(clip: clip, shortcut: index < 9 ? index + 1 : nil,
                                 selected: model.selected.contains(clip.id), model: model)
                            .id(clip.id)
                            // One handler reading the click count: a separate count-2 gesture makes
                            // SwiftUI hold every single click until the double-click interval passes.
                            .onTapGesture {
                                if NSApp.currentEvent?.clickCount == 2 {
                                    model.onPaste([clip], false)
                                } else {
                                    model.select(clip.id, extend: Self.extendFromModifiers())
                                }
                            }
                            .contextMenu {
                                ClipActionsMenu(actions: model.actions(for: model.targets(for: clip), openPreview: openPreview))
                            }
                        // Pinned clips lead History; a rule marks where they end.
                        if clip.isPinned, model.board == nil, index + 1 < model.clips.count, !model.clips[index + 1].isPinned {
                            Capsule().fill(.secondary.opacity(0.5)).frame(width: 3, height: 160)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .onChange(of: model.cursor) { _, id in
                if let id { withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private static func extendFromModifiers() -> PanelModel.Extend {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { return .range }
        if flags.contains(.command) { return .toggle }
        return .none
    }
}

private struct ClipCard: View {
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
                .padding(12)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.background.opacity(0.92), in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Color.brand : .primary.opacity(0.08), lineWidth: selected ? (isCursor ? 3.5 : 2.5) : 1)
        }
        .shadow(color: .black.opacity(selected ? 0.25 : 0.12), radius: selected ? 10 : 5, y: 3)
        .scaleEffect(selected ? 1.0 : 0.97)
        .animation(.snappy(duration: 0.15), value: selected)
        .task(id: clip.id) {
            thumbnail = await model.thumbnail(for: clip)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if clip.isPinned { Image(systemName: "pin.fill").font(.caption) }
                    Text(kindTitle).font(.headline)
                }
                Text(clip.usedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
            if let icon = model.icon(for: clip.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 30, height: 30)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .file:
            VStack(alignment: .leading, spacing: 8) {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 110)
                } else {
                    Image(systemName: "doc.fill").font(.system(size: 34)).foregroundStyle(.secondary)
                }
                Text(fileNames).font(.callout.weight(.medium)).lineLimit(thumbnail == nil ? 3 : 1)
            }
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Text(URL(string: clip.preview)?.host() ?? clip.preview).font(.callout.weight(.semibold)).lineLimit(1)
                Text(clip.preview).font(.caption).foregroundStyle(.tint).lineLimit(5)
            }
        case .text:
            if let color = hexColor {
                RoundedRectangle(cornerRadius: 10).fill(color)
                    .overlay(Text(clip.preview.uppercased()).font(.callout.monospaced().weight(.semibold)).foregroundStyle(.white).shadow(radius: 2))
            } else {
                Text(clip.preview.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
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
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
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
        return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
