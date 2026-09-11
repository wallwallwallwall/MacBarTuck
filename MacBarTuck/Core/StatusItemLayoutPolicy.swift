import CoreGraphics

enum StatusItemLayoutPolicy {
    static func separatorLength(enabled: Bool, ready: Bool, hasSelection: Bool,
                                isApplying: Bool, screenWidths: [CGFloat]) -> CGFloat {
        if isApplying { return 20 }
        guard enabled, ready, hasSelection else { return 0 }
        let widest = screenWidths.filter { $0.isFinite && $0 > 0 }.max() ?? 1728
        return min(10_000, max(500, widest * 2))
    }
}
