import AppKit
import Foundation
import PaneCueCore

public enum PaneCueVoiceState: Equatable, Sendable {
    case idle
    case listening
    case processing
}

public struct PaneCueFeatureDiagnostics: Equatable, Sendable {
    public let profile: String
    public let processing: String
    public let screenRecording: String

    public init(
        profile: String,
        processing: String,
        screenRecording: String
    ) {
        self.profile = profile
        self.processing = processing
        self.screenRecording = screenRecording
    }
}

@MainActor
public struct PaneCueFeatureProviderContext {
    public let aiSettings: AIEngineSettingsStore
    public let connectivity: ConnectivityMonitor
    public let windowManager: WindowManager
    public let shouldPresentSuggestion: () -> Bool
    public let suggestionHandler: (AutoModeSuggestion) -> Void
    public let stateDidChange: (String?) -> Void
    public let runFeatureAction: (VoiceCommandAction) -> Void
    public let toggleVoiceCommand: () -> Void
    public let configureCloudAccess: () -> Void

    public init(
        aiSettings: AIEngineSettingsStore,
        connectivity: ConnectivityMonitor,
        windowManager: WindowManager,
        shouldPresentSuggestion: @escaping () -> Bool,
        suggestionHandler: @escaping (AutoModeSuggestion) -> Void,
        stateDidChange: @escaping (String?) -> Void,
        runFeatureAction: @escaping (VoiceCommandAction) -> Void,
        toggleVoiceCommand: @escaping () -> Void,
        configureCloudAccess: @escaping () -> Void
    ) {
        self.aiSettings = aiSettings
        self.connectivity = connectivity
        self.windowManager = windowManager
        self.shouldPresentSuggestion = shouldPresentSuggestion
        self.suggestionHandler = suggestionHandler
        self.stateDidChange = stateDidChange
        self.runFeatureAction = runFeatureAction
        self.toggleVoiceCommand = toggleVoiceCommand
        self.configureCloudAccess = configureCloudAccess
    }
}

@MainActor
public protocol PaneCueFeatureProvider: AnyObject {
    var isExperimental: Bool { get }
    var displayName: String { get }
    var voiceState: PaneCueVoiceState { get }
    var isVideoCaptureActive: Bool { get }
    var hasAPIKey: Bool { get }
    var isAutoModeEnabled: Bool { get }
    var isSuggestionVisible: Bool { get }
    var hasScreenRecordingPermission: Bool { get }
    var diagnostics: PaneCueFeatureDiagnostics { get }

    func configure(context: PaneCueFeatureProviderContext)
    func start()
    func installStatusMenuItems(in menu: NSMenu)
    func refreshStatusMenuItems()
    func processingModeDidChange(_ mode: AIProcessingMode)
    func connectivityDidChange(isOnline: Bool)
    func configureAPIKey() throws -> String?
    func requestScreenRecordingAccess() -> String
    func startVoiceListening() async throws
    func stopVoiceAndRun(
        scenarios: [VoiceScenarioReference],
        processingDidBegin: @MainActor () -> Void,
        executor: @escaping @MainActor @Sendable (
            RealtimeToolCall
        ) async throws -> String
    ) async throws -> String
    func cancelVoice()
    func startCallCapture() async throws -> String
    func startBrowserVideoCapture() async throws -> String
    func stopVideoCapture() async
    func setAutoModeEnabled(_ enabled: Bool)
    func toggleAutoMode()
    func presentAutoModeSuggestion(
        _ suggestion: AutoModeSuggestion,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    )
    func hideAutoModeSuggestion()
    func pauseAutoMode(for seconds: TimeInterval)
    func autoModeWorkspaceMayHaveChanged()
    func resetAutoModePersonalization()
    func shutdown() async
}
