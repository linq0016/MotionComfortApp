import Foundation

public enum AudioMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case monotone
    case melodic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off:
            return "Off"
        case .monotone:
            return "Monotone"
        case .melodic:
            return "Melodic"
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .off, .monotone, .melodic:
            return true
        }
    }
}
