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

    public var note: String {
        switch self {
        case .minimal:
            return "Current product mode: H5-style monochrome flow with a clean minimal feel."
        case .dynamic:
            return "H5-matched nebula particle starfield with layered clouds, dust, and warp-speed travel."
        case .liveView:
            return "Full-screen camera preview with adaptive edge flow and a stable SDR live camera feed."
        }
    }

    public var statusTitle: String {
        switch self {
        case .minimal:
            return "Ready"
        case .dynamic:
            return "Ready"
        case .liveView:
            return "Ready"
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .minimal:
            return true
        case .dynamic:
            return true
        case .liveView:
            return true
        }
    }

    public var placeholderTitle: String {
        switch self {
        case .minimal:
            return "Minimal is active"
        case .dynamic:
            return "Dynamic starfield is active"
        case .liveView:
            return "Live View is active"
        }
    }

    public var placeholderNote: String {
        switch self {
        case .minimal:
            return "Minimal is the current fully implemented visual session."
        case .dynamic:
            return "Dynamic runs an H5-matched layered starfield with nebula clouds, fine dust, and a dedicated cruise or warp route."
        case .liveView:
            return "This session uses the real camera route with adaptive side flow overlays. When camera access is unavailable, it falls back to a clean permission surface."
        }
    }
}
