import CoreGraphics

struct NativeOverflowSpacerPlan: Equatable {
    let itemLength: CGFloat
    let itemCount: Int

    var totalLength: CGFloat { itemLength * CGFloat(itemCount) }
}

struct NativeOverflowSpacerPresentation: Equatable {
    let alphaValue: CGFloat
    let isEnabled: Bool
    let appearsDisabled: Bool
}

struct NativeOverflowLayoutMove: Equatable {
    let sourceID: String
    let targetID: String
}

enum NativeOverflowMoveVerificationDecision: Equatable {
    case retry(nextCheck: Int, consecutiveMatches: Int)
    case succeeded
    case failed
}

enum NativeOverflowMoveVerificationPolicy {
    static let maximumChecks = 8
    static let requiredConsecutiveMatches = 2
    static let adjacencyTolerance: CGFloat = 5

    static func decision(
        source: CGRect?,
        target: CGRect?,
        check: Int,
        consecutiveMatches: Int
    ) -> NativeOverflowMoveVerificationDecision {
        let adjacent: Bool
        if let source, let target,
           source.width > 0, source.height > 0,
           target.width > 0, target.height > 0,
           source.minX.isFinite, source.maxX.isFinite,
           target.minX.isFinite, target.maxX.isFinite {
            adjacent = source.minX < target.minX &&
                abs(source.maxX - target.minX) <= adjacencyTolerance
        } else {
            adjacent = false
        }

        let stableMatches = adjacent ? consecutiveMatches + 1 : 0
        if stableMatches >= requiredConsecutiveMatches {
            return .succeeded
        }
        let nextCheck = check + 1
        guard nextCheck < maximumChecks else { return .failed }
        return .retry(
            nextCheck: nextCheck,
            consecutiveMatches: stableMatches
        )
    }
}

enum StatusItemLayoutPolicy {
    static let compactSeparatorLength: CGFloat = 20

    static func hiddenSectionItemCount(usesHiddenSection: Bool) -> Int {
        usesHiddenSection ? 1 : 0
    }

    static func nativeOverflowSpacerPresentation(
        isApplyingLayout: Bool,
        length: CGFloat
    ) -> NativeOverflowSpacerPresentation {
        let acceptsLayoutDrops = isApplyingLayout && length > 0
        return NativeOverflowSpacerPresentation(
            alphaValue: 0,
            isEnabled: acceptsLayoutDrops,
            appearsDisabled: !acceptsLayoutDrops
        )
    }

    static func separatorLength(enabled: Bool, ready: Bool, hasSelection: Bool,
                                isApplying: Bool, screenWidths: [CGFloat]) -> CGFloat {
        if isApplying { return compactSeparatorLength }
        guard enabled, ready, hasSelection else { return 0 }
        let widest = screenWidths.filter { $0.isFinite && $0 > 0 }.max() ?? 1728
        return min(10_000, max(500, widest * 2))
    }

    static func statusRegionWidth(
        screenWidth: CGFloat,
        auxiliaryTopRightWidth: CGFloat?
    ) -> CGFloat {
        let validScreenWidth = screenWidth.isFinite && screenWidth > 0
            ? screenWidth
            : 1728
        if let auxiliaryTopRightWidth,
           auxiliaryTopRightWidth.isFinite,
           auxiliaryTopRightWidth > 0 {
            return min(validScreenWidth, auxiliaryTopRightWidth)
        }
        return validScreenWidth * 0.5
    }

    static func nativeOverflowSpacerPlan(
        screenWidths: [CGFloat],
        statusRegionWidths: [CGFloat] = []
    ) -> NativeOverflowSpacerPlan {
        let validScreenWidths = screenWidths.filter { $0.isFinite && $0 > 0 }
        let widths = validScreenWidths.isEmpty ? [CGFloat(1728)] : validScreenWidths
        let narrowest = widths.min() ?? 1728
        let widest = widths.max() ?? narrowest
        // macOS 27 drops one hosted status item when it reaches half of the
        // narrowest display. Stay below that per-item threshold and combine
        // multiple spacers when a wider display needs more pressure.
        let itemLength = floor(max(320, narrowest * 0.45))
        let validRegionWidths = statusRegionWidths.filter { $0.isFinite && $0 > 0 }
        let requiredWidth = max(validRegionWidths.max() ?? 0, widest * 0.5)
        let itemCount = min(12, max(1, Int(ceil(requiredWidth / itemLength))))
        return NativeOverflowSpacerPlan(
            itemLength: itemLength,
            itemCount: itemCount
        )
    }
}

enum NativeOverflowLayoutPolicy {
    static func movePlan(
        currentOrder: [String],
        desiredOrder: [String]
    ) -> [NativeOverflowLayoutMove] {
        guard currentOrder.count == Set(currentOrder).count,
              desiredOrder.count == Set(desiredOrder).count,
              Set(currentOrder) == Set(desiredOrder),
              let last = desiredOrder.last else { return [] }

        var working = currentOrder
        var targetID = last
        var moves = [NativeOverflowLayoutMove]()

        for sourceID in desiredOrder.dropLast().reversed() {
            guard let sourceIndex = working.firstIndex(of: sourceID),
                  let targetIndex = working.firstIndex(of: targetID) else { return [] }
            if sourceIndex + 1 != targetIndex {
                working.remove(at: sourceIndex)
                guard let refreshedTargetIndex = working.firstIndex(of: targetID) else { return [] }
                working.insert(sourceID, at: refreshedTargetIndex)
                moves.append(.init(sourceID: sourceID, targetID: targetID))
            }
            targetID = sourceID
        }

        return working == desiredOrder ? moves : []
    }

    static func applying(
        _ moves: [NativeOverflowLayoutMove],
        to order: [String]
    ) -> [String]? {
        guard order.count == Set(order).count else { return nil }
        var result = order
        for move in moves {
            guard move.sourceID != move.targetID,
                  let sourceIndex = result.firstIndex(of: move.sourceID) else { return nil }
            result.remove(at: sourceIndex)
            guard let targetIndex = result.firstIndex(of: move.targetID) else { return nil }
            result.insert(move.sourceID, at: targetIndex)
        }
        return result
    }
}
