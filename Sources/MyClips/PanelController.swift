import AppKit
import Carbon.HIToolbox
import MyClipsCore
import MyKit
import SwiftUI
import os

/// Floats the preview above the shelf without taking keyboard focus from it.
final class PreviewPanel: OverlayPanel {
    init() {
        // The shelf sits at main-menu level, over the Dock; the preview must sit above it.
        super.init(level: .mainMenu)
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hasShadow = true
    }
}

/// Shows the shelf as a sheet on the bottom edge of the screen under the mouse, over the Dock, in a myKit `StripPanel`
/// (a `FloatingPanel`):
/// it takes typing without activating myClips, so the app you were in stays frontmost and receives the paste.
/// Closes on Esc, the hotkey, a paste, a click outside, or another app activating;
/// it stays open when focus moves to system UI such as the screenshot tool.
final class PanelController {
    /// The top bar and a row of cards.
    static let height: CGFloat = 332

    let model: PanelModel
    weak var app: AppModel? {
        didSet {
            guard let app else { return }
            panel.setContent {
                PanelView(model: model, app: app, openPreview: { [weak self] in self?.setPreview(true) })
            }
        }
    }
    // UI test runs happen on a Mac someone is using; their clicks must not close the shelf.
    private let panel = StripPanel(
        edge: .bottom, placement: .sheet, height: PanelController.height, options: .init(closesOnOutsideClick: !AppModel.uiTest))
    private let previewPanel = PreviewPanel()
    private let dragSource: DragSource
    private var keyMonitor: Any?
    private let log = Logger(subsystem: "dev.maciek.myclips", category: "panel")

    init(model: PanelModel) {
        self.model = model
        let preview = NSHostingView(rootView: PreviewView(model: model))
        preview.sizingOptions = []
        previewPanel.contentView = preview
        dragSource = DragSource(window: panel)
        panel.onClose = { [weak self] reason in self?.didClose(reason) }
        dragSource.items = { [weak self] point in
            guard let self else { return [] }
            return self.model.dragItems(at: self.dragSource.contentPoint(point), onScreen: self.picture)
        }
        dragSource.onPress = { [weak self] point in
            // A fast drag can start before this runs; it made its own items.
            guard let self, !self.dragSource.isDragging else { return }
            self.model.prepareDrag(at: self.dragSource.contentPoint(point), onScreen: self.picture)
        }
        // The shelf covers the bottom of the screen; it steps aside for the drop target.
        dragSource.onLeaveWindow = { [weak self] in self?.hide("drag") }
    }

    var isVisible: Bool { panel.isVisible }
    /// The app that was frontmost when the shelf opened; it receives the paste.
    private(set) var previousApp: NSRunningApplication?

    func toggle() {
        if isVisible { hide("hotkey") } else { show() }
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApp : front
        model.prepareForOpen()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        panel.show(on: screen)
        startKeyMonitor()
    }

    /// Before a paste the shelf closes at once: while it slides out it still takes keys, and so the ⌘V.
    func hide(_ reason: String) {
        panel.dismiss(reason, animated: reason != "paste")
    }

    /// After every close, whoever started it: this controller, or the panel itself (outside click, app switch).
    private func didClose(_ reason: String) {
        log.notice("hide: \(reason, privacy: .public)")
        setPreview(false)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func setPreview(_ open: Bool) {
        model.previewing = open && model.cursorClip != nil
        guard model.previewing, let visible = panel.screen?.visibleFrame else {
            previewPanel.orderOut(nil)
            return
        }
        let shelf = panel.frame
        let width = min(1000, shelf.width * 0.7)
        let bottom = shelf.maxY + 12
        let height = min(680, visible.maxY - bottom - 20)
        previewPanel.setFrame(NSRect(x: shelf.midX - width / 2, y: bottom, width: width, height: height), display: true)
        previewPanel.orderFront(nil)
    }

    /// What the shelf shows in this rect (SwiftUI coordinates), a little see-through: a card's drag picture, copied
    /// from the screen instead of drawn again. Nil when the rect is not fully in view.
    private func picture(of frame: CGRect) -> NSImage? {
        guard let view = panel.contentView else { return nil }
        let rect = CGRect(x: frame.minX, y: view.bounds.height - frame.maxY, width: frame.width, height: frame.height)
        guard view.bounds.contains(rect), let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: bitmap)
        return NSImage(size: rect.size, flipped: false) { bounds in
            bitmap.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 0.8, respectFlipped: false, hints: nil)
        }
    }

    /// ⌘K: the same actions as right-click, for the selection, from the keyboard.
    private func showActionsMenu() {
        let actions = model.actions(for: model.selectedClips.map(\.id)) { [weak self] in self?.setPreview(true) }
        guard !actions.isEmpty else { return }
        let menu = ClipActionsNSMenu.make(actions)
        guard let host = panel.contentView else { return }
        let x = host.bounds.maxX - 320
        let y: CGFloat = host.isFlipped ? 64 : host.bounds.maxY - 64
        menu.popUp(positioning: menu.items.first, at: NSPoint(x: x, y: y), in: host)
    }

    private var searchTextSelected: Bool {
        ((panel.firstResponder as? NSTextView)?.selectedRange().length ?? 0) > 0
    }

    /// Runs a text key on the search field's editor directly: the shelf has no Edit menu, and the panel does not
    /// pass these keys on to the field by itself. One case per key, so the complexity rule is off here.
    private func performTextCommand(_ key: SearchFieldKeys.Key) -> Bool {  // swiftlint:disable:this cyclomatic_complexity
        guard let editor = panel.firstResponder as? NSTextView else { return false }
        switch (key.commandLetter, key.code) {
        case ("a", _): editor.selectAll(nil)
        case ("c", _): editor.copy(nil)
        case ("x", _): editor.cut(nil)
        case ("v", _): editor.paste(nil)
        case ("z", _): editor.undoManager?.undo()
        case (_, kVK_Delete): editor.deleteToBeginningOfLine(nil)
        case (_, kVK_LeftArrow) where key.command: editor.moveToBeginningOfLine(nil)
        case (_, kVK_LeftArrow): editor.moveWordLeft(nil)
        case (_, kVK_RightArrow) where key.command: editor.moveToEndOfLine(nil)
        case (_, kVK_RightArrow): editor.moveWordRight(nil)
        default: return false
        }
        return true
    }

    private func startKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only keys for the open shelf: not while it slides out after Esc, and not for the preview or Settings.
            guard let self, self.panel.isKeyWindow, !self.panel.isClosing else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Returns true when the key was consumed. One case per key, so the complexity rule is off here.
    private func handle(_ event: NSEvent) -> Bool {  // swiftlint:disable:this cyclomatic_complexity
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let code = Int(event.keyCode)
        // Letter shortcuts by character, so they follow the keyboard layout.
        let letter = flags == .command ? event.charactersIgnoringModifiers?.lowercased() : nil

        if model.newBoardName != nil {
            if code == kVK_Escape { model.newBoardName = nil; return true }
            return false  // the name field handles everything else, including Return
        }
        let key = SearchFieldKeys.Key(
            code: code, command: flags.contains(.command), option: flags.contains(.option), commandLetter: letter)
        if SearchFieldKeys.ownsKey(key, fieldHasText: !model.query.isEmpty, textSelected: searchTextSelected) {
            return performTextCommand(key)
        }

        switch (code, letter) {
        case (kVK_Escape, _):
            if model.previewing { setPreview(false) } else { hide("esc") }
        case (kVK_Space, nil) where flags.isEmpty && model.query.isEmpty: setPreview(!model.previewing)
        case (_, "y"): setPreview(!model.previewing)
        case (kVK_RightArrow, _): model.moveCursor(by: 1, extending: flags.contains(.shift))
        case (kVK_LeftArrow, _): model.moveCursor(by: -1, extending: flags.contains(.shift))
        case (kVK_Return, _), (kVK_ANSI_KeypadEnter, _): model.pasteSelection(plainText: flags.contains(.shift))
        case (kVK_Tab, _): model.cycleBoard(by: flags.contains(.shift) ? -1 : 1)
        case (kVK_Delete, _) where flags.contains(.command): model.deleteSelection()
        case (_, "a"): model.selectAll()
        case (_, "c"): model.copySelection()
        case (_, "p"): model.togglePinnedSelection()
        case (_, "n"): model.startNewBoard()
        case (_, "k"): showActionsMenu()
        case (_, ","): app?.showSettings()
        case (_, let digit?) where Int(digit).map((1...9).contains) == true: model.paste(at: Int(digit)! - 1)
        default: return false
        }
        return true
    }
}
