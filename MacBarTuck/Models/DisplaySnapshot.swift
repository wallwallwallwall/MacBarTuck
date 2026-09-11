import CoreGraphics

struct DisplaySnapshot: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    let frame: CGRect
    let pixelSize: CGSize
    let hasNotch: Bool
    let availableMenuWidth: Double?

    var roleLabel: String {
        let language = AppLanguageController.shared
        return isMain ? language.text("permissions.display.main") : language.text("permissions.display.extended")
    }

    var resolutionLabel: String {
        "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
    }

    func displayName(for language: AppLanguageController) -> String {
        isBuiltIn ? language.text("permissions.display.builtin") : name
    }

    var constraintCandidate: DisplayConstraintCandidate {
        DisplayConstraintCandidate(id: id, availableMenuWidth: availableMenuWidth)
    }
}
