import AppKit
import Foundation
import PaneCueCore

private enum StableFeatureUnavailableError: LocalizedError {
    case experimentalBuildRequired

    var errorDescription: String? {
        "This capability is available only in PaneCue Experimental."
    }
}

@MainActor
public final class StablePaneCueFeatureProvider: PaneCueFeatureProvider {
    public init() {}

    public let isExperimental = false
    public let displayName = "PaneCue"
    public let voiceState: PaneCueVoiceState = .idle
    public let isVideoCaptureActive = false
    public let hasAPIKey = false
    public let isAutoModeEnabled = false
    public let isSuggestionVisible = false
    public let hasScreenRecordingPermission = false
    public let diagnostics = PaneCueFeatureDiagnostics(
        profile: "Main",
        processing: "Offline Only",
        screenRecording: "not present in stable profile"
    )

    public func configure(context: PaneCueFeatureProviderContext) {}
    public func start() {}
    public func installStatusMenuItems(in menu: NSMenu) {}
    public func refreshStatusMenuItems() {}
    public func processingModeDidChange(_ mode: AIProcessingMode) {}
    public func connectivityDidChange(isOnline: Bool) {}

    public func configureAPIKey() throws -> String? {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    public func requestScreenRecordingAccess() -> String {
        "Screen Recording is not included in this build."
    }

    public func startVoiceListening() async throws {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    public func stopVoiceAndRun(
        scenarios: [VoiceScenarioReference],
        processingDidBegin: @MainActor () -> Void,
        executor: @escaping @MainActor @Sendable (
            RealtimeToolCall
        ) async throws -> String
    ) async throws -> String {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    public func cancelVoice() {}

    public func startCallCapture() async throws -> String {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    public func startBrowserVideoCapture() async throws -> String {
        throw StableFeatureUnavailableError.experimentalBuildRequired
    }

    public func stopVideoCapture() async {}
    public func setAutoModeEnabled(_ enabled: Bool) {}
    public func toggleAutoMode() {}

    public func presentAutoModeSuggestion(
        _ suggestion: AutoModeSuggestion,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {}

    public func hideAutoModeSuggestion() {}
    public func pauseAutoMode(for seconds: TimeInterval) {}
    public func autoModeWorkspaceMayHaveChanged() {}
    public func resetAutoModePersonalization() {}
    public func shutdown() async {}
}
