import AppKit
import Carbon.HIToolbox

@MainActor
private final class Registration: TrayShortcutRegistration {
    var isCancelled = false
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    func cancel() { isCancelled = true }
    func releaseKey() { if !isCancelled { action() } }
}

@main
@MainActor
enum TrayShortcutTests {
    private static var checks = 0

    static func main() throws {
        _ = NSApplication.shared
        let domain = "TrayShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var registrations: [Registration] = []
        var refusesRegistration = false
        var activations = 0
        let register: TrayShortcutController.Register = { _, action in
            guard !refusesRegistration else { return nil }
            let token = Registration(action: action)
            registrations.append(token)
            return token
        }
        let controller = TrayShortcutController(defaults: defaults, previewMode: false,
            register: register, action: { activations += 1 })
        controller.start()
        try expect(controller.selection == .disabled && registrations.isEmpty, "Default must not reserve a global key.")
        controller.setShortcut(.controlOptionSpace)
        try expect(controller.selection == .controlOptionSpace && registrations.count == 1, "A chosen shortcut must register.")
        registrations[0].releaseKey()
        try expect(activations == 1, "A registered shortcut must dispatch its action.")
        controller.start()
        try expect(registrations.count == 1, "Repeated startup must not register the same combination twice.")
        refusesRegistration = true
        controller.setShortcut(.controlOptionB)
        try expect(controller.registrationFailed && controller.selection == .controlOptionSpace,
                   "A conflict must retain the working selection and expose an error.")
        try expect(defaults.string(forKey: TrayShortcutController.preferenceKey) == TrayShortcut.controlOptionSpace.rawValue,
                   "A conflict must not persist the failed choice.")
        registrations[0].releaseKey()
        try expect(activations == 2, "A failed replacement must leave the previous shortcut usable.")
        controller.setShortcut(.controlOptionSpace)
        try expect(!controller.registrationFailed && registrations.count == 1, "Keeping the active choice must clear the error without re-registering.")
        refusesRegistration = false
        controller.setShortcut(.controlOptionB)
        try expect(registrations.count == 2 && registrations[0].isCancelled, "Replacement must release the old key.")
        registrations[0].releaseKey()
        registrations[1].releaseKey()
        try expect(activations == 3, "Only the replacement may fire after changing keys.")
        controller.stop()
        try expect(registrations[1].isCancelled, "Shutdown must unregister the key.")
        controller.start()
        try expect(controller.selection == .controlOptionB && registrations.count == 3, "Restart must restore the saved choice.")
        controller.setShortcut(.disabled)
        try expect(registrations[2].isCancelled && controller.selection == .disabled, "Off must immediately release the key.")
        controller.start()
        try expect(registrations.count == 3, "Off must survive restart.")

        defaults.set(TrayShortcut.controlOptionSpace.rawValue, forKey: TrayShortcutController.preferenceKey)
        refusesRegistration = true
        let blocked = TrayShortcutController(defaults: defaults, previewMode: false, register: register, action: {})
        blocked.start()
        try expect(blocked.selection == .disabled && blocked.registrationFailed, "Startup conflict must not claim an active shortcut.")
        blocked.setShortcut(.disabled)
        try expect(!blocked.registrationFailed && defaults.string(forKey: TrayShortcutController.preferenceKey) == "disabled",
                   "Off must clear a startup conflict and its saved choice.")
        defaults.set("obsolete-choice", forKey: TrayShortcutController.preferenceKey)
        blocked.start()
        try expect(blocked.selection == .disabled && !blocked.registrationFailed, "Unknown preferences must safely fall back to Off.")

        let preview = TrayShortcutController(defaults: defaults, previewMode: true, register: register, action: {})
        preview.start()
        preview.setShortcut(.controlOptionB)
        try expect(preview.selection == .controlOptionB && registrations.count == 3,
                   "Preview must change the UI without reserving a key.")
        try expect(defaults.string(forKey: TrayShortcutController.preferenceKey) == "obsolete-choice", "Preview must not write preferences.")

        // Exercise real OS ownership and cleanup without sending desktop input.
        let shortcut = TrayShortcut.allCases.dropFirst().first { choice in
            guard let probe = CarbonTrayHotKey(shortcut: choice, action: {}) else { return false }
            probe.cancel()
            return true
        }
        var nativeActivations = 0
        guard let shortcut, let first = CarbonTrayHotKey(shortcut: shortcut, action: { nativeActivations += 1 }) else {
            throw failure("No preset is available for the OS registration test.")
        }
        let duplicate = CarbonTrayHotKey(shortcut: shortcut, action: {})
        try expect(duplicate == nil, "macOS must reject an occupied combination.")
        try expect(sendHotKeyEvent(first.eventID, kind: kEventHotKeyPressed) == noErr && nativeActivations == 0,
                   "Press events must be handled without toggling before release.")
        try expect(sendHotKeyEvent(first.eventID) == noErr && nativeActivations == 1,
                   "The native Carbon dispatcher must route a release to the registered callback.")
        let foreignID = EventHotKeyID(signature: 0, id: first.eventID.id)
        try expect(sendHotKeyEvent(foreignID) != noErr && nativeActivations == 1,
                   "Another application's event must not trigger the tray.")
        first.cancel()
        first.cancel()
        try expect(sendHotKeyEvent(first.eventID) != noErr && nativeActivations == 1,
                   "A queued release must not activate a cancelled shortcut.")
        var released: CarbonTrayHotKey? = CarbonTrayHotKey(shortcut: shortcut, action: {})
        try expect(released != nil, "Cancelling must free the combination for reuse.")
        released = nil
        let afterDeinit = CarbonTrayHotKey(shortcut: shortcut, action: {})
        try expect(afterDeinit != nil, "Deinitialization must release the key and handler.")
        afterDeinit?.cancel()
        print("TrayShortcutTests: \(checks) passed, including native registration/conflict/event routing/cleanup")
    }

    private static func sendHotKeyEvent(_ id: EventHotKeyID, kind: Int = kEventHotKeyReleased) -> OSStatus {
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kind),
                          0, EventAttributes(kEventAttributeNone), &event) == noErr,
              let event else { return OSStatus(paramErr) }
        defer { ReleaseEvent(event) }
        var id = id
        let result = SetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                                      MemoryLayout<EventHotKeyID>.size, &id)
        guard result == noErr else { return result }
        // Dispatch only within this process, never inject input into the desktop.
        return SendEventToEventTarget(event, GetEventDispatcherTarget())
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw failure(message) }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TrayShortcutTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
