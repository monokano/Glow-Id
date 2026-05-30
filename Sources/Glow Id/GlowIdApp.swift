import SwiftUI
import UniformTypeIdentifiers

@main
struct GlowIdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Open…") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        panel.allowedContentTypes = [.item]
                        if panel.runModal() == .OK {
                            NSApp.delegate?.application?(NSApp, open: panel.urls)
                        }
                    }
                    .keyboardShortcut("o", modifiers: .command)
                }
                CommandGroup(replacing: .undoRedo) {}
                CommandGroup(replacing: .appSettings) {
                    Button("Preferences…") {
                        appDelegate.openPreferences()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .help) {
                    Button("Glow Id Help") {
                        appDelegate.openHelp()
                    }
                    .keyboardShortcut("?", modifiers: .command)
                    Divider()
                    Button("Change Log") {
                        appDelegate.openChangeLog()
                    }
                }
            }
    }
}
