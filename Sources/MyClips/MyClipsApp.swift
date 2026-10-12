import AppKit
import MyClipsCore
import SwiftUI

@main
struct MyClipsApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    // Without this binding SwiftUI quits the app when its only scene, this item, is hidden in System Settings → Menu Bar.
    @State private var menuBarItemInserted = true

    var body: some Scene {
        MenuBarExtra("myClips", systemImage: "list.clipboard", isInserted: $menuBarItemInserted) {
            SettingsMenu(app: delegate.app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Built eagerly so the menu bar scene never renders before the model exists.
    let app: AppModel = {
        do {
            return AppModel(store: try Store(url: AppModel.storeURL()))
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "myClips could not open its database."
            alert.runModal()
            exit(1)
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.start()
    }
}

/// Shared by the menu bar item and the panel's gear button.
struct SettingsMenu: View {
    @Bindable var app: AppModel

    var body: some View {
        Button("Open myClips") { app.panel.show() }
            .keyboardShortcut("v", modifiers: [.command, .control, .option, .shift])
        Toggle("Pause Capture", isOn: $app.paused)
        Divider()
        if app.needsClipboardAccess {
            Button("Allow Clipboard Access…") { app.openPasteboardSettings() }
        }
        if !app.accessibilityTrusted {
            Button("Enable Direct Paste…") { app.requestAccessibility() }
        }
        if !app.hotKeyRegistered {
            Text("Hyper-V (⌃⌥⇧⌘V) is taken by another app")
        }
        Button("Settings…") { app.showSettings() }
            .keyboardShortcut(",")
        Button("Clear History…") { app.clearHistory() }
        Divider()
        Button("Quit myClips") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
