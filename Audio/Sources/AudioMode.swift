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

    public var note: String {
        switch self {
        case .off:
            return "No audio guidance."
        case .monotone:
            return "A continuous 100 Hz signal path. Keep the volume low and use it conservatively."
        case .melodic:
            return "Placeholder for a future music-like comfort mode."
        }
    }

    public var statusTitle: String {
        switch self {
        case .off, .monotone:
            return "Ready"
        case .melodic:
            return "Soon"
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .off, .monotone:
            return true
        case .melodic:
            return false
        }
    }
}
