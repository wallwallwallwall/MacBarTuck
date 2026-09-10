import CoreGraphics

struct DisplaySnapshot: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isMain: Bool
    let frame: CGRect
    let pixelSize: CGSize
    let hasNotch: Bool
    let availableMenuWidth: Double?

    var roleLabel: String { isMain ? "主屏" : "扩展屏" }

    var resolutionLabel: String {
        "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
    }

    var constraintCandidate: DisplayConstraintCandidate {
        DisplayConstraintCandidate(id: id, availableMenuWidth: availableMenuWidth)
    }
}
