import Foundation

struct DisplayConstraintCandidate: Equatable {
    let id: UInt32
    let availableMenuWidth: Double?
}

enum DisplayConstraint {
    static func minimumAvailableWidth(
        from displays: [DisplayConstraintCandidate]
    ) -> Double? {
        displays.compactMap(\.availableMenuWidth).min()
    }
}
