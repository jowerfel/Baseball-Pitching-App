import Foundation

enum PitchingHand: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case right
    case left

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .right:
            return "Righty"
        case .left:
            return "Lefty"
        }
    }
}
