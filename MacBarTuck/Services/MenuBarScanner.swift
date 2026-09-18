import AppKit
import ApplicationServices

/// Reads menu-bar status windows from WindowServer without blocking on
/// per-process Accessibility IPC.
final class MenuBarScanner {
    private var ownedStatusWindowIDs: Set<CGWindowID> = []
    private let readWindows: () -> [[String: Any]]
    private let readDisplayBounds: () -> [CGRect]
    private let ownBundleIdentifier: String?
    private let applicationResolver: MenuBarApplicationIdentityResolver
    private let platformPolicy: MenuBarPlatformPolicy
    private let sessionIdentity = UUID().uuidString
    private var knownMirrorPairs: [CGWindowID: Set<CGWindowID>] = [:]

    init(
        readWindows: @escaping () -> [[String: Any]] = MenuBarWindowServer.windowInfo,
        readDisplayBounds: @escaping () -> [CGRect] = MenuBarScanner.activeDisplayBounds,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        applicationResolver: MenuBarApplicationIdentityResolver = MenuBarApplicationIdentityResolver(),
        platformPolicy: MenuBarPlatformPolicy = .current
    ) {
        self.readWindows = readWindows
        self.readDisplayBounds = readDisplayBounds
        self.ownBundleIdentifier = ownBundleIdentifier
        self.applicationResolver = applicationResolver
        self.platformPolicy = platformPolicy
    }

    func setOwnedStatusWindowIDs(_ windowIDs: Set<CGWindowID>) {
        ownedStatusWindowIDs = windowIDs
    }

    func scan(selectedIDs: Set<String>) -> [MenuBarItem] {
        let windowItems = scanWindowBackedItems(selectedIDs: selectedIDs)
        // Sequoia exposes a number of third-party status items through the
        // owning application's Accessibility menu bar instead of publishing
        // a complete, draggable layer-25 window. macOS 26 needs the bounded
        // WindowServer path above for Control Center-hosted items, while
        // macOS 15 needs this AX enrichment/discovery path for older status
        // item implementations.
        // macOS 27 no longer guarantees one WindowServer window per status
        // item. Prefer the per-item AX tree there; the old layer-25 list can
        // otherwise collapse into one composite menu-bar host.
        switch platformPolicy.discovery {
        case .accessibilityPreferred:
            guard AXIsProcessTrusted() else { return windowItems }
            let discovered = scanAccessibilityItems(
                [],
                selectedIDs: selectedIDs,
                allowsUnmatchedRegularItems: true
            )
            return discovered.contains(where: { $0.axElement != nil }) ? discovered : windowItems
        case .windowServerOnly:
            return windowItems
        case .windowServerWithAccessibility:
            guard AXIsProcessTrusted() else { return windowItems }
            return scanAccessibilityItems(windowItems, selectedIDs: selectedIDs)
        }
    }

    func invalidateApplicationIdentityCache() { applicationResolver.invalidate() }

    private func scanAccessibilityItems(
        _ initialResults: [MenuBarItem],
        selectedIDs: Set<String>,
        allowsUnmatchedRegularItems: Bool = false
    ) -> [MenuBarItem] {
        var results = initialResults
        let ownBundleID = ownBundleIdentifier
        let displays = displayBounds()
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, bundleID != ownBundleID else { continue }
            let identity = applicationResolver.resolve(bundleIdentifier: bundleID)
            let resolvedBundleID = identity?.bundleIdentifier ?? bundleID
            let application = AXUIElementCreateApplication(app.processIdentifier)
            // AX calls can block while a login item is rebuilding its menu.
            // The old unbounded traversal was the reason this path was
            // removed; keep the macOS 15 compatibility path bounded.
            AXUIElementSetMessagingTimeout(application, 0.25)
            guard let contents = accessibilityMenuBarContents(for: application) else { continue }
            for (occurrence, child) in contents.children.enumerated() {
                guard let frame = frame(of: child), frame.width > 5, frame.height > 5,
                      isOnRightSide(frame) || isHiddenMenuBarFrame(frame) else { continue }
                let rawTitle = stringAttribute(child, kAXTitleAttribute as CFString)
                let rawDescription = stringAttribute(child, kAXDescriptionAttribute as CFString)
                let role = stringAttribute(child, kAXRoleAttribute as CFString)
                let subrole = stringAttribute(child, kAXSubroleAttribute as CFString)
                guard !Self.isOpaqueAccessibilityHost(
                    rawTitle: rawTitle,
                    rawDescription: rawDescription,
                    role: role,
                    subrole: subrole,
                    bundleIdentifier: bundleID
                ) else { continue }
                let title = Self.accessibilityItemTitle(
                    rawTitle: rawTitle,
                    rawDescription: rawDescription,
                    applicationName: identity?.displayName ?? app.localizedName,
                    bundleIdentifier: bundleID
                )
                let matchingIndex = results.firstIndex { existing in
                    Self.accessibilityItemMatches(
                        existingOwnerPID: existing.ownerPID,
                        existingHasAccessibilityElement: existing.axElement != nil,
                        existingFrame: existing.frame,
                        existingTitle: existing.title,
                        candidateOwnerPID: app.processIdentifier,
                        candidateFrame: frame,
                        candidateTitle: title
                    )
                }
                let isProtected = MenuBarSystemItemClassifier.isProtected(title, owner: bundleID)
                // A regular application's AX menu bar also contains File/Edit
                // style menus. Only admit unmatched elements from accessory
                // apps; regular apps may still enrich a matching status item.
                guard matchingIndex != nil || allowsUnmatchedRegularItems ||
                    app.activationPolicy != .regular else { continue }
                if title.isEmpty || Self.isOwnedStatusTitle(title) ||
                    (!isProtected && Self.isLikelyApplicationMenu(
                        attributeName: contents.attributeName,
                        title: title,
                        frame: frame
                    )) {
                    if let matchingIndex, !results[matchingIndex].isProtectedSystemItem {
                        results.remove(at: matchingIndex)
                    }
                    continue
                }
                let supportsPress = actionNames(child).contains(kAXPressAction as String)
                if let matchingIndex {
                    let existing = results[matchingIndex]
                    existing.axElement = child
                    existing.supportsPressAction = supportsPress
                    existing.ownerPID = app.processIdentifier
                    existing.sourceDisplayBounds = displays.first { $0.intersects(frame) }
                    if existing.isProtectedSystemItem { continue }
                    existing.title = title
                    existing.ownerName = identity?.displayName ?? app.localizedName ?? bundleID
                    existing.bundleIdentifier = identity?.bundleIdentifier ?? bundleID
                    existing.menuBarHostBundleIdentifier = bundleID
                    if MenuBarSystemItemClassifier.isInputSourceAgent(title, owner: bundleID) {
                        existing.resolvedTitle = "Input Source"
                        existing.resolvedApplicationIcon = nil
                    } else {
                        existing.resolvedApplicationIcon = identity?.icon
                    }
                    continue
                }
                let id = Self.accessibilityItemIdentifier(
                    bundleIdentifier: resolvedBundleID,
                    title: title,
                    occurrence: occurrence,
                    isProtected: isProtected
                )
                let legacyIDs = Self.accessibilityLegacyIdentifiers(
                    sourceBundleIdentifier: bundleID,
                    resolvedBundleIdentifier: resolvedBundleID,
                    title: title
                ).subtracting([id])
                let item = MenuBarItem(
                    id: id,
                    title: isProtected ? MenuBarSystemItemClassifier.canonicalName(title, owner: bundleID) : title,
                    ownerName: isProtected ? "System Menu Bar" : (identity?.displayName ?? app.localizedName ?? bundleID),
                    bundleIdentifier: resolvedBundleID,
                    frame: frame,
                    axElement: child,
                    applicationIcon: MenuBarSystemItemClassifier.prefersCapturedMenuBarIcon(title, bundleIdentifier: bundleID)
                        ? nil
                        : (identity?.icon ?? app.icon),
                    isSelected: !isProtected && (selectedIDs.contains(id) || !selectedIDs.isDisjoint(with: legacyIDs)),
                    supportsPressAction: supportsPress,
                    ownerPID: app.processIdentifier,
                    isProtectedSystemItem: isProtected,
                    menuBarHostBundleIdentifier: bundleID
                )
                item.sourceDisplayBounds = displays.first { $0.intersects(frame) }
                item.legacyIDs = legacyIDs
                item.resolvedTitle = MenuBarSystemItemClassifier.isInputSourceAgent(title, owner: bundleID)
                    ? "Input Source"
                    : nil
                results.append(item)
            }
        }
        return results.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// macOS 26 exposes most menu bar controls as Control Center-owned windows.
    /// This public window-list fallback discovers those controls even when the
    /// originating app does not publish an Accessibility menu-bar element.
    private func scanWindowBackedItems(selectedIDs: Set<String>) -> [MenuBarItem] {
        // Hidden-section items are deliberately moved offscreen. They must
        // remain in the settings and overflow panel when either is refreshed.
        let windows = readWindows()
        let candidates: [(identifier: Int, ownerPID: Int, title: String, owner: String, ownerKey: String, hostBundleIdentifier: String?, appIcon: NSImage?, frame: CGRect)] = windows.compactMap { window in
            guard MenuBarWindowServer.isStatusItemLayer(window),
                  let bounds = MenuBarWindowServer.bounds(in: window),
                  let identifier = MenuBarWindowServer.integer(kCGWindowNumber as String, in: window),
                  identifier > 0, identifier <= Int(CGWindowID.max),
                  let ownerPID = MenuBarWindowServer.integer(kCGWindowOwnerPID as String, in: window) else { return nil }
            guard ownerPID != Int(getpid()), !ownedStatusWindowIDs.contains(CGWindowID(identifier)) else { return nil }
            let title = (window[kCGWindowName as String] as? String) ?? "Menu Bar Item"
            guard !Self.isOwnedStatusTitle(title), title != ownBundleIdentifier else { return nil }
            let owner = (window[kCGWindowOwnerName as String] as? String) ?? "System Menu Bar"
            let runningApp = NSRunningApplication(processIdentifier: pid_t(ownerPID))
            // macOS can report the same Control Center status item with either
            // the localized owner name or its bundle identifier. Keep one
            // stable key so selections survive WindowServer refreshes.
            let rawOwnerKey = runningApp?.bundleIdentifier ?? owner
            let runningIdentity = runningApp?.bundleIdentifier.flatMap {
                applicationResolver.resolve(bundleIdentifier: $0)
            }
            let ownerKey = rawOwnerKey == "com.apple.controlcenter" || owner == "Control Center"
                ? "Control Center"
                : rawOwnerKey
            // Control Center's generic application icon is a white rounded
            // square, not the status item's icon. Keep it out of the panel so
            // the item-specific capture/fallback symbol can be used instead.
            let applicationIcon = ownerKey == "Control Center" ? nil : (runningIdentity?.icon ?? runningApp?.icon)
            let displayOwner = ownerKey == "Control Center" ? owner : (runningIdentity?.displayName ?? owner)
            let frame = bounds
            guard isMenuBarWindowFrame(frame), frame.width > 4, frame.height > 4, frame.height <= 40 else { return nil }
            let hostBundleIdentifier = runningApp?.bundleIdentifier ??
                (Self.looksLikeBundleIdentifier(title) ? title : nil)
            return (identifier, ownerPID, title, displayOwner, ownerKey,
                    hostBundleIdentifier, applicationIcon, frame)
        }
        var occurrences: [String: Int] = [:]
        var legacyOccurrences: [String: Int] = [:]
        let items = candidates.sorted {
            $0.frame.minX == $1.frame.minX ? $0.identifier < $1.identifier : $0.frame.minX > $1.frame.minX
        }.map { candidate in
            let occurrenceKey = "\(candidate.ownerKey)|\(candidate.title)"
            let occurrence = occurrences[occurrenceKey, default: 0]
            occurrences[occurrenceKey] = occurrence + 1
            let legacyOccurrence = legacyOccurrences[candidate.title, default: 0]
            legacyOccurrences[candidate.title] = legacyOccurrence + 1
            let isProtected = MenuBarSystemItemClassifier.isProtected(candidate.title, owner: candidate.ownerKey)
            let title = isProtected ? MenuBarSystemItemClassifier.canonicalName(candidate.title, owner: candidate.ownerKey) : candidate.title
            let id: String
            if isProtected {
                id = "system|\(title)|\(occurrence)"
            } else if Self.isAnonymousTitle(candidate.title) {
                // An anonymous slot can belong to a different app next time.
                // Never carry its positional rule across application launches.
                id = "session|\(sessionIdentity)|\(candidate.identifier)"
            } else {
                id = "window|\(candidate.ownerKey)|\(candidate.title)|\(occurrence)"
            }
            let alternateOwnerKey = candidate.ownerKey == "Control Center" ? "com.apple.controlcenter" : candidate.ownerKey
            let alternateID = "window|\(alternateOwnerKey)|\(candidate.title)|\(occurrence)"
            let legacyID = "window|\(candidate.title)|\(legacyOccurrence)"
            let isSelected = selectedIDs.contains(id) || selectedIDs.contains(alternateID) || selectedIDs.contains(legacyID) || (isProtected && isHiddenMenuBarFrame(candidate.frame))
            let displayTitle = candidate.title == "Item-0" ? "Menu Bar Item" : title
            return MenuBarItem(id: id, title: displayTitle, ownerName: isProtected ? "System Menu Bar" : candidate.owner, bundleIdentifier: candidate.ownerKey, frame: candidate.frame, axElement: nil, applicationIcon: candidate.appIcon, isSelected: isSelected, supportsPressAction: false, windowID: CGWindowID(candidate.identifier), ownerPID: pid_t(candidate.ownerPID), isProtectedSystemItem: isProtected, menuBarHostBundleIdentifier: candidate.hostBundleIdentifier)
        }
        return resolveMirrors(items, windows: windows)
    }

    private struct MirrorAnchor {
        let frame: CGRect
        let display: CGRect
    }

    private func resolveMirrors(_ items: [MenuBarItem], windows: [[String: Any]]) -> [MenuBarItem] {
        let displays = displayBounds()
        let controlWidth = windows.first {
            ($0[kCGWindowName as String] as? String) == "BarTuckControlItem"
        }.flatMap(MenuBarWindowServer.bounds)?.width
        let anchors: [MirrorAnchor] = windows.compactMap { info in
            guard let controlWidth,
                  MenuBarWindowServer.isStatusItemLayer(info),
                  let title = info[kCGWindowName as String] as? String,
                  title == "BarTuckControlItem" || title == ownBundleIdentifier,
                  let frame = MenuBarWindowServer.bounds(in: info),
                  abs(frame.width - controlWidth) <= 1,
                  let display = displays.first(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }),
                  abs(frame.minY - display.minY) <= 4 else { return nil }
            return MirrorAnchor(frame: frame, display: display)
        }
        func anchor(for item: MenuBarItem) -> MirrorAnchor? {
            let matches = anchors.filter {
                abs($0.frame.minY - item.frame.minY) <= 1 && abs($0.frame.height - item.frame.height) <= 1
            }
            if matches.count == 1 { return matches[0] }
            let visibleMatches = matches.filter { $0.display.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) }
            return visibleMatches.count == 1 ? visibleMatches[0] : nil
        }
        for item in items { item.sourceDisplayBounds = anchor(for: item)?.display }
        var remaining = items
        var result: [MenuBarItem] = []
        while let item = remaining.first {
            remaining.removeFirst()
            var members = [item]
            if let windowID = item.windowID, let pairedIDs = knownMirrorPairs[windowID] {
                let known = remaining.filter { candidate in
                    guard let otherID = candidate.windowID, pairedIDs.contains(otherID), candidate.ownerPID == item.ownerPID,
                          abs(candidate.frame.width - item.frame.width) <= 1 else { return false }
                    return Self.isAnonymousTitle(item.title) || Self.isAnonymousTitle(candidate.title) || item.title == candidate.title
                }
                members += known
                let ids = Set(known.map(\.id))
                remaining.removeAll { ids.contains($0.id) }
            }
            if members.count == 1, let base = anchor(for: item), items.filter({ candidate in
                guard candidate.ownerPID == item.ownerPID, let other = anchor(for: candidate) else { return false }
                return other.display == base.display && abs(candidate.frame.minX - item.frame.minX) <= 1 && abs(candidate.frame.width - item.frame.width) <= 1
            }).count == 1 {
                let matches = remaining.filter { candidate in
                    guard candidate.ownerPID == item.ownerPID,
                          let other = anchor(for: candidate), other.display != base.display,
                          abs(candidate.frame.width - item.frame.width) <= 1,
                          abs((candidate.frame.minX - other.frame.minX) - (item.frame.minX - base.frame.minX)) <= 1
                    else { return false }
                    return Self.isAnonymousTitle(item.title) || Self.isAnonymousTitle(candidate.title) || item.title == candidate.title
                }
                // A one-to-one slot match is required. Ambiguous same-size
                // windows stay independent; names alone never merge items.
                let displayGroups = Dictionary(grouping: matches, by: { candidate in
                    candidate.sourceDisplayBounds.flatMap { displays.firstIndex(of: $0) } ?? -1
                })
                if displayGroups.values.allSatisfy({ $0.count == 1 }) {
                    members += matches
                    let ids = Set(matches.map(\.id))
                    remaining.removeAll { ids.contains($0.id) }
                }
            }
            let representative = members.sorted {
                let lhs = Self.isAnonymousTitle($0.title) ? 1 : 0
                let rhs = Self.isAnonymousTitle($1.title) ? 1 : 0
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }[0]
            representative.mirrors = members.filter { $0 !== representative }
            if members.count > 1 {
                let windowIDs = Set(members.compactMap(\.windowID))
                for id in windowIDs { knownMirrorPairs[id] = windowIDs.subtracting([id]) }
            }
            representative.legacyIDs = Set(members.filter { !Self.isAnonymousTitle($0.title) }.map(\.id))
            representative.isSelected = members.contains(where: \.isSelected)
            if MenuBarSystemItemClassifier.isInputSourceAgent(representative.title,
                                                              owner: representative.bundleIdentifier) {
                representative.resolvedTitle = "Input Source"
                representative.applicationIcon = nil
                representative.resolvedApplicationIcon = nil
            } else if representative.title.contains("."),
                      let identity = applicationResolver.resolve(bundleIdentifier: representative.title) {
                representative.resolvedTitle = identity.displayName
                representative.bundleIdentifier = identity.bundleIdentifier ?? representative.bundleIdentifier
                representative.resolvedApplicationIcon = identity.icon
            }
            result.append(representative)
        }
        let currentWindowIDs = Set(items.compactMap(\.windowID))
        knownMirrorPairs = knownMirrorPairs.filter { currentWindowIDs.contains($0.key) }
        let sorted = result.sorted { $0.frame.minX == $1.frame.minX ? $0.id < $1.id : $0.frame.minX < $1.frame.minX }
        var unidentified = 0
        for item in sorted where Self.isAnonymousTitle(item.title) {
            unidentified += 1
            item.resolvedTitle = "Unidentified Item \(unidentified)"
        }
        return sorted
    }

    private static func isAnonymousTitle(_ title: String) -> Bool {
        let value = title.replacingOccurrences(of: " ", with: "").lowercased()
        return value.isEmpty || value.hasPrefix("item-") || ["menubaritem", "statusitem", "statusmenu"].contains(value)
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        return components.count >= 3 && components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy {
                $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
            }
        }
    }

    /// A position-independent fingerprint used to notice status-item creation,
    /// removal, and process restarts without treating our own layout moves as
    /// new items.
    func windowSignature() -> Set<String> {
        let windows = readWindows()
        return Set(windows.compactMap { window in
            guard MenuBarWindowServer.isStatusItemLayer(window),
                  let identifier = MenuBarWindowServer.integer(kCGWindowNumber as String, in: window),
                  identifier > 0, identifier <= Int(CGWindowID.max),
                  let ownerPID = MenuBarWindowServer.integer(kCGWindowOwnerPID as String, in: window),
                  ownerPID != Int(getpid()),
                  !ownedStatusWindowIDs.contains(CGWindowID(identifier)),
                  let bounds = MenuBarWindowServer.bounds(in: window) else { return nil }
            let title = (window[kCGWindowName as String] as? String) ?? ""
            guard !Self.isOwnedStatusTitle(title), title != ownBundleIdentifier else { return nil }
            let width = Int(bounds.width.rounded())
            let height = Int(bounds.height.rounded())
            guard width > 4, height > 4, height <= 40 else { return nil }
            return "\(identifier)|\(ownerPID)|\(title)|\(width)x\(height)"
        })
    }

    func refreshAccessibility(for item: MenuBarItem) -> (element: AXUIElement, supportsPress: Bool)? {
        if platformPolicy.discovery == .windowServerOnly {
            return nil
        }
        guard AXIsProcessTrusted() else { return nil }
        let windowItems = scanWindowBackedItems(selectedIDs: [])
        let accessibilityPreferred = platformPolicy.discovery == .accessibilityPreferred
        let seeds = platformPolicy.usesWindowServerAccessibilitySeeds ? windowItems : []
        let candidates = scanAccessibilityItems(
            seeds,
            selectedIDs: [],
            allowsUnmatchedRegularItems: accessibilityPreferred
        )
        let match = candidates.first {
            if let windowID = item.windowID, $0.windowID == windowID { return true }
            return $0.id == item.id
        }
        guard let match, let element = match.axElement else { return nil }
        return (element, match.supportsPressAction)
    }

    private func isHiddenMenuBarFrame(_ frame: CGRect) -> Bool {
        MenuBarGeometry.isHiddenLaneMenuItem(
            frame,
            displayBounds: displayBounds()
        )
    }

    private func isMenuBarWindowFrame(_ frame: CGRect) -> Bool {
        MenuBarGeometry.isMenuBarItem(
            frame,
            displayBounds: displayBounds()
        )
    }

    private func isOnRightSide(_ frame: CGRect) -> Bool {
        Self.isRightSideAccessibilityItem(frame: frame, displayBounds: displayBounds())
    }

    static func accessibilityItemTitle(
        rawTitle: String?, rawDescription: String?, applicationName: String?,
        bundleIdentifier: String
    ) -> String {
        for candidate in [rawTitle, rawDescription, applicationName, bundleIdentifier] {
            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty { return value }
        }
        return "Menu Bar Item"
    }

    static func isRightSideAccessibilityItem(frame: CGRect, displayBounds: [CGRect]) -> Bool {
        guard let display = displayBounds.first(where: { $0.intersects(frame) }) else { return false }
        // AX status icons can be vertically inset inside the menu-bar band.
        // Accept the full 50-point band at either coordinate-system edge.
        let nearQuartzMenuBar = frame.minY >= display.minY - 4 &&
            frame.maxY <= display.minY + 50
        let nearAppKitMenuBar = frame.minY >= display.maxY - 50 &&
            frame.maxY <= display.maxY + 4
        return frame.midX > display.midX && (nearQuartzMenuBar || nearAppKitMenuBar)
    }

    static func isOpaqueAccessibilityHost(
        rawTitle: String?, rawDescription: String?, role: String?, subrole: String?,
        bundleIdentifier: String
    ) -> Bool {
        guard bundleIdentifier == "com.apple.MenuBarAgent",
              role == kAXGroupRole as String,
              subrole == "AXHostingView" else { return false }
        return [rawTitle, rawDescription].allSatisfy {
            ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func isLikelyApplicationMenu(attributeName: String, title: String, frame: CGRect) -> Bool {
        attributeName == kAXMenuBarAttribute as String && (title.count > 18 || frame.width > 150)
    }

    static func accessibilityItemIdentifier(
        bundleIdentifier: String, title: String, occurrence: Int, isProtected: Bool
    ) -> String {
        if isProtected {
            let canonical = MenuBarSystemItemClassifier.canonicalName(title, owner: bundleIdentifier)
            return "system|\(canonical)|\(occurrence)"
        }
        return "ax|\(bundleIdentifier)|\(occurrence)"
    }

    private static func isOwnedStatusTitle(_ title: String) -> Bool {
        title == "BarTuckControlItem" || title.hasPrefix("BarTuckHiddenSection")
    }

    static func accessibilityLegacyIdentifiers(
        sourceBundleIdentifier: String, resolvedBundleIdentifier: String, title: String
    ) -> Set<String> {
        let bundleIdentifiers = Set([sourceBundleIdentifier, resolvedBundleIdentifier])
        let controlCenterOwners = ["Control Center", "控制中心", "com.apple.controlcenter"]
        var identifiers = Set(bundleIdentifiers.map { "\($0)|\(title)" })
        for owner in controlCenterOwners {
            for bundleIdentifier in bundleIdentifiers {
                identifiers.insert("window|\(owner)|\(bundleIdentifier)|0")
            }
        }
        return identifiers
    }

    static func framesRepresentSameItem(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let narrowerWidth = min(lhs.width, rhs.width)
        let widerWidth = max(lhs.width, rhs.width)
        guard narrowerWidth > 0, widerWidth <= narrowerWidth * 1.5 + 4 else { return false }
        let horizontalOverlap = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
        return horizontalOverlap >= min(lhs.width, rhs.width) * 0.5 &&
            abs(lhs.minY - rhs.minY) <= 4
    }

    static func accessibilityItemMatches(
        existingOwnerPID: pid_t?,
        existingHasAccessibilityElement: Bool,
        existingFrame: CGRect,
        existingTitle: String,
        candidateOwnerPID: pid_t,
        candidateFrame: CGRect,
        candidateTitle: String
    ) -> Bool {
        let hasSameOwner = existingOwnerPID == candidateOwnerPID
        if existingHasAccessibilityElement && !hasSameOwner { return false }
        return framesRepresentSameItem(existingFrame, candidateFrame) ||
            (hasSameOwner && existingTitle == candidateTitle)
    }

    static func isDiscreteAccessibilitySeed(frame: CGRect, displayBounds: [CGRect]) -> Bool {
        guard let display = displayBounds.first(where: { $0.intersects(frame) }) else { return false }
        let maximumWidth = min(CGFloat(320), display.width * 0.25)
        return frame.width <= maximumWidth
    }

    private func displayBounds() -> [CGRect] {
        readDisplayBounds()
    }

    static func activeDisplayBounds() -> [CGRect] {
        MenuBarDisplayBounds.current()
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute, &value) == .success ? value as? String : nil
    }

    private func arrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute, &value) == .success ? value as? [AXUIElement] : nil
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func accessibilityMenuBarContents(
        for application: AXUIElement
    ) -> (children: [AXUIElement], attributeName: String)? {
        for attributeName in platformPolicy.accessibilityMenuBarAttributeNames {
            guard let menuBar = elementAttribute(application, attributeName as CFString),
                  let children = arrayAttribute(menuBar, kAXChildrenAttribute as CFString),
                  !children.isEmpty else { continue }
            return (children, attributeName)
        }
        return nil
    }

    private func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let names else { return [] }
        return names as? [String] ?? []
    }

    private func frame(of element: AXUIElement) -> CGRect? {
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

}
