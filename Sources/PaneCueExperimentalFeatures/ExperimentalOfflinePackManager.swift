import Combine
import Foundation
import PaneCueApp
import PaneCueCore

@MainActor
final class ExperimentalOfflinePackManager: ObservableObject {
    enum State: Equatable {
        case checking
        case runtimeUnavailable
        case notInstalled
        case downloading(String)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .checking

    let service = OllamaLocalCommandService()
    private let miniService = PaneCueMiniCommandService()

    var isReady: Bool {
        state == .ready
    }

    var isBusy: Bool {
        if case .downloading = state {
            return true
        }
        return state == .checking
    }

    var statusText: String {
        switch state {
        case .checking:
            return "Checking the built-in local model…"
        case .runtimeUnavailable:
            return "PaneCue Mini is not included in this build"
        case .notInstalled:
            return "PaneCue Mini needs to be restored"
        case let .downloading(model):
            return "Downloading \(model)…"
        case .ready:
            return "PaneCue Mini v2 is built in • about 500 KB"
        case let .failed(message):
            return message
        }
    }

    init() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        state = .checking
        guard await miniService.isAvailable else {
            state = .runtimeUnavailable
            return
        }
        state = .ready
    }

    func prepare() {
        guard !isBusy else {
            return
        }

        Task {
            await refresh()
        }
    }

    func commandIntent(
        transcript: String,
        scenarios: [VoiceScenarioReference],
        model: LocalCommandModel
    ) async throws -> VoiceCommandIntent {
        if model == .smart {
            return try await miniService.intent(
                transcript: transcript,
                scenarios: scenarios
            )
        }
        return try await service.intent(
            transcript: transcript,
            scenarios: scenarios,
            selection: model
        )
    }

    func unloadModels() {
        Task {
            await miniService.unload()
            await service.unloadRunningModels()
        }
    }

    func shutdown() async {
        await miniService.unload()
        await service.shutdown()
    }
}
