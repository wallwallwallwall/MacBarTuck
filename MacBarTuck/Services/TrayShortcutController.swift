import AppKit
import Carbon.HIToolbox
import Combine

enum TrayShortcut: String, CaseIterable, Identifiable {
    case disabled, controlOptionSpace, controlOptionB

    var id: String { rawValue }
    var localizationKey: String { "preferences.shortcut.\(rawValue)" }
    var keyCode: UInt32 { UInt32(self == .controlOptionB ? kVK_ANSI_B : kVK_Space) }
    var modifiers: UInt32 { UInt32(controlKey | optionKey) }
}

@MainActor
protocol TrayShortcutRegistration: AnyObject {
    func cancel()
}

@MainActor
final class TrayShortcutController: ObservableObject {
    static let preferenceKey = "trayShortcutV1"
    typealias Register = @MainActor (TrayShortcut, @escaping () -> Void) -> (any TrayShortcutRegistration)?

    @Published private(set) var selection: TrayShortcut = .disabled
    @Published private(set) var registrationFailed = false
    private let defaults: UserDefaults
    private let previewMode: Bool
    private let register: Register
    private let action: () -> Void
    private var registration: (any TrayShortcutRegistration)?

    init(defaults: UserDefaults = .standard,
         previewMode: Bool = ProcessInfo.processInfo.arguments.contains("--ui-preview"),
         register: @escaping Register = { CarbonTrayHotKey(shortcut: $0, action: $1) },
         action: @escaping () -> Void) {
        self.defaults = defaults
        self.previewMode = previewMode
        self.register = register
        self.action = action
    }

    func start() {
        guard !previewMode else { return }
        let saved = defaults.string(forKey: Self.preferenceKey).flatMap(TrayShortcut.init(rawValue:)) ?? .disabled
        setShortcut(saved)
    }

    func setShortcut(_ shortcut: TrayShortcut) {
        if shortcut == selection, registration != nil {
            registrationFailed = false
            return
        }
        guard shortcut != selection || registrationFailed else { return }
        if previewMode {
            selection = shortcut
            return
        }
        var replacement: (any TrayShortcutRegistration)?
        if shortcut != .disabled {
            // Keep the working registration until the replacement succeeds.
            guard let next = register(shortcut, action) else {
                registrationFailed = true
                return
            }
            replacement = next
        }
        registration?.cancel()
        registration = replacement
        selection = shortcut
        registrationFailed = false
        defaults.set(shortcut.rawValue, forKey: Self.preferenceKey)
    }

    func stop() {
        registration?.cancel()
        registration = nil
        selection = .disabled
    }
}

@MainActor
final class CarbonTrayHotKey: TrayShortcutRegistration {
    private static var nextID: UInt32 = 0
    private static let signature: OSType = 0x4D42544B // MBTK
    let eventID: EventHotKeyID
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init?(shortcut: TrayShortcut, action: @escaping () -> Void) {
        guard shortcut != .disabled, !Self.isSystemShortcut(shortcut) else { return nil }
        Self.nextID &+= 1
        eventID = EventHotKeyID(signature: Self.signature, id: Self.nextID)
        self.action = action
        // Release fires once per gesture, including when a key is held down.
        let eventTypes = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        let installed = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let context, Thread.isMainThread else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<CarbonTrayHotKey>.fromOpaque(context).takeUnretainedValue().handle(event)
            }
        }, eventTypes.count, eventTypes, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return nil }
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            eventID, GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        guard result == noErr, hotKey != nil else { cancel(); return nil }
    }

    private func handle(_ event: EventRef?) -> OSStatus {
        guard hotKey != nil, let event else { return OSStatus(eventNotHandledErr) }
        var eventID = EventHotKeyID()
        let status = GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID)
        guard status == noErr, eventID.signature == self.eventID.signature, eventID.id == self.eventID.id else {
            return OSStatus(eventNotHandledErr)
        }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) { action() }
        return noErr
    }

    func cancel() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    private static func isSystemShortcut(_ shortcut: TrayShortcut) -> Bool {
        var entries: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&entries) == noErr,
              let entries = entries?.takeRetainedValue() as? [[String: Any]] else { return false }
        return entries.contains {
            ($0[kHISymbolicHotKeyEnabled] as? Bool) == true &&
                ($0[kHISymbolicHotKeyCode] as? UInt32) == shortcut.keyCode &&
                ($0[kHISymbolicHotKeyModifiers] as? UInt32) == shortcut.modifiers
        }
    }
}
