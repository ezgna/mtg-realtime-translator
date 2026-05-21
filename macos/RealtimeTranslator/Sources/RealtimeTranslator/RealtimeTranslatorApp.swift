import AppKit
import RealtimeTranslatorCore
import SwiftUI

@main
@MainActor
final class RealtimeTranslatorApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var viewModel: AppViewModel?

    static func main() {
        let app = NSApplication.shared
        let delegate = RealtimeTranslatorApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = AppViewModel()
        self.viewModel = viewModel
        let contentView = ContentView(viewModel: viewModel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Realtime Translator"
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
