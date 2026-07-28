import CoreGraphics
import Foundation
import PaneCueApp
import PaneCueCore

private enum ExperimentalFeatureProviderError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        "PaneCue Experimental is still starting. Try again in a moment."
    }
}

@MainActor
public final class ExperimentalPaneCueFeatureProvider:
    PaneCueFeatureProvider
{
    private let keyStore = OpenAIAPIKeyStore()
    private lazy var keySettings = OpenAIAPIKeySettingsController(
        keyStore: keyStore
    )
    private let offlinePack = ExperimentalOfflinePackManager()
    private let callVideoPreview = CallVideoPreviewController()
    private let suggestionPanel = AutoModeSuggestionPanelController()

    private var context: PaneCueFeatureProviderContext?
    private var voiceCommand: RealtimeVoiceCommandController?
    private var autoMode: AutoModeController?
    private var didShutdown = false

    public init() {}

    public let isExperimental = true
    public let displayName = "PaneCue Experimental"

    public var voiceState: PaneCueVoiceState {
        switch voiceCommand?.state ?? .idle {
        case .idle: return .idle
        case .listening: return .listening
        case .processing: return .processing
        }
    }

    public var isVideoCaptureActive: Bool {
        callVideoPreview.isCapturing
    }

    public var hasAPIKey: Bool {
        keyStore.hasKey
    }

    public var isAutoModeEnabled: Bool {
        autoMode?.isEnabled ?? false
    }

    public var isSuggestionVisible: Bool {
        suggestionPanel.isVisible
    }

    public var hasScreenRecordingPermission: Bool {
        callVideoPreview.hasScreenRecordingPermission
    }

    public var diagnostics: PaneCueFeatureDiagnostics {
        PaneCueFeatureDiagnostics(
            profile: "Experimental",
            processing: "User-selected experimental mode",
            screenRecording: hasScreenRecordingPermission
                ? "authorized"
                : "not authorized"
        )
    }

    public func configure(context: PaneCueFeatureProviderContext) {
        self.context = context
        voiceCommand = RealtimeVoiceCommandController(
            keyStore: keyStore,
            settings: context.aiSettings,
            connectivity: context.connectivity,
            offlinePack: offlinePack
        )
        autoMode = AutoModeController(
            windowManager: context.windowManager,
            shouldPresentSuggestion: context.shouldPresentSuggestion,
            suggestionHandler: context.suggestionHandler,
            enabledDidChange: { [weak self] _ in
                self?.suggestionPanel.hide()
                self?.context?.stateDidChange(nil)
            }
        )
        callVideoPreview.onUserClose = { [weak self] in
            self?.context?.stateDidChange("Floating video closed")
        }
    }

    public func start() {
        autoMode?.start()
    }

    public func processingModeDidChange(_ mode: AIProcessingMode) {
        if mode == .cloud {
            offlinePack.unloadModels()
        }
    }

    public func connectivityDidChange(isOnline: Bool) {
        guard isOnline,
              context?.aiSettings.processingMode == .automatic
        else {
            return
        }
        offlinePack.unloadModels()
    }

    public func configureAPIKey() throws -> String? {
        try keySettings.present()
    }

    public func requestScreenRecordingAccess() -> String {
        if CGPreflightScreenCaptureAccess() {
            return "Screen Recording access is enabled"
        }
        let granted = CGRequestScreenCaptureAccess()
        return granted
            ? "Screen Recording access is enabled"
            : "Screen Recording access was not granted"
    }

    public func startVoiceListening() async throws {
        guard let voiceCommand else {
            throw ExperimentalFeatureProviderError.notConfigured
        }
        try await voiceCommand.startListening()
    }

    public func stopVoiceAndRun(
        scenarios: [VoiceScenarioReference],
        processingDidBegin: @MainActor () -> Void,
        executor: @escaping @MainActor @Sendable (
            RealtimeToolCall
        ) async throws -> String
    ) async throws -> String {
        guard let voiceCommand else {
            throw ExperimentalFeatureProviderError.notConfigured
        }
        return try await voiceCommand.stopAndRun(
            scenarios: scenarios,
            processingDidBegin: processingDidBegin,
            executor: executor
        )
    }

    public func cancelVoice() {
        voiceCommand?.cancel()
    }

    public func startCallCapture() async throws -> String {
        try await callVideoPreview.startCallCapture()
    }

    public func startBrowserVideoCapture() async throws -> String {
        try await callVideoPreview.startBrowserVideoCapture()
    }

    public func stopVideoCapture() async {
        await callVideoPreview.stopCapture()
    }

    public func setAutoModeEnabled(_ enabled: Bool) {
        autoMode?.setEnabled(enabled)
    }

    public func toggleAutoMode() {
        autoMode?.toggle()
    }

    public func presentAutoModeSuggestion(
        _ suggestion: AutoModeSuggestion,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        suggestionPanel.show(
            suggestion: suggestion,
            onApply: { [weak self] in
                self?.autoMode?.markApplied(suggestion)
                onApply()
            },
            onDismiss: { [weak self] in
                self?.autoMode?.dismiss(suggestion)
                onDismiss()
            }
        )
    }

    public func hideAutoModeSuggestion() {
        suggestionPanel.hide()
    }

    public func pauseAutoMode(for seconds: TimeInterval) {
        autoMode?.pauseSuggestions(for: seconds)
    }

    public func autoModeWorkspaceMayHaveChanged() {
        autoMode?.workspaceMayHaveChanged()
    }

    public func resetAutoModePersonalization() {
        autoMode?.resetPersonalization()
    }

    public func shutdown() async {
        guard !didShutdown else {
            return
        }
        didShutdown = true
        suggestionPanel.hide()
        voiceCommand?.cancel()
        await offlinePack.shutdown()
        await callVideoPreview.stopCapture()
    }
}
