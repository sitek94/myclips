import AppKit
import MyClipsCore
import SwiftUI

/// ⌘, from the shelf, or "Settings…" in the menus.
final class SettingsWindow {
    private unowned let app: AppModel
    private var window: NSWindow?

    init(app: AppModel) {
        self.app = app
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(app: app)))
            window.title = "myClips Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @Bindable var app: AppModel

    /// "myClips 0.1.0 (12, a1b2c3d)" — the line bug reports ask for.
    static let version: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let commit = info["MyClipsCommit"] as? String ?? "?"
        return "myClips \(version) (\(build), \(commit))"
    }()

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Open myClips", value: "⌃⌥⇧⌘V (Hyper+V)")
                Toggle("Launch at login", isOn: $app.launchAtLogin)
                Toggle("Pause capture", isOn: $app.paused)
                Picker("Keep history", selection: $app.historyLimit) {
                    ForEach(AppModel.historySizes, id: \.self) { Text("\($0.formatted()) clips").tag($0) }
                }
                Text("Pinned clips and pinboards are always kept.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Direct paste (Accessibility)") {
                    if app.accessibilityTrusted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Enable…") { app.requestAccessibility() }
                    }
                }
                LabeledContent("Paste from other apps") {
                    if app.needsClipboardAccess {
                        Button("Allow…") { app.openPasteboardSettings() }
                    } else {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }

            Section {
                // Built-ins cover several password managers; list only the installed ones.
                ForEach(
                    CaptureRules.defaultIgnoredApps.sorted().filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
                    id: \.self
                ) { id in
                    AppRow(bundleID: id) { Text("Built in").foregroundStyle(.secondary) }
                }
                ForEach(app.ignoredApps, id: \.self) { id in
                    AppRow(bundleID: id) {
                        Button("Remove", role: .destructive) { app.ignoredApps.removeAll { $0 == id } }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…") { app.chooseIgnoredApp() }
            } header: {
                Text("Ignored apps")
            } footer: {
                Text("Nothing copied in these apps is recorded. Content that password managers mark as concealed is always skipped.")
            }

            Section {
                Button("Clear History…", role: .destructive) { app.clearHistory() }
            } footer: {
                Text(Self.version).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .tint(.brand)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AppRow<Trailing: View>: View {
    let bundleID: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        LabeledContent {
            trailing()
        } label: {
            Label {
                Text(url.map { $0.deletingPathExtension().lastPathComponent } ?? bundleID)
            } icon: {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app.dashed")
                }
            }
        }
    }
}
