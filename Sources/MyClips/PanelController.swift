import AppKit
import Carbon.HIToolbox
import MyKit
import SwiftUI
import os

/// Floats the preview above the shelf without taking keyboard focus from it.
final class PreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
}

/// Shows the shelf along the bottom of the screen under the mouse, in a myKit `FloatingPanel`:
/// it takes typing without activating myClips, so the app you were in stays frontmost and receives the paste.
/// Closes on Esc, the hotkey, a paste, a click outside, or another app activating;
/// it stays open when focus moves to system UI such as the screenshot tool.
final class PanelController {
    static let height: CGFloat = 330
    static let margin: CGFloat = 8

    let model: PanelModel
    weak var app: AppModel? {
        didSet {
            guard let app else { return }
            panel.setContent(tint: .brand) {
                PanelView(model: model, app: app, openPreview: { [weak self] in self?.setPreview(true) })
            }
        }
    }
    // UI test runs happen on a Mac someone is using; their clicks must not close the shelf.
    private let panel = FloatingPanel(
        contentRect: NSRect(x: 0, y: 0, width: 1200, height: PanelController.height),
        options: .init(closesOnOutsideClick: !AppModel.uiTest)
    )
    private let previewPanel = PreviewPanel()
    private var keyMonitor: Any?
    private let log = Logger(subsystem: "dev.maciek.myclips", category: "panel")

    init(model: PanelModel) {
        self.model = model
        let preview = NSHostingView(rootView: PreviewView(model: model).tint(.brand))
        preview.sizingOptions = []
        previewPanel.contentView = preview
        panel.onClose = { [weak self] reason in self?.didClose(reason) }
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
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(
                NSRect(
                    x: visible.minX + Self.margin, y: visible.minY + Self.margin,
                    width: visible.width - 2 * Self.margin, height: Self.height),
                display: false
            )
        }
        panel.present()
        startKeyMonitor()
    }

    func hide(_ reason: String) {
        panel.dismiss(reason)
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

    private func startKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
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
