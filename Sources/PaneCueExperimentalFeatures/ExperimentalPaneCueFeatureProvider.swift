import AppKit
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
    NSObject,
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
    private var apiKeyStatusItem: NSMenuItem?
    private var voiceCommandItem: NSMenuItem?
    private var autoModeItem: NSMenuItem?

    public override init() {
        super.init()
    }

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

    public func installStatusMenuItems(in menu: NSMenu) {
        guard apiKeyStatusItem == nil else {
            return
        }

        let keyStatus = NSMenuItem(
            title: "Voice: checking configuration…",
            action: nil,
            keyEquivalent: ""
        )
        keyStatus.isEnabled = false
        apiKeyStatusItem = keyStatus

        let keyItem = menuItem(
            title: "OpenAI API Key…",
            action: #selector(configureCloudAccessFromMenu)
        )
        let voiceItem = menuItem(
            title: "Start Voice Command",
            action: #selector(toggleVoiceCommandFromMenu)
        )
        voiceCommandItem = voiceItem
        let suggestionsItem = menuItem(
            title: "Suggestions Beta",
            action: #selector(toggleAutoModeFromMenu)
        )
        autoModeItem = suggestionsItem

        menu.addItem(keyStatus)
        menu.addItem(keyItem)
        menu.addItem(.separator())
        menu.addItem(voiceItem)
        menu.addItem(suggestionsItem)
        menu.addItem(.separator())
        menu.addItem(
            menuItem(
                title: "Code + Call",
                action: #selector(applyCodeAndCallFromMenu),
                keyEquivalent: "1"
            )
        )
        menu.addItem(
            menuItem(
                title: "Documentation + Code",
                action: #selector(applyDocumentationAndCodeFromMenu),
                keyEquivalent: "2"
            )
        )
        menu.addItem(
            menuItem(
                title: "Notes + Browser",
                action: #selector(applyNotesAndBrowserFromMenu),
                keyEquivalent: "3"
            )
        )
        menu.addItem(
            menuItem(
                title: "Browser Video",
                action: #selector(showBrowserVideoFromMenu),
                keyEquivalent: "4"
            )
        )
        refreshStatusMenuItems()
    }

    public func refreshStatusMenuItems() {
        apiKeyStatusItem?.title = hasAPIKey
            ? "Voice: OpenAI key is in Keychain"
            : "Voice: OpenAI key is not configured"
        autoModeItem?.state = isAutoModeEnabled ? .on : .off

        switch voiceState {
        case .idle:
            voiceCommandItem?.title = "Start Voice Command"
            voiceCommandItem?.isEnabled = true
        case .listening:
            voiceCommandItem?.title = "Stop and Run Voice Command"
            voiceCommandItem?.isEnabled = true
        case .processing:
            voiceCommandItem?.title = "Voice Command Is Processing…"
            voiceCommandItem?.isEnabled = false
        }
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

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.target = self
        return item
    }

    @objc
    private func configureCloudAccessFromMenu() {
        context?.configureCloudAccess()
    }

    @objc
    private func toggleVoiceCommandFromMenu() {
        context?.toggleVoiceCommand()
    }

    @objc
    private func toggleAutoModeFromMenu() {
        toggleAutoMode()
        context?.stateDidChange(nil)
    }

    @objc
    private func applyCodeAndCallFromMenu() {
        context?.runFeatureAction(.applyCodeAndCall)
    }

    @objc
    private func applyDocumentationAndCodeFromMenu() {
        context?.runFeatureAction(.applyDocumentationAndCode)
    }

    @objc
    private func applyNotesAndBrowserFromMenu() {
        context?.runFeatureAction(.applyNotesAndBrowser)
    }

    @objc
    private func showBrowserVideoFromMenu() {
        context?.runFeatureAction(.showBrowserVideo)
    }
}
