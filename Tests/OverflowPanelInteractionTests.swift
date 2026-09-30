import AppKit

@main
@MainActor
enum OverflowPanelInteractionTests {
    static func main() async throws {
        _ = NSApplication.shared
        let domain = "OverflowPanelInteractionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let language = AppLanguageController(defaults: defaults, preferredLanguages: ["en"],
                                             arguments: [], rootBundle: .main)
        let store = MenuBarItemStore(preferences: PreferencesStore(defaults: defaults), language: language)
        let controller = OverflowPanelController(store: store, language: language)
        let screen = NSScreen.main!.frame
        let anchor = CGRect(x: screen.maxX - 100, y: screen.maxY - 24, width: 24, height: 24)
        defer { controller.close() }
        controller.show(relativeTo: anchor)
        try await Task.sleep(for: .milliseconds(180))
        guard controller.isVisible else { throw failure("The fixture tray did not open.") }
        let panel = NSApp.windows.first { $0.title == language.text("window.panel") }!

        // Route a local event through AppKit without posting input to the desktop.
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20),
                                      modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                      context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        guard down.window === panel else { throw failure("The fixture event has no tray window.") }
        NSApp.sendEvent(down)
        try await Task.sleep(for: .milliseconds(200))
        guard controller.isVisible else {
            throw failure("A mouse-down inside the tray dismissed it before mouse-up could activate its button.")
        }
        let right = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 20, y: 20),
                                       modifierFlags: [], timestamp: 1, windowNumber: panel.windowNumber,
                                       context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        NSApp.sendEvent(right)
        try await Task.sleep(for: .milliseconds(150))
        guard controller.isVisible else { throw failure("Right-clicking tray background dismissed it.") }

        let outside = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 200, height: 100),
                               styleMask: .borderless, backing: .buffered, defer: false)
        outside.isReleasedWhenClosed = false
        defer { outside.close() }
        let outsideDown = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 20, y: 20),
                                             modifierFlags: [], timestamp: 2, windowNumber: outside.windowNumber,
                                             context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!
        NSApp.sendEvent(outsideDown)
        try await Task.sleep(for: .milliseconds(150))
        guard !controller.isVisible else { throw failure("Right-clicking another window left the tray open.") }
        controller.show(relativeTo: anchor)
        controller.close()
        controller.show(relativeTo: anchor)
        try await Task.sleep(for: .milliseconds(180))
        guard controller.isVisible else {
            throw failure("Reopening the tray during its fade-out was lost to the old close callback.")
        }
        controller.close()
        try await Task.sleep(for: .milliseconds(180))
        guard !controller.isVisible else { throw failure("Closing the tray left its window visible.") }
        print("OverflowPanelInteractionTests: held click, right click, outside dismissal, reopen and close passed")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "OverflowPanelInteractionTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
