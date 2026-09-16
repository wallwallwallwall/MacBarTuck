import AppKit
import ApplicationServices
@preconcurrency import CoreGraphics
import OSLog

struct NativeOverflowTransactionResult {
    let succeeded: Bool
    let movedCount: Int
    let rollbackSucceeded: Bool
    let wasNoOp: Bool
}

/// Moves status-item windows by sending WindowServer-targeted Command-drag events.
/// The synthetic drag temporarily updates the system pointer, then restores it
/// to the real pre-operation location captured before the move.
@MainActor
final class MenuBarLayoutManager {
    private enum Placement { case left, right }
    private struct NativeOverflowNode {
        let id: String
        let frame: () -> CGRect?
    }

    private let logger = Logger(subsystem: "com.bartuck.app", category: "layout")
    private let preferences: PreferencesStore
    private let platformPolicy: MenuBarPlatformPolicy
    private let initialWindowIDs: Set<CGWindowID>
    private var controlStatusItemWindowID: CGWindowID?
    private var hiddenStatusItemWindowIDs = [CGWindowID]()
    private var controlStatusItemFrameProvider: (() -> CGRect?)?
    private var hiddenStatusItemFrameProviders = [() -> CGRect?]()
    private var accessibilityElementRefresher: ((MenuBarItem) -> AXUIElement?)?
    private var nativeOverflowOriginalOrder: [String]?
    private var operationGeneration = 0
    func cancelPendingOperations() { operationGeneration += 1 }
    var onHiddenFramesChanged: (([CGRect]) -> Void)?
    init(
        preferences: PreferencesStore,
        platformPolicy: MenuBarPlatformPolicy = .current
    ) {
        self.preferences = preferences
        self.platformPolicy = platformPolicy
        initialWindowIDs = Set(Self.fetchWindowRecords().map(\.id))
    }

    var isEnabled: Bool {
        get { preferences.layoutManagementEnabled }
        set { preferences.layoutManagementEnabled = newValue }
    }

    /// macOS 26 does not expose the stable autosave name as the hosted
    /// status-window title. Keep the WindowServer IDs published by
    /// StatusBarController so layout operations can target the two app-owned
    /// hosts without guessing from Control Center's provisional Item-0/1
    /// names.
    func setStatusItemWindowIDs(control: CGWindowID?, hidden: [CGWindowID]) {
        controlStatusItemWindowID = control
        hiddenStatusItemWindowIDs = hidden
        logger.info("Published status window IDs control=\(control ?? 0, privacy: .public) hiddenCount=\(hidden.count, privacy: .public)")
    }

    func setStatusItemFrameProviders(
        control: @escaping () -> CGRect?,
        hidden: [() -> CGRect?]
    ) {
        controlStatusItemFrameProvider = control
        hiddenStatusItemFrameProviders = hidden
    }

    func setAccessibilityElementRefresher(
        _ refresher: @escaping (MenuBarItem) -> AXUIElement?
    ) {
        accessibilityElementRefresher = refresher
    }

    func applyNativeOverflow(
        managed: [MenuBarItem],
        retained: [MenuBarItem],
        completion: @escaping (NativeOverflowTransactionResult) -> Void
    ) {
        guard platformPolicy.movement == .nativeOverflow, isEnabled,
              let snapshot = nativeOverflowSnapshot(items: managed + retained) else {
            completion(.init(succeeded: false, movedCount: 0,
                             rollbackSucceeded: true, wasNoOp: false))
            return
        }
        let currentIndex = Dictionary(
            uniqueKeysWithValues: snapshot.currentOrder.enumerated().map { ($0.element, $0.offset) }
        )
        let managedIDs = managed.map(nativeItemID).filter {
            snapshot.nodes[$0] != nil
        }.sorted {
            (currentIndex[$0] ?? Int.max) < (currentIndex[$1] ?? Int.max)
        }
        let retainedIDs = retained.map(nativeItemID).filter {
            snapshot.nodes[$0] != nil
        }.sorted {
            (currentIndex[$0] ?? Int.max) < (currentIndex[$1] ?? Int.max)
        }
        let desiredOrder = managedIDs + snapshot.spacerIDs + retainedIDs + [snapshot.controlID]
        performNativeOverflowTransaction(
            nodes: snapshot.nodes,
            currentOrder: snapshot.currentOrder,
            desiredOrder: desiredOrder,
            rememberOriginalOrder: true,
            completion: completion
        )
    }

    func restoreNativeOverflow(
        items: [MenuBarItem],
        completion: @escaping (NativeOverflowTransactionResult) -> Void
    ) {
        guard platformPolicy.movement == .nativeOverflow else {
            completion(.init(succeeded: false, movedCount: 0,
                             rollbackSucceeded: true, wasNoOp: false))
            return
        }
        guard let originalOrder = nativeOverflowOriginalOrder else {
            completion(.init(succeeded: true, movedCount: 0,
                             rollbackSucceeded: true, wasNoOp: true))
            return
        }
        guard let snapshot = nativeOverflowSnapshot(items: items) else {
            completion(.init(succeeded: false, movedCount: 0,
                             rollbackSucceeded: true, wasNoOp: false))
            return
        }
        let currentSet = Set(snapshot.currentOrder)
        var desiredOrder = originalOrder.filter(currentSet.contains)
        let desiredSet = Set(desiredOrder)
        let newIDs = snapshot.currentOrder.filter { !desiredSet.contains($0) }
        if let controlIndex = desiredOrder.firstIndex(of: snapshot.controlID) {
            desiredOrder.insert(contentsOf: newIDs.filter { $0 != snapshot.controlID }, at: controlIndex)
        } else {
            desiredOrder.append(contentsOf: newIDs.filter { $0 != snapshot.controlID })
            desiredOrder.append(snapshot.controlID)
        }
        performNativeOverflowTransaction(
            nodes: snapshot.nodes,
            currentOrder: snapshot.currentOrder,
            desiredOrder: desiredOrder,
            rememberOriginalOrder: false
        ) { [weak self] result in
            if result.succeeded { self?.nativeOverflowOriginalOrder = nil }
            completion(result)
        }
    }

    private func nativeOverflowSnapshot(
        items: [MenuBarItem]
    ) -> (
        nodes: [String: NativeOverflowNode],
        currentOrder: [String],
        spacerIDs: [String],
        controlID: String
    )? {
        guard let controlProvider = controlStatusItemFrameProvider,
              let controlFrame = controlProvider(),
              let targetDisplay = Self.activeDisplayBounds().first(where: {
                  $0.contains(CGPoint(x: controlFrame.midX, y: controlFrame.midY))
              }),
              !hiddenStatusItemFrameProviders.isEmpty else { return nil }

        let controlID = "control"
        var nodes: [String: NativeOverflowNode] = [
            controlID: NativeOverflowNode(id: controlID, frame: controlProvider)
        ]
        let spacerIDs = hiddenStatusItemFrameProviders.indices.map { index in
            let id = "spacer|\(index)"
            nodes[id] = NativeOverflowNode(
                id: id,
                frame: hiddenStatusItemFrameProviders[index]
            )
            return id
        }

        var seenItemIDs = Set<String>()
        for logicalItem in items where !logicalItem.isAlwaysVisibleSystemItem {
            let id = nativeItemID(logicalItem)
            guard seenItemIDs.insert(id).inserted else { continue }
            let item = logicalItem.activationTarget(on: targetDisplay)
            guard item.axElement != nil,
                  let frame = freshNativeFrame(for: item),
                  targetDisplay.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return nil }
            nodes[id] = NativeOverflowNode(id: id) { [weak self] in
                guard let self else { return nil }
                return self.freshNativeFrame(for: item)
            }
        }

        let frames = nodes.compactMap { id, node -> (String, CGRect)? in
            node.frame().map { (id, $0) }
        }
        guard frames.count == nodes.count else { return nil }
        let currentOrder = frames.sorted {
            if abs($0.1.minX - $1.1.minX) > 0.5 { return $0.1.minX < $1.1.minX }
            return $0.0 < $1.0
        }.map(\.0)
        return (nodes, currentOrder, spacerIDs, controlID)
    }

    private func performNativeOverflowTransaction(
        nodes: [String: NativeOverflowNode],
        currentOrder: [String],
        desiredOrder: [String],
        rememberOriginalOrder: Bool,
        completion: @escaping (NativeOverflowTransactionResult) -> Void
    ) {
        guard Set(currentOrder) == Set(desiredOrder),
              currentOrder.count == desiredOrder.count else {
            completion(.init(succeeded: false, movedCount: 0,
                             rollbackSucceeded: true, wasNoOp: false))
            return
        }
        let moves = NativeOverflowLayoutPolicy.movePlan(
            currentOrder: currentOrder,
            desiredOrder: desiredOrder
        )
        if moves.isEmpty {
            if rememberOriginalOrder, nativeOverflowOriginalOrder == nil {
                nativeOverflowOriginalOrder = currentOrder
            }
            DiagnosticLog.shared.record("native.layout_noop", ["items": currentOrder.count])
            completion(.init(succeeded: true, movedCount: 0,
                             rollbackSucceeded: true, wasNoOp: true))
            return
        }

        let generation = operationGeneration
        DiagnosticLog.shared.record("native.layout_begin", [
            "moves": moves.count,
            "items": currentOrder.count
        ])
        executeNativeMoves(
            moves,
            nodes: nodes,
            index: 0,
            generation: generation,
            completed: []
        ) { [weak self] completedMoves, succeeded in
            guard let self else { return }
            guard succeeded else {
                let partialOrder = NativeOverflowLayoutPolicy.applying(
                    completedMoves,
                    to: currentOrder
                ) ?? currentOrder
                let rollbackMoves = NativeOverflowLayoutPolicy.movePlan(
                    currentOrder: partialOrder,
                    desiredOrder: currentOrder
                )
                self.executeNativeMoves(
                    rollbackMoves,
                    nodes: nodes,
                    index: 0,
                    generation: generation,
                    completed: []
                ) { _, rollbackSucceeded in
                    DiagnosticLog.shared.record("native.layout_rollback", [
                        "moved": completedMoves.count,
                        "rollback": rollbackSucceeded ? 1 : 0
                    ])
                    completion(.init(
                        succeeded: false,
                        movedCount: completedMoves.count,
                        rollbackSucceeded: rollbackSucceeded,
                        wasNoOp: false
                    ))
                }
                return
            }
            if rememberOriginalOrder, self.nativeOverflowOriginalOrder == nil {
                self.nativeOverflowOriginalOrder = currentOrder
            }
            DiagnosticLog.shared.record("native.layout_end", [
                "moved": completedMoves.count,
                "items": currentOrder.count
            ])
            completion(.init(
                succeeded: true,
                movedCount: completedMoves.count,
                rollbackSucceeded: true,
                wasNoOp: false
            ))
        }
    }

    private func executeNativeMoves(
        _ moves: [NativeOverflowLayoutMove],
        nodes: [String: NativeOverflowNode],
        index: Int,
        generation: Int,
        completed: [NativeOverflowLayoutMove],
        completion: @escaping ([NativeOverflowLayoutMove], Bool) -> Void
    ) {
        guard generation == operationGeneration else {
            completion(completed, false)
            return
        }
        guard index < moves.count else {
            completion(completed, true)
            return
        }
        let move = moves[index]
        guard let source = nodes[move.sourceID],
              let target = nodes[move.targetID] else {
            completion(completed, false)
            return
        }
        moveNativeNode(source, immediatelyBefore: target) { [weak self] moved in
            guard let self else { return }
            guard moved else {
                completion(completed, false)
                return
            }
            var nextCompleted = completed
            nextCompleted.append(move)
            self.executeNativeMoves(
                moves,
                nodes: nodes,
                index: index + 1,
                generation: generation,
                completed: nextCompleted,
                completion: completion
            )
        }
    }

    private func moveNativeItemBeforeControl(
        _ item: MenuBarItem,
        completion: @escaping (Bool) -> Void
    ) {
        guard let control = controlStatusItemFrameProvider else {
            completion(false)
            return
        }
        let source = nativeNode(for: item)
        moveNativeNode(
            source,
            immediatelyBefore: NativeOverflowNode(id: "control", frame: control),
            completion: completion
        )
    }

    private func moveNativeItemBeforeFirstSpacer(
        _ item: MenuBarItem,
        completion: @escaping (Bool) -> Void
    ) {
        let available = hiddenStatusItemFrameProviders.enumerated().compactMap { index, provider in
            provider().map { (index, provider, $0) }
        }
        guard let first = available.min(by: { $0.2.minX < $1.2.minX }) else {
            completion(false)
            return
        }
        moveNativeNode(
            nativeNode(for: item),
            immediatelyBefore: NativeOverflowNode(id: "spacer|\(first.0)", frame: first.1),
            completion: completion
        )
    }

    private func nativeNode(for item: MenuBarItem) -> NativeOverflowNode {
        NativeOverflowNode(id: nativeItemID(item)) { [weak self, weak item] in
            guard let self, let item else { return nil }
            return self.freshNativeFrame(for: item)
        }
    }

    private func nativeItemID(_ item: MenuBarItem) -> String { "item|\(item.id)" }

    private func freshNativeFrame(for item: MenuBarItem) -> CGRect? {
        if let element = accessibilityElementRefresher?(item) {
            item.axElement = element
            if let frame = currentAXFrame(for: element) {
                return frame
            }
        }
        if let element = item.axElement,
           let frame = currentAXFrame(for: element) {
            return frame
        }
        return nil
    }

    private func moveNativeNode(
        _ source: NativeOverflowNode,
        immediatelyBefore target: NativeOverflowNode,
        completion: @escaping (Bool) -> Void
    ) {
        guard source.id != target.id,
              let sourceFrame = source.frame(),
              let targetFrame = target.frame() else {
            completion(false)
            return
        }
        if sourceFrame.minX < targetFrame.minX,
           abs(sourceFrame.maxX - targetFrame.minX) <= 5 {
            completion(true)
            return
        }
        let start = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let end = CGPoint(x: targetFrame.minX - 2, y: targetFrame.midY)
        guard CGPreflightPostEventAccess(),
              Self.activeDisplayBounds().contains(where: { display in
                  let strip = CGRect(x: display.minX, y: display.minY,
                                     width: display.width, height: 45)
                  return strip.contains(start) && strip.contains(end)
              }),
              let eventSource = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(
                  keyboardEventSource: eventSource,
                  virtualKey: 0x37,
                  keyDown: true
              ),
              let commandUp = CGEvent(
                  keyboardEventSource: eventSource,
                  virtualKey: 0x37,
                  keyDown: false
              ),
              let mouseDown = nativeMouseEvent(.leftMouseDown, at: start, source: eventSource),
              let mouseUp = nativeMouseEvent(.leftMouseUp, at: end, source: eventSource) else {
            completion(false)
            return
        }
        let dragEvents = MenuBarGeometry.coordinateDragPath(
            from: start,
            to: end,
            steps: 40
        ).compactMap {
            nativeMouseEvent(.leftMouseDragged, at: $0, source: eventSource)
        }
        guard dragEvents.count == 40 else {
            completion(false)
            return
        }
        let pointer = CGEvent(source: nil)?.location
        let generation = operationGeneration
        eventSource.localEventsSuppressionInterval = 0
        commandDown.flags = .maskCommand
        commandUp.flags = []
        DiagnosticLog.shared.record("native.move_begin", ["generation": generation])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard CGWarpMouseCursorPosition(start) == .success else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            commandDown.post(tap: .cghidEventTap)
            usleep(50_000)
            mouseDown.post(tap: .cghidEventTap)
            usleep(80_000)
            for event in dragEvents {
                event.post(tap: .cghidEventTap)
                usleep(10_000)
            }
            mouseUp.post(tap: .cghidEventTap)
            commandUp.post(tap: .cghidEventTap)
            if let pointer { CGWarpMouseCursorPosition(pointer) }
            DispatchQueue.main.async { [weak self] in
                self?.verifyNativeMove(
                    source,
                    immediatelyBefore: target,
                    check: 0,
                    consecutiveMatches: 0,
                    generation: generation,
                    completion: completion
                )
            }
        }
    }

    private func verifyNativeMove(
        _ source: NativeOverflowNode,
        immediatelyBefore target: NativeOverflowNode,
        check: Int,
        consecutiveMatches: Int,
        generation: Int,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, generation == self.operationGeneration else {
                completion(false)
                return
            }
            let decision = NativeOverflowMoveVerificationPolicy.decision(
                source: source.frame(),
                target: target.frame(),
                check: check,
                consecutiveMatches: consecutiveMatches
            )
            switch decision {
            case .succeeded:
                DiagnosticLog.shared.record("native.move_end", [
                    "verified": 1,
                    "checks": check + 1
                ])
                completion(true)
            case .failed:
                DiagnosticLog.shared.record("native.move_end", [
                    "verified": 0,
                    "checks": check + 1
                ])
                completion(false)
            case .retry(let nextCheck, let stableMatches):
                self.verifyNativeMove(
                    source,
                    immediatelyBefore: target,
                    check: nextCheck,
                    consecutiveMatches: stableMatches,
                    generation: generation,
                    completion: completion
                )
            }
        }
    }

    private func nativeMouseEvent(
        _ type: CGEventType,
        at point: CGPoint,
        source: CGEventSource
    ) -> CGEvent? {
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.flags = [.maskCommand, .maskNonCoalesced]
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }

    func hide(_ items: [MenuBarItem], relativeTo controlFrame: CGRect, targetAttempt: Int = 0, completion: @escaping (Int) -> Void = { _ in }) {
        guard isEnabled else { completion(0); return }
        switch platformPolicy.movement {
        case .maskOverlay, .nativeOverflow, .assessmentMode:
            completion(0)
            return
        case .accessibility:
            // The macOS 27 menu bar is a composite host. Never send the old
            // per-window Command-drag event to that host: it cannot hide a
            // single icon and can move or disturb the whole bar. AX-backed
            // children are attempted individually; unsupported children are
            // intentionally left visible and reported by the caller.
            completion(hideAccessibilityItems(items.filter { $0.axElement != nil }))
        case .windowServer:
            hideWindowBacked(items, relativeTo: controlFrame, targetAttempt: targetAttempt, completion: completion)
        case .hybrid:
            let accessibilityItems = items.filter { $0.windowID == nil && $0.axElement != nil }
            let windowItems = items.filter { $0.windowID != nil || $0.axElement == nil }
            let movedAccessibility = hideAccessibilityItems(accessibilityItems)
            guard !windowItems.isEmpty else { completion(movedAccessibility); return }
            hideWindowBacked(windowItems, relativeTo: controlFrame, targetAttempt: targetAttempt) { moved in
                completion(movedAccessibility + moved)
            }
        }
    }

    private func hideWindowBacked(_ items: [MenuBarItem], relativeTo controlFrame: CGRect, targetAttempt: Int, completion: @escaping (Int) -> Void) {
        let managedSystemNames = protectedNames(for: items)
        hideAfterRestoringProtectedItems(items, relativeTo: controlFrame, targetAttempt: targetAttempt, managedSystemNames: managedSystemNames, completion: completion)
    }

    private func hideAfterRestoringProtectedItems(_ items: [MenuBarItem], relativeTo controlFrame: CGRect, targetAttempt: Int, managedSystemNames: Set<String>, generation: Int? = nil, completion: @escaping (Int) -> Void) {
        let token = generation ?? operationGeneration
        guard token == operationGeneration else { completion(0); return }
        guard isEnabled else { completion(0); return }
        guard let target = hiddenTargetWindow(), target.frame.width <= 100, Self.isVisibleMenuBarFrame(target.frame) else {
            guard targetAttempt < 20 else {
                logger.error("Visible hidden-section staging target did not appear after bounded retries")
                completion(0)
                return
            }
            logger.info("Hidden staging target pending; retrying attempt \(targetAttempt + 1, privacy: .public)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.hideAfterRestoringProtectedItems(items, relativeTo: controlFrame, targetAttempt: targetAttempt + 1, managedSystemNames: managedSystemNames, generation: token, completion: completion)
            }
            return
        }
        logger.info("Hiding \(items.count, privacy: .public) items relative to window \(target.id, privacy: .public)")
        let managed = items.filter {
            $0.windowID != target.id
        }.filter { !$0.isAlwaysVisibleSystemItem }
         .filter(needsHiding)
        publishCurrentFrames(for: managed)
        hideSequentially(managed, index: 0, movedCount: 0, generation: token) { [weak self] movedCount in
            self?.publishCurrentFrames(for: managed)
            completion(movedCount)
        }
    }

    func reveal(_ item: MenuBarItem, restoreCursorLocation: CGPoint? = nil, completion: @escaping (Bool) -> Void) {
        switch platformPolicy.movement {
        case .maskOverlay, .assessmentMode:
            completion(false)
            return
        case .nativeOverflow:
            moveNativeItemBeforeControl(item, completion: completion)
            return
        case .accessibility:
            guard let element = item.axElement else { completion(false); return }
            completion(setAXPosition(item.restorationFrame.origin, for: element))
            return
        case .hybrid:
            if item.windowID == nil, let element = item.axElement {
                completion(setAXPosition(item.restorationFrame.origin, for: element))
                return
            }
        case .windowServer:
            break
        }
        guard let target = controlTargetWindow() else { completion(false); return }
        // The hidden-section separator reaches the control item's left edge,
        // so the only valid temporary visible slot is immediately to its right.
        move(item, relativeTo: target.id, placement: .right, restoreCursorLocation: restoreCursorLocation, completion: completion)
    }

    func rehide(_ item: MenuBarItem, restoreCursorLocation: CGPoint? = nil, targetAttempt: Int = 0, generation: Int? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        let token = generation ?? operationGeneration
        guard token == operationGeneration else { completion(false); return }
        switch platformPolicy.movement {
        case .maskOverlay, .assessmentMode:
            completion(false)
            return
        case .nativeOverflow:
            moveNativeItemBeforeFirstSpacer(item, completion: completion)
            return
        case .accessibility:
            guard isEnabled, let element = item.axElement else { completion(false); return }
            completion(setAXPosition(hiddenAXPosition(for: item), for: element))
            return
        case .hybrid:
            if item.windowID == nil, let element = item.axElement {
                completion(setAXPosition(hiddenAXPosition(for: item), for: element))
                return
            }
        case .windowServer:
            break
        }
        guard isEnabled, let target = hiddenTargetWindow() else { completion(false); return }
        // Wait for the compact separator to reach WindowServer. The UI
        // length changes asynchronously after a menu is dismissed.
        guard target.frame.width <= 100 else {
            guard targetAttempt < 20 else { completion(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.rehide(item, restoreCursorLocation: restoreCursorLocation,
                             targetAttempt: targetAttempt + 1, generation: token, completion: completion)
            }
            return
        }
        move(item, relativeTo: target.id, placement: .left, restoreCursorLocation: restoreCursorLocation, completion: completion)
    }

    /// Returns true only while a managed item is still occupying the visible
    /// menu bar, so repair passes focus on actual duplicate icons.
    func needsHiding(_ item: MenuBarItem) -> Bool {
        // macOS keeps active privacy/media indicators visible. These
        // Control Center windows are not draggable status items, so do not
        // report a failed layout repair when the system leaves them in place.
        if item.isAlwaysVisibleSystemItem { return false }
        guard item.windowID != nil || item.axElement != nil else { return false }
        return visibility(of: item) != .hidden
    }

    /// Returns whether WindowServer currently places the item in a real menu
    /// bar slot. Hidden items intentionally retain their original window
    /// identity, but their frame is moved completely off the active display.
    /// Activation must distinguish that state from a visible item; using
    /// `needsHiding` for both meanings caused hidden right-clicks to be sent
    /// directly to invalid (negative) coordinates.
    func isVisible(_ item: MenuBarItem) -> Bool {
        let state = visibility(of: item)
        return state == .visible || state == .partial
    }

    func visibility(of item: MenuBarItem) -> MenuItemVisibility {
        MenuItemVisibility.evaluate(item.windowRepresentations.map { representation -> Bool? in
            guard let frame = currentFrame(for: representation) else { return nil }
            return MenuBarGeometry.isVisibleMenuBarItem(
                frame,
                displayBounds: representation.sourceDisplayBounds.map { [$0] }
                    ?? Self.activeDisplayBounds()
            )
        })
    }

    func currentFrame(for item: MenuBarItem) -> CGRect? {
        if let windowID = item.windowID,
           let frame = currentFrame(windowID: windowID) {
            return frame
        }
        guard let element = item.axElement else { return nil }
        return currentAXFrame(for: element)
    }

    /// Quartz screen coordinates captured before any synthetic menu-bar event.
    func currentPointerLocation() -> CGPoint? { CGEvent(source: nil)?.location }

    /// Kept as a compatibility hook for older activation call sites. Move
    /// operations restore the pointer inside `postDrag`; this method is not a
    /// second restoration pass.
    func restorePointerLocation(_ point: CGPoint?) {
        // Intentionally empty.
    }

    func restore(_ items: [MenuBarItem], relativeTo controlFrame: CGRect, completion: @escaping (Int) -> Void = { _ in }) {
        switch platformPolicy.movement {
        case .maskOverlay, .nativeOverflow, .assessmentMode:
            completion(0)
            return
        case .accessibility:
            completion(restoreAccessibilityItems(items.filter { $0.axElement != nil }))
            return
        case .hybrid:
            let accessibilityItems = items.filter { $0.windowID == nil && $0.axElement != nil }
            let windowItems = items.filter { $0.windowID != nil || $0.axElement == nil }
            let restoredAccessibility = restoreAccessibilityItems(accessibilityItems)
            guard !windowItems.isEmpty else { completion(restoredAccessibility); return }
            guard let target = controlTargetWindow() else { completion(restoredAccessibility); return }
            restoreSequentially(Array(windowItems.reversed()), index: 0, target: target, movedCount: restoredAccessibility, completion: completion)
            return
        case .windowServer:
            break
        }
        guard let target = controlTargetWindow() else { completion(0); return }
        restoreSequentially(Array(items.reversed()), index: 0, target: target, movedCount: 0, completion: completion)
    }

    func show(_ item: MenuBarItem) {
        switch platformPolicy.movement {
        case .maskOverlay, .assessmentMode:
            return
        case .nativeOverflow:
            moveNativeItemBeforeControl(item) { _ in }
            return
        case .accessibility:
            guard let element = item.axElement else { return }
            _ = setAXPosition(item.restorationFrame.origin, for: element)
            return
        case .hybrid:
            if item.windowID == nil, let element = item.axElement {
                _ = setAXPosition(item.restorationFrame.origin, for: element)
                return
            }
        case .windowServer:
            break
        }
        guard let target = controlTargetWindow() else { return }
        move(item, relativeTo: target.id, placement: .right) { _ in }
    }

    func restoreProtectedSystemItems(attempt: Int = 0, excluding excludedWindowIDs: Set<CGWindowID> = [], excludingSystemNames: Set<String> = [], completion: @escaping (Int) -> Void = { _ in }) {
        guard platformPolicy.movement != .maskOverlay,
              platformPolicy.movement != .nativeOverflow,
              platformPolicy.movement != .assessmentMode else {
            completion(0)
            return
        }
        guard let target = controlTargetWindow() else {
            guard attempt < 3 else {
                logger.error("Control target unavailable while restoring protected items")
                completion(0)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.restoreProtectedSystemItems(attempt: attempt + 1, excluding: excludedWindowIDs, excludingSystemNames: excludingSystemNames, completion: completion)
            }
            return
        }
        let displays = Self.activeDisplayBounds()
        let hidden = windowRecords().filter {
            MenuBarSystemItemClassifier.isProtected($0.title, owner: $0.owner) &&
                MenuBarGeometry.isHiddenLaneMenuItem($0.frame, displayBounds: displays) &&
                !excludedWindowIDs.contains($0.id) &&
                !excludingSystemNames.contains($0.title) &&
                !excludingSystemNames.contains(MenuBarSystemItemClassifier.canonicalName($0.title, owner: $0.owner)) &&
                !(MenuBarSystemItemClassifier.isGenericControlCenterItem($0.title, owner: $0.owner) && excludingSystemNames.contains("Control Center Item"))
        }
        restoreProtectedSequentially(hidden, index: 0, target: target, movedCount: 0, completion: completion)
    }

    private func protectedNames(for items: [MenuBarItem]) -> Set<String> {
        var names = Set<String>()
        for item in items where item.isProtectedSystemItem {
            names.insert(item.title)
            if item.title == "Control Center Item" {
                names.insert("Control Center Item")
            }
        }
        return names
    }

    /// macOS 15 still exposes some third-party status items only through AX.
    /// Their position attribute is the supported compatibility fallback for
    /// those items; WindowServer-targeted drags remain the primary macOS 26
    /// path because Control Center-owned items do not expose a settable AX
    /// position there.
    private func hideAccessibilityItems(_ items: [MenuBarItem]) -> Int {
        items.reduce(into: 0) { moved, item in
            guard let element = item.axElement,
                  setAXPosition(hiddenAXPosition(for: item), for: element) else { return }
            moved += 1
        }
    }

    private func restoreAccessibilityItems(_ items: [MenuBarItem]) -> Int {
        items.reduce(into: 0) { restored, item in
            guard let element = item.axElement,
                  setAXPosition(item.restorationFrame.origin, for: element) else { return }
            restored += 1
        }
    }

    private func hiddenAXPosition(for item: MenuBarItem) -> CGPoint {
        let leftEdge = NSScreen.screens.map(\.frame.minX).min() ?? 0
        return CGPoint(
            x: leftEdge - item.restorationFrame.width - 16,
            y: item.restorationFrame.minY
        )
    }

    private func setAXPosition(_ point: CGPoint, for element: AXUIElement) -> Bool {
        var position = point
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    private func currentAXFrame(for element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let position = value, CFGetTypeID(position) == AXValueGetTypeID(),
              AXValueGetType(position as! AXValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let sizeValue = value, CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetType(sizeValue as! AXValue) == .cgSize else { return nil }
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func hideSequentially(_ items: [MenuBarItem], index: Int, movedCount: Int, generation: Int? = nil, completion: @escaping (Int) -> Void) {
        let token = generation ?? operationGeneration
        guard token == operationGeneration else { completion(movedCount); return }
        guard index < items.count else { completion(movedCount); return }
        guard let target = hiddenTargetWindow(), Self.isVisibleMenuBarFrame(target.frame) else {
            completion(movedCount)
            return
        }
        let item = items[index]
        move(item, relativeTo: target.id, placement: .left) { [weak self] moved in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                // One failed placement ends the transaction. Continuing to
                // drag other hosts after a timeout makes both bars jump.
                guard moved else { completion(movedCount); return }
                self?.hideSequentially(items, index: index + 1, movedCount: movedCount + 1, generation: token, completion: completion)
            }
        }
    }

    private func publishCurrentFrames(for items: [MenuBarItem]) {
        let frames = items.compactMap { item in
            item.windowID.flatMap(currentFrame(windowID:))
        }
        onHiddenFramesChanged?(frames)
    }

    private func restoreSequentially(_ items: [MenuBarItem], index: Int, target: (id: CGWindowID, frame: CGRect), movedCount: Int, generation: Int? = nil, completion: @escaping (Int) -> Void) {
        let token = generation ?? operationGeneration
        guard token == operationGeneration else { completion(movedCount); return }
        guard index < items.count else { completion(movedCount); return }
        let item = items[index]
        move(item, relativeTo: target.id, placement: .right) { [weak self] moved in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                guard let self, let refreshed = self.controlTargetWindow() else {
                    completion(movedCount + (moved ? 1 : 0))
                    return
                }
                self.restoreSequentially(items, index: index + 1, target: refreshed, movedCount: movedCount + (moved ? 1 : 0), generation: token, completion: completion)
            }
        }
    }

    private func restoreProtectedSequentially(_ records: [(id: CGWindowID, pid: pid_t, title: String, owner: String, frame: CGRect)], index: Int, target: (id: CGWindowID, frame: CGRect), movedCount: Int, generation: Int? = nil, completion: @escaping (Int) -> Void) {
        let token = generation ?? operationGeneration
        guard token == operationGeneration else { completion(movedCount); return }
        guard index < records.count else { completion(movedCount); return }
        let record = records[index]
        let item = MenuBarItem(
            id: "protected|\(record.title)",
            title: record.title,
            ownerName: "System Menu Bar",
            bundleIdentifier: nil,
            frame: record.frame,
            axElement: nil,
            isSelected: false,
            supportsPressAction: false,
            windowID: record.id,
            ownerPID: record.pid
        )
        move(item, relativeTo: target.id, placement: .right) { [weak self] moved in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard let self, let refreshed = self.controlTargetWindow() else {
                    completion(movedCount + (moved ? 1 : 0))
                    return
                }
                self.restoreProtectedSequentially(records, index: index + 1, target: refreshed, movedCount: movedCount + (moved ? 1 : 0), generation: token, completion: completion)
            }
        }
    }

    private func move(_ requestedItem: MenuBarItem, relativeTo targetWindowID: CGWindowID, placement: Placement, attempt: Int = 1, restoreCursorLocation: CGPoint? = nil, completion: @escaping (Bool) -> Void) {
        let generation = operationGeneration
        let displayBounds = Self.activeDisplayBounds()
        guard let targetFrame = currentFrame(windowID: targetWindowID),
              let targetDisplay = displayBounds.first(where: { $0.contains(CGPoint(x: targetFrame.midX, y: targetFrame.midY)) }) else {
            DiagnosticLog.shared.record("move.rejected.target", ["target": Int(targetWindowID)])
            completion(false); return
        }
        if let originalDisplay = requestedItem.sourceDisplayBounds, originalDisplay != targetDisplay,
           requestedItem.representation(on: targetDisplay) == nil {
            DiagnosticLog.shared.record("move.rejected.display", ["window": Int(requestedItem.windowID ?? 0)])
            completion(false); return
        }
        let item = requestedItem.activationTarget(on: targetDisplay)
        // Capture before injecting the synthetic drag. At this point the
        // WindowServer location still matches the real hardware pointer,
        // including when the user clicked inside MacBarTuck itself.
        let physicalPointerLocation = restoreCursorLocation ?? CGEvent(source: nil)?.location
        guard let itemWindowID = item.windowID, let ownerPID = item.ownerPID,
              let itemFrame = currentFrame(windowID: itemWindowID),
              let source = eventSource(for: ownerPID) else {
            completion(false)
            return
        }
        // Control Center requires the synthetic drag coordinates to start on
        // the visible source item. The WindowServer window fields identify
        // the source/destination; keeping the actual points on an active
        // display means a hidden off-screen target cannot clamp the user's
        // hardware pointer. On reveal the hidden source is invalid, so the
        // target's visible frame becomes the safe fallback for both events.
        let itemPoint = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
        let startPoint = targetDisplay.contains(itemPoint) ? itemPoint : CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        guard let destinationPoint = destinationPoint(for: placement, itemFrame: itemFrame, targetFrame: targetFrame),
              targetDisplay.contains(destinationPoint) else {
            DiagnosticLog.shared.record("move.rejected.edge", ["window": Int(itemWindowID), "target": Int(targetWindowID)])
            logger.error("Refusing menu-bar move because the destination edge is off the active display")
            completion(false)
            return
        }
        guard let down = targetedEvent(type: .leftMouseDown, point: startPoint, windowID: itemWindowID, pid: ownerPID, source: source, command: true),
              let dragged = targetedEvent(type: .leftMouseDragged, point: destinationPoint, windowID: targetWindowID, pid: ownerPID, source: source, command: true),
              let up = targetedEvent(type: .leftMouseUp, point: destinationPoint, windowID: targetWindowID, pid: ownerPID, source: source, command: true) else {
            completion(false)
            return
        }
        DiagnosticLog.shared.record("move.begin", ["window": Int(itemWindowID), "target": Int(targetWindowID), "generation": generation])
        postDrag(
            down: down,
            dragged: dragged,
            up: up,
            ownerPID: ownerPID,
            restoreCursorLocation: physicalPointerLocation,
            displayBounds: displayBounds
        ) { [weak self] success in
            guard let self, success, self.operationGeneration == generation else { completion(false); return }
            self.verifyMove(item, relativeTo: targetWindowID, placement: placement, attempt: attempt, check: 0, generation: generation, restoreCursorLocation: physicalPointerLocation, completion: completion)
        }
    }

    private func verifyMove(_ item: MenuBarItem, relativeTo targetWindowID: CGWindowID, placement: Placement, attempt: Int, check: Int, generation: Int, restoreCursorLocation: CGPoint?, completion: @escaping (Bool) -> Void) {
        guard let itemWindowID = item.windowID else { completion(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.operationGeneration == generation else { completion(false); return }
            let itemFrame = self.currentFrame(windowID: itemWindowID)
            let targetFrame = self.currentFrame(windowID: targetWindowID)
            let moved: Bool
            switch placement {
            case .left: moved = abs((itemFrame?.maxX ?? -.infinity) - (targetFrame?.minX ?? .infinity)) < 1
            case .right: moved = abs((itemFrame?.minX ?? -.infinity) - (targetFrame?.maxX ?? .infinity)) < 1
            }
            if moved {
                DiagnosticLog.shared.record("move.verified", ["window": Int(itemWindowID), "target": Int(targetWindowID)])
                self.logger.info("Move verification window \(itemWindowID, privacy: .public) attempt \(attempt, privacy: .public) moved=true")
                completion(true)
            } else if check < 5 {
                self.verifyMove(item, relativeTo: targetWindowID, placement: placement, attempt: attempt, check: check + 1, generation: generation, restoreCursorLocation: restoreCursorLocation, completion: completion)
            } else {
                DiagnosticLog.shared.record("move.timeout", ["window": Int(itemWindowID), "target": Int(targetWindowID)])
                self.logger.info("Move verification window \(itemWindowID, privacy: .public) failed")
                completion(false)
            }
        }
    }

    /// Posts the complete drag gesture through WindowServer. A down/up pair
    /// alone is treated as a click by macOS 26; the dragged event is required
    /// for Control Center's hosted status items. The gesture uses one bounded
    /// jump instead of an off-screen or multi-step path, which avoids the
    /// notch dead-zone while keeping every coordinate on an active display.
    private func postDrag(
        down: CGEvent,
        dragged: CGEvent,
        up: CGEvent,
        ownerPID: pid_t,
        restoreCursorLocation: CGPoint?,
        displayBounds: [CGRect],
        completion: @escaping (Bool) -> Void
    ) {
        let tap: CGEventTapLocation = isControlCenter(ownerPID) ? .cghidEventTap : .cgSessionEventTap
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            down.post(tap: tap)
            usleep(80_000)
            dragged.post(tap: tap)
            usleep(80_000)
            up.post(tap: tap)
            usleep(140_000)
            if let restoreCursorLocation,
               displayBounds.contains(where: { $0.contains(restoreCursorLocation) }),
               let restore = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: restoreCursorLocation, mouseButton: .left) {
                // This is the real pointer location captured before the
                // operation, never a synthetic off-screen or test coordinate.
                restore.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.async {
                self?.logger.info("Posted Command-drag window event via \(tap == .cghidEventTap ? "hid" : "session", privacy: .public)")
                completion(true)
            }
        }
    }

    private func eventSource(for pid: pid_t) -> CGEventSource? {
        let state: CGEventSourceStateID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.controlcenter"
            ? .hidSystemState
            : .privateState
        return CGEventSource(stateID: state)
    }

    private func isControlCenter(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.controlcenter"
    }

    private func destinationPoint(for placement: Placement, itemFrame: CGRect, targetFrame: CGRect) -> CGPoint? {
        let x: CGFloat
        switch placement {
        case .left:
            // Hiding means placing the item immediately before the staging
            // host. The host is compacted by StatusBarController for the
            // duration of a hide transaction, so this edge stays on-screen;
            // never fall back to an interior point, which would place the
            // item back in the visible section.
            let edge = CGPoint(x: targetFrame.minX - 1, y: targetFrame.midY)
            guard Self.activeDisplayBounds().contains(where: { $0.contains(edge) }) else { return nil }
            return edge
        case .right:
            // Drop just beyond the visible control item. Clamp below in
            // `safeEventPoint` if the control item is near a display edge.
            x = targetFrame.maxX + max(2, min(itemFrame.width * 0.25, 8))
        }
        return safeEventPoint(preferred: CGPoint(x: x, y: targetFrame.midY), fallback: targetFrame)
    }

    /// All synthetic drag events must carry an on-screen cursor coordinate.
    /// The target window fields select the status-item source/destination;
    /// using an off-screen point (20,000 or a negative hidden-section frame)
    /// makes WindowServer clamp the logical pointer to the top-left corner.
    private func safeEventPoint(preferred: CGPoint?, fallback: CGRect) -> CGPoint {
        let displays = Self.activeDisplayBounds()
        if let preferred, displays.contains(where: { $0.contains(preferred) }) {
            return preferred
        }
        if let display = displays.first {
            let x = min(max(fallback.midX, display.minX + 8), display.maxX - 8)
            let y = min(max(fallback.midY, display.minY + 8), display.maxY - 8)
            return CGPoint(x: x, y: y)
        }
        return CGPoint(x: 8, y: 8)
    }

    private func targetedEvent(type: CGEventType, point: CGPoint, windowID: CGWindowID, pid: pid_t, source: CGEventSource, command: Bool) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = command ? .maskCommand : []
        // Direct HID posting is the reliable path for macOS 26's protected
        // Control Center host. Supplying an event target PID makes WindowServer
        // drop the hosted drag, so retain that field only for ordinary owners.
        if !isControlCenter(pid) {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        }
        event.setIntegerValueField(.eventSourceUserData, value: Int64.random(in: 1...Int64.max))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        event.setIntegerValueField(CGEventField(rawValue: 0x33)!, value: Int64(windowID))
        return event
    }

    private func controlTargetWindow() -> (id: CGWindowID, frame: CGRect)? {
        let records = windowRecords()
        if let controlStatusItemWindowID,
           let control = records.first(where: { $0.id == controlStatusItemWindowID }) {
            return (control.id, control.frame)
        }
        if let macBarTuck = records.first(where: { $0.title == "BarTuckControlItem" }) {
            return (macBarTuck.id, macBarTuck.frame)
        }
        return records
            .filter { $0.pid == getpid() && $0.frame.width <= 100 && $0.frame.height > 1 }
            .min(by: { $0.id < $1.id })
            .map { ($0.id, $0.frame) }
    }

    private func hiddenTargetWindow() -> (id: CGWindowID, frame: CGRect)? {
        let records = windowRecords()
        if let hidden = records
            .filter({ hiddenStatusItemWindowIDs.contains($0.id) })
            .min(by: { $0.frame.minX < $1.frame.minX }) {
            return (hidden.id, hidden.frame)
        }
        if let hidden = records.first(where: { $0.title == "BarTuckHiddenSection" }) {
            return (hidden.id, hidden.frame)
        }
        return records
            .filter { $0.pid == getpid() && !initialWindowIDs.contains($0.id) && $0.frame.width > 1_000 }
            .max(by: { $0.frame.width < $1.frame.width })
            .map { ($0.id, $0.frame) }
    }

    private func currentFrame(windowID: CGWindowID) -> CGRect? { windowRecords().first { $0.id == windowID }?.frame }

    private static func isVisibleMenuBarFrame(_ frame: CGRect) -> Bool {
        MenuBarGeometry.isVisibleMenuBarItem(
            frame,
            displayBounds: activeDisplayBounds()
        )
    }

    private static func isMenuBarWindowFrame(_ frame: CGRect) -> Bool {
        MenuBarGeometry.isMenuBarItem(
            frame,
            displayBounds: activeDisplayBounds()
        )
    }

    private static func activeDisplayBounds() -> [CGRect] {
        MenuBarDisplayBounds.current()
    }

    private func windowRecords() -> [(id: CGWindowID, pid: pid_t, title: String, owner: String, frame: CGRect)] { Self.fetchWindowRecords() }

    private static func fetchWindowRecords() -> [(id: CGWindowID, pid: pid_t, title: String, owner: String, frame: CGRect)] {
        let list = MenuBarWindowServer.windowInfo()
        return list.compactMap { info -> (id: CGWindowID, pid: pid_t, title: String, owner: String, frame: CGRect)? in
            guard MenuBarWindowServer.isStatusItemLayer(info),
                  let id = MenuBarWindowServer.integer(kCGWindowNumber as String, in: info),
                  let pid = MenuBarWindowServer.integer(kCGWindowOwnerPID as String, in: info),
                  let frame = MenuBarWindowServer.bounds(in: info) else { return nil }
            // Quartz window coordinates are global. On a vertically arranged
            // multi-display setup, or on systems that place the menu bar at a
            // non-zero global Y coordinate, the primary-display assumption
            // `frame.minY == 0` drops every real status-item window. Keep the
            // layout path aligned with the scanner's display-aware geometry
            // check, while still retaining offscreen hidden-section windows.
            // AppKit's macOS 26 hosted status windows can briefly report a
            // provisional frame that does not pass the global display check;
            // retain only our own layer-25 windows in that case so the IDs
            // published by StatusBarController remain usable during startup.
            guard pid_t(pid) == getpid() || Self.isMenuBarWindowFrame(frame) else { return nil }
            return (CGWindowID(id), pid_t(pid), info[kCGWindowName as String] as? String ?? "", info[kCGWindowOwnerName as String] as? String ?? "", frame)
        }
    }
}
