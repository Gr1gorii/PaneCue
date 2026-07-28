import Foundation
import PaneCueCore

private enum StableFeatureUnavailableError: LocalizedError {
    case experimentalBuildRequired

    var errorDescription: String? {
        "This capability is available only in PaneCue Experimental."
    }
}

@MainActor
final class OpenAIAPIKeyStore {
    var hasKey: Bool { false }
}

@MainActor
final class OpenAIAPIKeySettingsController {
    init(keyStore: OpenAIAPIKeyStore) {}

    func present() throws -> String? {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }
}

@MainActor
final class RealtimeVoiceCommandController {
    enum State: Equatable {
        case idle
        case listening
        case processing
    }

    private(set) var state: State = .idle

    init(
        keyStore: OpenAIAPIKeyStore,
        settings: AIEngineSettingsStore,
        connectivity: ConnectivityMonitor,
        offlinePack: OfflinePackManager
    ) {}

    func startListening() async throws {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    func stopAndRun(
        scenarios: [VoiceScenarioReference],
        processingDidBegin: @MainActor () -> Void,
        executor: @escaping @MainActor @Sendable (
            RealtimeToolCall
        ) async throws -> String
    ) async throws -> String {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    func cancel() {
        state = .idle
    }
}

@MainActor
final class CallVideoPreviewController {
    private(set) var isCapturing = false
    var onUserClose: (() -> Void)?
    var hasScreenRecordingPermission: Bool { false }

    func startCallCapture() async throws -> String {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    func startBrowserVideoCapture() async throws -> String {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    func stopCapture(hidePanel: Bool = true) async {
        isCapturing = false
    }
}

@MainActor
final class AutoModeController {
    private(set) var isEnabled = false

    init(
        windowManager: WindowManager,
        defaults: UserDefaults = .standard,
        shouldPresentSuggestion: @escaping () -> Bool,
        suggestionHandler: @escaping (AutoModeSuggestion) -> Void,
        enabledDidChange: @escaping (Bool) -> Void
    ) {}

    func start() {}

    func setEnabled(_ enabled: Bool) {
        isEnabled = false
    }

    func toggle() {}
    func dismiss(_ suggestion: AutoModeSuggestion) {}
    func markApplied(_ suggestion: AutoModeSuggestion) {}
    func pauseSuggestions(for seconds: TimeInterval) {}
    func workspaceMayHaveChanged() {}
    func resetPersonalization() {}
}

@MainActor
final class AutoModeSuggestionPanelController {
    var isVisible: Bool { false }

    func show(
        suggestion: AutoModeSuggestion,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {}

    func hide() {}
}
