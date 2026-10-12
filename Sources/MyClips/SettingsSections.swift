import AppKit
import MyClipsCore
import MyKit
import SwiftUI

/// The sections of the Settings window (⌘, from the shelf, or "Settings…" in the menus).
struct SettingsSections: View {
    @Bindable var app: AppModel

    var body: some View {
        Section("General") {
            LabeledContent("Open myClips") { ShortcutRecorder(app.openShortcut) }
            LaunchAtLoginToggle()
            Toggle("Pause capture", isOn: $app.paused)
            Picker("Keep history", selection: $app.historyLimit) {
                ForEach(AppModel.historySizes, id: \.self) { Text("\($0.formatted()) clips").tag($0) }
            }
            Text("Pinned clips and pinboards are always kept.").font(.textCaption).foregroundStyle(.secondary)
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

        Section("History") {
            Button("Clear History…", role: .destructive) { app.clearHistory() }
        }

        Section("Permissions") {
            PermissionRow("Direct paste (Accessibility)", granted: app.accessibilityTrusted, fixTitle: "Enable…") {
                app.requestAccessibility()
            }
            PermissionRow("Paste from other apps", granted: !app.needsClipboardAccess) {
                SystemSettingsPane.pasteFromOtherApps.open()
            }
        }

        Section("About") {
            VersionLine()
        }
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
