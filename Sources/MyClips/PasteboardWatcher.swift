import AppKit
import MyClipsCore
import os

/// Polls the general pasteboard's change count and turns new content into payloads.
final class PasteboardWatcher {
    var paused = false
    var onCapture: (ClipPayload) -> Void = { _ in }

    private let pasteboard = NSPasteboard.general
    private let log = Logger(subsystem: "dev.maciek.myclips", category: "capture")
    private var lastChangeCount: Int
    private var ownChangeCount: Int?
    private var timer: Timer?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Call after myClips itself writes the pasteboard, so its own paste is not captured again.
    func ignoreCurrentChange() {
        ownChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard !paused, changeCount != ownChangeCount else { return }

        let source = NSWorkspace.shared.frontmostApplication
        if let bundleID = source?.bundleIdentifier, ignoredApps.contains(bundleID) {
            log.debug("skipped change from ignored app \(bundleID, privacy: .public)")
            return
        }
        guard let payload = readPayload(source: source) else { return }
        onCapture(payload)
    }

    private var ignoredApps: Set<String> {
        CaptureRules.defaultIgnoredApps.union(UserDefaults.standard.stringArray(forKey: "ignoredApps") ?? [])
    }

    private func readPayload(source: NSRunningApplication?) -> ClipPayload? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        let allTypes = Set(items.flatMap { $0.types.map(\.rawValue) })
        if CaptureRules.shouldSkip(types: allTypes) {
            log.debug("skipped concealed or transient content")
            return nil
        }

        var read: [Representation] = []
        for (index, item) in items.enumerated() {
            for type in CaptureRules.typesToRead(item.types.map(\.rawValue)) {
                guard let data = item.data(forType: NSPasteboard.PasteboardType(type)) else { continue }
                read.append(Representation(item: index, type: type, data: data))
            }
        }
        let reps = CaptureRules.withinBudget(read)
        if reps.count < read.count { log.info("dropped \(read.count - reps.count) oversized representations") }
        guard !reps.isEmpty else { return nil }

        let string = pasteboard.string(forType: .string)
        let kind = CaptureRules.kind(types: allTypes, string: string)
        let text: String = if kind == .file {
            items.compactMap { $0.string(forType: .fileURL).flatMap(URL.init(string:))?.path(percentEncoded: false) }
                .joined(separator: "\n")
        } else {
            string ?? ""
        }
        return ClipPayload(
            kind: kind, text: text, representations: reps,
            sourceBundleID: source?.bundleIdentifier, sourceName: source?.localizedName
        )
    }
}
