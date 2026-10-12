import AppKit
import MyClipsCore
import SwiftUI

/// One action list shared by the right-click menu and the ⌘K actions menu.
struct ClipAction: Identifiable {
    enum Kind {
        case button(shortcut: String?, destructive: Bool, perform: () -> Void)
        case submenu([ClipAction])
        case divider
    }

    let id = UUID()
    var title = ""
    var kind: Kind

    static func button(_ title: String, _ shortcut: String? = nil, destructive: Bool = false, perform: @escaping () -> Void) -> ClipAction {
        ClipAction(title: title, kind: .button(shortcut: shortcut, destructive: destructive, perform: perform))
    }

    static let divider = ClipAction(kind: .divider)
}

extension PanelModel {
    /// Actions for `ids` (in shelf order).
    func actions(for ids: [Int64], openPreview: @escaping () -> Void) -> [ClipAction] {
        let clips = self.clips.filter { ids.contains($0.id) }
        guard !clips.isEmpty else { return [] }
        let many = clips.count > 1
        var actions: [ClipAction] = [
            .button(many ? "Paste \(clips.count) clips" : "Paste", "↩") { self.onPaste(clips, false) },
            .button("Paste as Plain Text", "⇧↩") { self.onPaste(clips, true) },
        ]
        if !many {
            actions.append(
                .button("Preview", "⌘Y") {
                    self.select(clips[0].id)
                    openPreview()
                })
        }
        actions.append(.divider)
        let allPinned = clips.allSatisfy(\.isPinned)
        actions.append(.button(allPinned ? "Unpin from Top" : "Pin to Top", "⌘P") { self.setPinned(ids, !allPinned) })
        actions.append(
            ClipAction(
                title: "Add to Pinboard",
                kind: .submenu(
                    pinboards.map { board in .button(board.name) { self.add(ids, to: board.id) } }
                        + [.divider, .button("New Pinboard…") { self.startNewBoard(adding: ids) }]
                )))
        if let board, let name = pinboards.first(where: { $0.id == board })?.name {
            actions.append(.button("Remove from \(name)") { self.remove(ids) })
        }
        actions.append(.divider)
        actions.append(.button(many ? "Delete \(clips.count) clips" : "Delete", "⌘⌫", destructive: true) { self.delete(ids) })
        return actions
    }
}

/// SwiftUI rendering, for `.contextMenu`.
struct ClipActionsMenu: View {
    let actions: [ClipAction]

    var body: some View {
        ForEach(actions) { action in
            switch action.kind {
            case .button(_, let destructive, let perform):
                Button(action.title, role: destructive ? .destructive : nil, action: perform)
            case .submenu(let children):
                Menu(action.title) { ClipActionsMenu(actions: children) }
            case .divider:
                Divider()
            }
        }
    }
}

/// AppKit rendering, for the keyboard-opened actions menu.
@MainActor
enum ClipActionsNSMenu {
    private final class Target: NSObject {
        let perform: () -> Void
        init(_ perform: @escaping () -> Void) { self.perform = perform }
        @objc func run() { perform() }
    }

    static func make(_ actions: [ClipAction]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in actions {
            switch action.kind {
            case .button(let shortcut, _, let perform):
                let target = Target(perform)
                let item = NSMenuItem(title: action.title, action: #selector(Target.run), keyEquivalent: "")
                item.target = target
                item.representedObject = target  // NSMenuItem holds its target weakly
                if let shortcut { item.toolTip = shortcut }
                menu.addItem(item)
            case .submenu(let children):
                let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                item.submenu = make(children)
                menu.addItem(item)
            case .divider:
                menu.addItem(.separator())
            }
        }
        return menu
    }
}
