import AppKit
import ApplicationServices
import Carbon.HIToolbox
import MyClipsCore
import MyKit
import Observation
import SwiftUI
import os

@Observable
final class AppModel {
    static let historySizes = [1_000, 5_000, 10_000, 50_000]
    /// `-uiTest YES` on launch: shelf ignores outside clicks and opens on a distributed notification,
    /// so scripts/drive.sh can test it without global key events.
    static let uiTest = UserDefaults.standard.bool(forKey: "uiTest")

    /// Persisted; `-paused YES` on launch starts paused (used for UI test runs).
    var paused = UserDefaults.standard.bool(forKey: "paused") {
        didSet {
            watcher.paused = paused
            UserDefaults.standard.set(paused, forKey: "paused")
        }
    }
    private(set) var accessibilityTrusted = AXIsProcessTrusted()
    private(set) var pasteboardAccess = NSPasteboard.general.accessBehavior
    /// `.default` means macOS has not asked yet; myClips only appears in System Settings after the first prompt.
    var needsClipboardAccess: Bool { pasteboardAccess == .ask || pasteboardAccess == .alwaysDeny }
    /// Unpinned clips kept in history.
    var historyLimit = UserDefaults.standard.object(forKey: "historyLimit") as? Int ?? 10_000 {
        didSet {
            UserDefaults.standard.set(historyLimit, forKey: "historyLimit")
            Task { [store, historyLimit] in try? await store.prune(keep: historyLimit) }
        }
    }
    /// User-added bundle IDs that are never captured, on top of `CaptureRules.defaultIgnoredApps`.
    var ignoredApps = UserDefaults.standard.stringArray(forKey: "ignoredApps") ?? [] {
        didSet { UserDefaults.standard.set(ignoredApps, forKey: "ignoredApps") }
    }

    @ObservationIgnored let panel: PanelController
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let watcher = PasteboardWatcher()
    /// ✦ V by default; the user can change it in Settings.
    @ObservationIgnored private(set) lazy var openShortcut = GlobalShortcut(
        name: "openShelf", default: Shortcut(keyCode: kVK_ANSI_V, modifiers: Shortcut.hyper)
    ) { [weak self] in self?.panel.toggle() }
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var capturesSincePrune = 0
    @ObservationIgnored private lazy var settingsWindow = SettingsWindow(title: "myClips Settings", tint: .brand) { [unowned self] in
        SettingsSections(app: self)
    }
    @ObservationIgnored private let log = Logger(subsystem: "dev.maciek.myclips", category: "app")

    init(store: Store) {
        self.store = store
        let panelModel = PanelModel(store: store)
        panel = PanelController(model: panelModel)
        panel.app = self
        panelModel.onPaste = { [weak self] clips, plain in self?.paste(clips, plainText: plain) }
        panelModel.onCopy = { [weak self] clips in self?.copy(clips) }
        watcher.onCapture = { [weak self] payload in self?.record(payload) }
    }

    /// `-dataDir <path>` on launch (e.g. `open myClips.app --args -dataDir /tmp/x`) uses a scratch store.
    static func storeURL() -> URL {
        if let dir = UserDefaults.standard.string(forKey: "dataDir") {
            return URL(filePath: dir).appending(path: "clips.sqlite")
        }
        return URL.applicationSupportDirectory.appending(path: "dev.maciek.myclips/clips.sqlite")
    }

    func start() {
        watcher.paused = paused
        watcher.start()
        _ = openShortcut  // registers the global shortcut
        Task { [store, historyLimit] in try? await store.prune(keep: historyLimit) }
        if Self.uiTest {
            DistributedNotificationCenter.default().addObserver(
                forName: .init("dev.maciek.myclips.toggle"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.panel.toggle() }
            }
        }

        // Permission changes happen in System Settings; refresh what the menu shows.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    // MARK: Capture

    private func record(_ payload: ClipPayload) {
        capturesSincePrune += 1
        let prune = capturesSincePrune >= 100
        if prune { capturesSincePrune = 0 }
        Task { [historyLimit] in
            do {
                try await store.record(payload)
                if prune { try await store.prune(keep: historyLimit) }
            } catch {
                log.error("record failed: \(error.localizedDescription, privacy: .public)")
            }
            if panel.isVisible { panel.model.reload() }
        }
    }

    // MARK: Paste

    private func paste(_ clips: [Clip], plainText: Bool) {
        panel.hide("paste")
        Task {
            guard await write(clips, plainText: plainText) else { return }
            if clips.count == 1, let clip = clips.first { _ = try? await store.markUsed(clip.id) }
            guard AXIsProcessTrusted() else { return }  // clip stays on the pasteboard for a manual Cmd+V
            guard !Self.uiTest else {
                log.notice("ui test: pasted clip to pasteboard, keystroke skipped")
                return
            }
            // Normally myClips never activates; if it did (e.g. just launched), hand focus back first.
            if NSApp.isActive { panel.previousApp?.activate() }
            // Give the previous app's window a moment to become key again.
            try? await Task.sleep(for: .milliseconds(60))
            Paster.sendPasteKeystroke()
        }
    }

    /// ⌘C in the shelf: clipboard only; the shelf stays open and the list keeps its order.
    private func copy(_ clips: [Clip]) {
        Task { _ = await write(clips, plainText: false) }
    }

    /// One clip goes on the clipboard with all its representations (or as plain text). Several go as
    /// one item: their texts one per line, plus rich text with images in shelf order (unless plain text
    /// was asked for). Returns false when there was nothing to write.
    private func write(_ clips: [Clip], plainText: Bool) async -> Bool {
        if let clip = clips.first, clips.count == 1 {
            guard let reps = try? await store.representations(of: clip.id), !reps.isEmpty else { return false }
            Paster.write(reps, plainText: plainText ? Self.string(in: reps) : nil)
        } else {
            var parts: [MultiClip.Part] = []
            for clip in clips {
                // A Finder file copy carries the file's icon as an image; use its path instead.
                if clip.kind == .file {
                    parts.append(.text(clip.preview))
                    continue
                }
                let reps = (try? await store.representations(of: clip.id)) ?? []
                if let part = MultiClip.part(of: reps, fallbackText: nil) { parts.append(part) }
            }
            let composed = MultiClip.compose(parts)
            guard !composed.plainText.isEmpty || composed.rtfd != nil else { return false }
            Paster.write(plainText: composed.plainText, rtfd: plainText ? nil : composed.rtfd)
        }
        watcher.ignoreCurrentChange()
        return true
    }

    private static func string(in reps: [Representation]) -> String? {
        reps.first { $0.type == NSPasteboard.PasteboardType.string.rawValue }.flatMap { String(data: $0.data, encoding: .utf8) }
    }

    // MARK: Menu actions

    func showSettings() {
        panel.hide("settings")
        settingsWindow.show()
    }

    func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned clips and clips on pinboards are kept."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { try? await store.clearHistory() }
    }

    func chooseIgnoredApp() {
        NSApp.activate()
        let open = NSOpenPanel()
        open.directoryURL = URL(filePath: "/Applications")
        open.allowedContentTypes = [.application]
        open.message = "myClips will not record anything copied in this app."
        guard open.runModal() == .OK, let url = open.url,
            let id = Bundle(url: url)?.bundleIdentifier, !ignoredApps.contains(id)
        else { return }
        ignoredApps.append(id)
    }

    func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func openPasteboardSettings() {
        SystemSettingsPane.pasteFromOtherApps.open()
    }

    private func refreshPermissions() {
        accessibilityTrusted = AXIsProcessTrusted()
        pasteboardAccess = NSPasteboard.general.accessBehavior
    }
}
