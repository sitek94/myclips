import AppKit
import MyClipsCore
import MyKit
import SwiftUI

@main
struct MyClipsApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarItem("myClips", systemImage: "list.clipboard") {
            AppActions(app: delegate.app)
            Divider()
            AppMenuItems(appName: "myClips", openSettings: delegate.app.showSettings)
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

/// myClips' own menu items, shared by the menu bar item and the shelf's gear menu.
struct AppActions: View {
    @Bindable var app: AppModel

    var body: some View {
        Button("Open myClips") { app.panel.show() }
            .keyboardShortcut(app.openShortcut.shortcut?.menuShortcut)
        Toggle("Pause Capture", isOn: $app.paused)
        Divider()
        if app.needsClipboardAccess {
            Button("Allow Clipboard Access…") { app.openPasteboardSettings() }
        }
        if !app.accessibilityTrusted {
            Button("Enable Direct Paste…") { app.requestAccessibility() }
        }
        if let shortcut = app.openShortcut.shortcut, !app.openShortcut.isRegistered {
            Text("\(shortcut.displayText) is used by another app")
        }
        Button("Clear Clipboard…") { app.clearHistory() }
    }
}
