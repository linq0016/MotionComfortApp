import Foundation

public enum AudioMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case melodic
    case monotone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off:
            return String(localized: "audio_mode.off")
        case .melodic:
            return String(localized: "audio_mode.melodic")
        case .monotone:
            return String(localized: "audio_mode.mono")
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .off, .monotone, .melodic:
            return true
        }
    }
}
