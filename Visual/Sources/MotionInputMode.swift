import Foundation

public enum MotionInputMode: String, CaseIterable, Identifiable, Sendable {
    case realTime
    case demo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .realTime:
            return "Real-time Motion"
        case .demo:
            return "Demo Motion"
        }
    }

    public var note: String {
        switch self {
        case .realTime:
            return "Read live 3-axis userAcceleration from deviceMotion."
        case .demo:
            return "Use the built-in simulated motion loop for demos and tuning."
        }
    }
}
