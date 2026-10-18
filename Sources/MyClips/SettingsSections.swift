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
            Picker("Keep in Clipboard", selection: $app.historyLimit) {
                ForEach(AppModel.historySizes, id: \.self) { Text("\($0.formatted()) clips").tag($0) }
            }
            Text("Pinned clips and pinboards are always kept.").font(.textCaption).foregroundStyle(.secondary)
        }

        Section("Sounds") {
            Toggle("Play sounds", isOn: $app.playsSounds)
            SoundPicker(title: "When a clip is saved", selection: $app.saveSound, sounds: app.sounds)
            SoundPicker(title: "When clips are pasted", selection: $app.pasteSound, sounds: app.sounds)
            Text("Lists the sounds in ~/Library/Sounds and the macOS sounds.").font(.textCaption).foregroundStyle(.secondary)
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

        Section("Clipboard") {
            Button("Clear Clipboard…", role: .destructive) { app.clearHistory() }
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
            AboutRow()
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

/// Plays the sound on a pick, so the user hears it.
private struct SoundPicker: View {
    let title: String
    @Binding var selection: String
    let sounds: Sounds
    @State private var names = Sounds.names()

    var body: some View {
        Picker(title, selection: $selection) {
            // A sound picked earlier and since removed stays visible as the selection.
            ForEach(names.contains(selection) ? names : [selection] + names, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: selection) { _, name in sounds.play(named: name) }
    }
}
