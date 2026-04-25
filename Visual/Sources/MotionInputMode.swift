import Foundation

public enum MotionInputMode: String, CaseIterable, Identifiable, Sendable {
    case realTime

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .realTime:
            return "Real-time Motion"
        }
    }

    public var note: String {
        switch self {
        case .realTime:
            return "Read live 3-axis userAcceleration from deviceMotion."
        }
    }
}
