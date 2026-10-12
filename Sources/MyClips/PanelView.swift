import MyClipsCore
import MyKit
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
        VStack(spacing: .space3) {
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
        .padding(.top, .space3)
        .padding(.bottom, .space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toast(model.flash)
        .panelSurface()
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
        HStack(spacing: .space2) {
            HStack(spacing: .space2) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused(focus, equals: .search)
            }
            .frame(width: 236)
            .pill()

            TypeFilter(kind: $model.kind)
            BoardChips(model: model, focus: focus)
            Spacer(minLength: 0)
            PermissionButtons(app: app)
            GearMenu(appName: "myClips", openSettings: app.showSettings) {
                AppActions(app: app)
            }
        }
        .padding(.horizontal, .space4)
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
        .buttonStyle(.pill(selected: kind != nil))
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
            Button {
                app.openPasteboardSettings()
            } label: {
                warning("Allow Clipboard Access")
            }
            .buttonStyle(.pill)
        }
        if !app.accessibilityTrusted {
            Button {
                app.requestAccessibility()
            } label: {
                warning("Enable Direct Paste")
            }
            .buttonStyle(.pill)
            .help("Lets myClips press ⌘V for you. Without it, clips are copied and you paste yourself.")
        }
    }

    /// Only the symbol is yellow: yellow text is hard to read.
    private func warning(_ title: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.warning)
        }
    }
}

private struct BoardChips: View {
    @Bindable var model: PanelModel
    var focus: FocusState<PanelField?>.Binding

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .space2) {
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
                        .frame(width: 146)
                        .pill()
                        .focused(focus, equals: .boardName)
                        .onSubmit { model.commitNewBoard() }
                } else {
                    Button("New Pinboard", systemImage: "plus") { model.startNewBoard() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.pillIcon)
                        .help("New pinboard (⌘N)")
                }
            }
            .padding(.vertical, .space1)
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
        }
        .buttonStyle(.pill(selected: selected))
    }
}

// MARK: Cards

private struct CardStrip: View {
    @Bindable var model: PanelModel
    let openPreview: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: .space3) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        ClipCard(
                            clip: clip, shortcut: index < 9 ? index + 1 : nil,
                            selected: model.selected.contains(clip.id), model: model
                        )
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
                .padding(.horizontal, .space4)
                .padding(.vertical, .space1)
            }
            .scrollClipDisabled()
            .onChange(of: model.cursor) { _, id in
                if let id { withAnimation(.quick) { proxy.scrollTo(id, anchor: .center) } }
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
