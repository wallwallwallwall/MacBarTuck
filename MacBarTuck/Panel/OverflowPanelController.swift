import AppKit
import SwiftUI

@MainActor
final class OverflowPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let store: MenuBarItemStore
    private let language: AppLanguageController
    private let presentation = OverflowPanelPresentationState()
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var closeWorkItem: DispatchWorkItem?
    private weak var anchorButton: NSStatusBarButton?
    // Synthetic status-item clicks can generate a mouse-moved notification at
    // the menu bar. Tell the owner before dispatching the activation so its
    // hover revealer cannot immediately reopen this panel over the menu that
    // the click just opened.
    var onItemActivation: (() -> Void)?
    var onSettings: (() -> Void)?

    init(store: MenuBarItemStore, language: AppLanguageController = .shared) {
        self.store = store
        self.language = language
        panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 260, height: OverflowPanelView.preferredHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        updateLocalization()
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let store = self.store
        let presentation = self.presentation
        let activateAction: (MenuBarItem) -> Void = { [weak self] item in
            self?.onItemActivation?()
            self?.close()
            self?.store.activate(item)
        }
        let rightActivateAction: (MenuBarItem) -> Void = { [weak self] item in
            self?.onItemActivation?()
            self?.close()
            self?.store.activate(item, mouseButton: .right)
        }
        let retuckAction: () -> Void = { [weak self] in
            self?.close()
            self?.store.retuckTemporarilyVisibleItems()
        }
        let settingsAction: () -> Void = { [weak self] in self?.openSettings() }
        panel.contentView = NSHostingView(rootView: AppLocalizedRoot(language: language) {
            OverflowPanelView(
                store: store,
                presentation: presentation,
                onActivate: activateAction,
                onRightActivate: rightActivateAction,
                onRetuck: retuckAction,
                onSettings: settingsAction
            )
        })
        MacBarTuckTrayAppearance.apply(to: panel)
        panel.orderOut(nil)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.panel.isVisible, let button = self.anchorButton else { return }
                _ = self.positionPanel(relativeTo: button)
            }
        }
    }

    func toggle(relativeTo button: NSStatusBarButton) { isVisible ? close() : show(relativeTo: button) }
    var isVisible: Bool { panel.isVisible && closeWorkItem == nil }

    func openSettings() {
        close()
        onSettings?()
    }

    func updateLocalization() {
        let title = language.text("window.panel")
        panel.title = title
        panel.setAccessibilityLabel(title)
    }
    func show(relativeTo button: NSStatusBarButton) {
        guard let frame = button.macBarTuckScreenFrame else { return }
        anchorButton = button
        show(relativeTo: frame)
    }

    func show(relativeTo anchorFrame: CGRect) {
        guard !isVisible else { return }
        closeWorkItem?.cancel()
        closeWorkItem = nil
        guard positionPanel(relativeTo: anchorFrame) else { return }
        presentation.isPresented = false
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            withAnimation(.easeOut(duration: self.reduceMotion ? 0.08 : 0.12)) {
                self.presentation.isPresented = true
            }
        }
        // Discovery and icon capture may involve WindowServer or
        // ScreenCaptureKit. Keep them behind the first visible frame so hover
        // animation is never held up by a refresh.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.store.refreshIfWindowSetChanged(immediate: false)
            self.store.refreshImages(for: self.store.overflowItems.filter { $0.displayImage == nil })
        }
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isPointerAtAnchor else { return }
            self.close()
        }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Buttons activate on mouse-up. Dismissing on an internal
            // mouse-down removes them before a normal or held click finishes.
            guard let self, event.window !== self.panel,
                  !self.isPointerAtAnchor else { return event }
            self.close()
            return event
        }
    }

    func close() {
        guard isVisible else { return }
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor); self.globalEventMonitor = nil }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor); self.localEventMonitor = nil }
        withAnimation(.easeOut(duration: reduceMotion ? 0.06 : 0.10)) {
            presentation.isPresented = false
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            self?.closeWorkItem = nil
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.06 : 0.11), execute: workItem)
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    deinit {
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        closeWorkItem?.cancel()
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var isPointerAtAnchor: Bool {
        anchorButton?.macBarTuckScreenFrame?.contains(NSEvent.mouseLocation) == true
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) -> Bool {
        guard let frame = button.macBarTuckScreenFrame else { return false }
        return positionPanel(relativeTo: frame)
    }

    private func positionPanel(relativeTo buttonFrame: CGRect) -> Bool {
        guard let screen = screen(containing: CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)) else { return false }
        let usableFrame = usableFrame(for: screen)
        guard !usableFrame.isNull, usableFrame.width > 0, usableFrame.height > 0 else { return false }

        let desiredWidth = OverflowPanelView.preferredWidth(
            itemCount: store.overflowItems.count,
            showsRetuck: !store.temporarilyVisibleItems.isEmpty
        )
        let maximumWidth = max(96, min(720, usableFrame.width - 16))
        let width = min(desiredWidth, maximumWidth)
        let height = OverflowPanelView.preferredHeight
        panel.setContentSize(.init(width: width, height: height))

        let minimumX = usableFrame.minX + 8
        let maximumX = usableFrame.maxX - width - 8
        let x = maximumX >= minimumX
            ? min(max(buttonFrame.midX - width / 2, minimumX), maximumX)
            : usableFrame.midX - width / 2
        let proposedY = buttonFrame.minY - height - 5
        let minimumY = usableFrame.minY + 6
        let maximumY = usableFrame.maxY - height - 5
        let y = maximumY >= minimumY ? min(max(proposedY, minimumY), maximumY) : usableFrame.midY - height / 2
        panel.setFrameOrigin(.init(x: x.rounded(.toNearestOrAwayFromZero), y: y.rounded(.toNearestOrAwayFromZero)))
        return true
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }) ?? NSScreen.main
    }

    private func usableFrame(for screen: NSScreen) -> CGRect {
        let insets = screen.safeAreaInsets
        let safeFrame = CGRect(
            x: screen.frame.minX + insets.left,
            y: screen.frame.minY + insets.bottom,
            width: max(0, screen.frame.width - insets.left - insets.right),
            height: max(0, screen.frame.height - insets.top - insets.bottom)
        )
        let intersection = screen.visibleFrame.intersection(safeFrame)
        return intersection.isNull ? screen.visibleFrame : intersection
    }
}
