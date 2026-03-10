import AppKit
import SwiftUI

// Swift Package executables cannot use @main or call App.main() safely.
// Bootstrap via NSApplication + NSHostingView instead.

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app icon from the bundled .icns (visible in Dock + ⌘⇥ switcher)
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }

        // Fixed-size, non-resizable window — width matches RecorderView's .frame(width: 420)
        // plus 32 pt of horizontal padding (16 each side). Height is generous enough to
        // show preview + stats + region row + both action buttons without clipping.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 452, height: 560),
            styleMask:   [.titled, .closable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.title = "Screen Recorder"
        window.center()
        window.contentView = NSHostingView(rootView: RecorderView())
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    // Never auto-quit on last-window-close: the recorder window is temporarily
    // hidden (orderOut) during region picking, so we handle quit explicitly.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Quit when the user explicitly closes the recorder window (the × button).
    // Guard against being called for other windows (e.g. timeline editor).
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
