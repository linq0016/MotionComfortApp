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
            return "A looped melodic comfort bed from the bundled music asset. Keep the volume low and use it conservatively."
        }
    }

    public var statusTitle: String {
        switch self {
        case .off, .monotone, .melodic:
            return "Ready"
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .off, .monotone, .melodic:
            return true
        }
    }
}
