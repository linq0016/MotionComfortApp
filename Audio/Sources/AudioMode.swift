import Foundation

public enum AudioMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case melodic
    case monotone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off:
            return "Off"
        case .melodic:
            return "Melodic"
        case .monotone:
            return "Mono"
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .off, .monotone, .melodic:
            return true
        }
    }
}
