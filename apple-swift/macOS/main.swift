import AppKit
import MigoMacV8

/// A window holding the game at a phone's proportions (`demo` is portrait).
/// The app quits when the game asks to exit or the window closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.menu()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 844),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Migo example"
        do {
            let gameView = try ExampleGame.makeView()
            window.contentView = gameView
            ExampleGame.run(in: gameView, onExit: { NSApp.terminate(nil) })
        } catch {
            window.contentView = NSTextField(labelWithString: "Could not install the game: \(error.localizedDescription)")
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private static func menu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Migo example", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(item)
        return menu
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
