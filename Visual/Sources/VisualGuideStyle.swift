import Foundation

public enum VisualGuideStyle: String, CaseIterable, Identifiable, Sendable {
    case minimal
    case dynamic
    case liveView

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .minimal:
            return "Minimal"
        case .dynamic:
            return "Dynamic"
        case .liveView:
            return "Live View"
        }
    }
}
