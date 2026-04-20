import Foundation

public enum VisualGuideStyle: String, CaseIterable, Identifiable, Sendable {
    case minimal
    case dynamic
    case liveView

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .minimal:
            return String(localized: "visual_mode.minimal")
        case .dynamic:
            return String(localized: "visual_mode.dynamic")
        case .liveView:
            return String(localized: "visual_mode.live_view")
        }
    }
}
