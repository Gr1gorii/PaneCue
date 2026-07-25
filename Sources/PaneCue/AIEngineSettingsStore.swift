import Combine
import Foundation
import PaneCueCore

@MainActor
final class AIEngineSettingsStore: ObservableObject {
    @Published var processingMode: AIProcessingMode {
        didSet {
            defaults.set(
                processingMode.rawValue,
                forKey: Keys.processingMode
            )
            modeDidChange?(processingMode)
        }
    }

    @Published var localCommandModel: LocalCommandModel {
        didSet {
            defaults.set(
                localCommandModel.rawValue,
                forKey: Keys.localCommandModel
            )
        }
    }

    var modeDidChange: ((AIProcessingMode) -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        processingMode = AIProcessingMode(
            rawValue: defaults.string(forKey: Keys.processingMode) ?? ""
        ) ?? .automatic
        localCommandModel = LocalCommandModel(
            rawValue: defaults.string(forKey: Keys.localCommandModel) ?? ""
        ) ?? .smart
    }

    private enum Keys {
        static let processingMode = "PaneCue.AIProcessingMode"
        static let localCommandModel = "PaneCue.LocalCommandModel"
    }
}

extension AIProcessingMode {
    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .offline:
            return "Offline Only"
        case .cloud:
            return "Cloud Only"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Cloud while online, local models without internet"
        case .offline:
            return "Audio and commands stay entirely on this Mac"
        case .cloud:
            return "Use OpenAI and keep local models out of memory"
        }
    }
}

extension LocalCommandModel {
    var displayName: String {
        switch self {
        case .smart:
            return "PaneCue Mini"
        case .functionGemma:
            return "FunctionGemma"
        case .qwen:
            return "PaneCue Qwen"
        }
    }

    var detail: String {
        switch self {
        case .smart:
            return "499,975 parameters • ~500 KB • negligible memory use"
        case .functionGemma:
            return "Optional experiment • about 320 MB while active"
        case .qwen:
            return "Optional fallback • about 1.9 GB while active"
        }
    }
}
