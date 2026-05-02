import UIKit

@MainActor
enum AppHaptics {
    private static let buttonTapGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func prepareButtonTap() {
        buttonTapGenerator.prepare()
    }

    static func buttonTap() {
        buttonTapGenerator.impactOccurred(intensity: 0.6)
        buttonTapGenerator.prepare()
    }

    static func selectionChanged() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }
}
