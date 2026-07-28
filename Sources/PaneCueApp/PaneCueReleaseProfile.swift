import Foundation

enum PaneCueReleaseProfile: String {
    case main = "Main"
    case experimental = "Experimental"

    static let current: PaneCueReleaseProfile = {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "PaneCueReleaseProfile"
        ) as? String else {
            return .main
        }
        return PaneCueReleaseProfile(rawValue: value) ?? .main
    }()

    var isExperimental: Bool {
        self == .experimental
    }

    var displayName: String {
        switch self {
        case .main:
            return "PaneCue"
        case .experimental:
            return "PaneCue Experimental"
        }
    }
}
