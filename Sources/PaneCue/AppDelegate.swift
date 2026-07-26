import AppKit
@preconcurrency import AVFoundation
import PaneCueCore
@preconcurrency import Speech

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let windowManager = WindowManager()
    private let callVideoPreview = CallVideoPreviewController()
    private let apiKeyStore = OpenAIAPIKeyStore()
    private let customScenarioStore = CustomScenarioStore()
    private let applicationLauncher = ScenarioApplicationLauncher()
    private let aiSettings = AIEngineSettingsStore()
    private let connectivity = ConnectivityMonitor()
    private let offlinePack = OfflinePackManager()
    private let commandLab = CommandLabService()
    private let voiceHUD = VoiceCommandHUDController()
    private let appIconController = PaneCueAppIconController()
    private let autoModeSuggestionPanel =
        AutoModeSuggestionPanelController()
    private lazy var apiKeySettings = OpenAIAPIKeySettingsController(
        keyStore: apiKeyStore
    )
    private lazy var voiceCommand = RealtimeVoiceCommandController(
        keyStore: apiKeyStore,
        settings: aiSettings,
        connectivity: connectivity,
        offlinePack: offlinePack
    )
    private lazy var autoMode = AutoModeController(
        windowManager: windowManager,
        shouldPresentSuggestion: { [weak self] in
            guard let self else {
                return false
            }
            return voiceCommand.state == .idle
                && !callVideoPreview.isCapturing
                && windowManager.currentScenarioName == nil
                && NSApp.modalWindow == nil
                && !autoModeSuggestionPanel.isVisible
        },
        suggestionHandler: { [weak self] suggestion in
            self?.presentAutoModeSuggestion(suggestion)
        },
        enabledDidChange: { [weak self] _ in
            self?.autoModeSuggestionPanel.hide()
            self?.updateMenuState()
        }
    )
    private lazy var mainWindow = MainWindowController(
        store: customScenarioStore,
        keyStore: apiKeyStore,
        aiSettings: aiSettings,
        connectivity: connectivity,
        offlinePack: offlinePack,
        actions: PaneCueDashboardActions(
            runBuiltIn: { [weak self] action in
                self?.runBuiltInFromDashboard(action)
            },
            runCustom: { [weak self] id in
                self?.runCustomScenario(id: id)
            },
            restore: { [weak self] in
                self?.restorePreviousLayout()
            },
            toggleVoice: { [weak self] in
                self?.toggleVoiceCommand()
            },
            configureAPIKey: { [weak self] in
                self?.configureOpenAIKey()
            },
            requestAccessibility: { [weak self] in
                self?.requestAccessibility()
            },
            requestScreenRecordingAccess: { [weak self] in
                self?.requestScreenRecordingAccess()
            },
            requestMicrophoneAccess: { [weak self] in
                self?.requestMicrophoneAccess()
            },
            requestSpeechRecognitionAccess: { [weak self] in
                self?.requestSpeechRecognitionAccess()
            },
            openPrivacyPane: { [weak self] pane in
                self?.openPrivacyPane(pane)
            },
            setAutoModeEnabled: { [weak self] enabled in
                self?.autoMode.setEnabled(enabled)
            },
            scenariosDidChange: { [weak self] in
                self?.rebuildCustomScenariosMenu()
                self?.configureCustomScenarioHotKeys()
            },
            analyzeCommand: {
                [weak self] transcript, currentPlan in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                return try await commandLab.analyze(
                    transcript: transcript,
                    currentPlan: currentPlan,
                    scenarios: voiceScenarioReferences,
                    savedScenarios: customScenarioStore.scenarios,
                    offlinePack: offlinePack
                )
            },
            applyAnalyzedCommand: { [weak self] intent in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                beginUserInitiatedScenario()
                let summary = try await executeVoiceAction(
                    RealtimeToolCall(
                        action: intent.action,
                        callID: "command-lab-\(UUID().uuidString)",
                        arguments: intent.arguments
                    )
                )
                updateMenuState(message: summary)
                return summary
            },
            applyWorkspacePlan: { [weak self] plan in
                guard let self,
                      let scenario = plan.scenario(
                          named: "Arrange"
                      ) else {
                    throw PaneCueWindowError.operationFailed(
                        details: "Add at least two windows before applying this plan."
                    )
                }
                try ensureAccessibilityForApply()
                beginUserInitiatedScenario()
                await callVideoPreview.stopCapture()
                try await applicationLauncher.ensureApplications(
                    for: scenario
                )
                let result = try windowManager.applyCustomLayoutDetailed(
                    scenario
                )
                updateMenuState(message: result.summary)
                return result
            },
            rollbackWorkspace: { [weak self] in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                let summary = try await restoreWorkspace()
                updateMenuState(message: summary)
                autoMode.workspaceMayHaveChanged()
                return summary
            },
            saveCommandCorrection: {
                [weak self] transcript, intent in
                self?.commandLab.saveCorrection(
                    transcript: transcript,
                    intent: intent
                )
            },
            savePlanCorrection: {
                [weak self] transcript, plan in
                self?.commandLab.saveCorrection(
                    transcript: transcript,
                    plan: plan
                )
            },
            startCommandLabListening: { [weak self] in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                guard voiceCommand.state == .idle else {
                    throw CommandLabError.unavailable
                }
                try await commandLab.startListening()
            },
            stopCommandLabListening: { [weak self] in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                return try await commandLab.stopAndTranscribe()
            },
            cancelCommandLabListening: { [weak self] in
                self?.commandLab.cancelListening()
            },
            makeDiagnosticsReport: { [weak self] in
                guard let self else {
                    return "{\n  \"error\" : \"PaneCue is unavailable\"\n}"
                }
                return PaneCueDiagnostics.report(
                    scenarios: customScenarioStore.scenarios,
                    correctionCount: commandLab.correctionCount
                )
            },
            resetPersonalization: { [weak self] in
                guard let self else {
                    return 0
                }
                let removedCount = commandLab.resetPersonalization()
                if PaneCueReleaseProfile.current.isExperimental {
                    autoMode.resetPersonalization()
                }
                updateMenuState(
                    message: "Personalization reset · \(removedCount) corrections removed"
                )
                return removedCount
            }
        )
    )
    private var statusItem: NSStatusItem!
    private var statusLineItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var apiKeyStatusItem: NSMenuItem!
    private var voiceCommandItem: NSMenuItem!
    private var autoModeItem: NSMenuItem!
    private var restoreItem: NSMenuItem!
    private var customScenariosMenu: NSMenu!
    private var globalHotKey: GlobalHotKeyController?
    private var customScenarioHotKeys: CustomScenarioHotKeyController?

    private var voiceScenarioReferences: [VoiceScenarioReference] {
        customScenarioStore.scenarios.map { scenario in
            VoiceScenarioReference(
                name: scenario.name,
                activationPhrases: [
                    scenario.voicePhrase
                ].filter { !$0.isEmpty }
            )
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        appIconController.start()
        if PaneCueReleaseProfile.current.isExperimental {
            aiSettings.modeDidChange = { [weak self] mode in
                guard let self else {
                    return
                }
                if mode == .cloud {
                    offlinePack.unloadModels()
                }
                updateMenuState(message: mode.detail)
            }
            connectivity.statusDidChange = { [weak self] online in
                guard let self else {
                    return
                }
                if online, aiSettings.processingMode == .automatic {
                    offlinePack.unloadModels()
                }
                updateMenuState(
                    message: online
                        ? "Internet connection available"
                        : "PaneCue is ready to use the Offline Pack"
                )
            }
            callVideoPreview.onUserClose = { [weak self] in
                self?.updateMenuState(message: "Floating video closed")
            }
        } else {
            aiSettings.processingMode = .offline
            aiSettings.localCommandModel = .smart
        }
        configureStatusItem()
        configureGlobalHotKey()
        configureCustomScenarioHotKeys()
        if PaneCueReleaseProfile.current.isExperimental {
            autoMode.start()
        }
        mainWindow.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appIconController.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        mainWindow.refreshPermissions()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        mainWindow.show()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildCustomScenariosMenu()
        updateMenuState()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = PaneCueBrandAssets.statusIcon
                ?? NSImage(
                    systemSymbolName: "rectangle.split.2x1",
                    accessibilityDescription: "PaneCue"
                )
            button.toolTip = PaneCueReleaseProfile.current.displayName
        }

        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(
            title: "Open Arrange",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        statusLineItem = NSMenuItem(title: "PaneCue is starting…", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)
        menu.addItem(.separator())

        accessibilityItem = NSMenuItem(
            title: "Grant Accessibility Access…",
            action: #selector(requestAccessibility),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        apiKeyStatusItem = NSMenuItem(
            title: "Voice: checking configuration…",
            action: nil,
            keyEquivalent: ""
        )
        apiKeyStatusItem.isEnabled = false

        let apiKeyItem = NSMenuItem(
            title: "OpenAI API Key…",
            action: #selector(configureOpenAIKey),
            keyEquivalent: ""
        )
        apiKeyItem.target = self

        voiceCommandItem = NSMenuItem(
            title: "Start Voice Command (⌥ Space)",
            action: #selector(toggleVoiceCommand),
            keyEquivalent: ""
        )
        voiceCommandItem.target = self

        autoModeItem = NSMenuItem(
            title: "Suggestions Beta",
            action: #selector(toggleAutoMode),
            keyEquivalent: ""
        )
        autoModeItem.target = self

        let codeAndCallItem = NSMenuItem(
            title: "Code + Call",
            action: #selector(applyCodeAndCall),
            keyEquivalent: "1"
        )
        codeAndCallItem.target = self

        let documentationAndCodeItem = NSMenuItem(
            title: "Documentation + Code",
            action: #selector(applyDocumentationAndCode),
            keyEquivalent: "2"
        )
        documentationAndCodeItem.target = self

        let notesAndBrowserItem = NSMenuItem(
            title: "Notes + Browser",
            action: #selector(applyNotesAndBrowser),
            keyEquivalent: "3"
        )
        notesAndBrowserItem.target = self

        let browserVideoItem = NSMenuItem(
            title: "Browser Video",
            action: #selector(showBrowserVideo),
            keyEquivalent: "4"
        )
        browserVideoItem.target = self

        if PaneCueReleaseProfile.current.isExperimental {
            menu.addItem(apiKeyStatusItem)
            menu.addItem(apiKeyItem)
            menu.addItem(.separator())
            menu.addItem(voiceCommandItem)
            menu.addItem(autoModeItem)
            menu.addItem(.separator())
            menu.addItem(codeAndCallItem)
            menu.addItem(documentationAndCodeItem)
            menu.addItem(notesAndBrowserItem)
            menu.addItem(browserVideoItem)
        }

        customScenariosMenu = NSMenu(title: "Cues")
        let customScenariosItem = NSMenuItem(
            title: "Cues",
            action: nil,
            keyEquivalent: ""
        )
        customScenariosItem.submenu = customScenariosMenu
        menu.addItem(customScenariosItem)

        let editScenariosItem = NSMenuItem(
            title: "Edit Cues…",
            action: #selector(editCustomScenarios),
            keyEquivalent: ","
        )
        editScenariosItem.target = self
        menu.addItem(editScenariosItem)

        restoreItem = NSMenuItem(
            title: "Restore Previous Layout",
            action: #selector(restorePreviousLayout),
            keyEquivalent: ""
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit PaneCue",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        rebuildCustomScenariosMenu()
        updateMenuState()
    }

    private func rebuildCustomScenariosMenu() {
        guard customScenariosMenu != nil else {
            return
        }

        customScenariosMenu.removeAllItems()

        if customScenarioStore.scenarios.isEmpty {
            let emptyItem = NSMenuItem(
                title: "No Cues",
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            customScenariosMenu.addItem(emptyItem)
            return
        }

        for scenario in customScenarioStore.scenarios {
            let shortcutSuffix = scenario.hotKey.isEnabled
                ? "  \(scenario.hotKey.displayName)"
                : ""
            let item = NSMenuItem(
                title: scenario.name + shortcutSuffix,
                action: #selector(applyCustomScenarioFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = scenario.id.uuidString
            customScenariosMenu.addItem(item)
        }
    }

    private func updateMenuState(message: String? = nil) {
        let trusted = windowManager.hasAccessibilityPermission
        let voiceStateMessage: String?
        switch voiceCommand.state {
        case .idle:
            voiceStateMessage = nil
            voiceCommandItem.title = "Start Voice Command (⌥ Space)"
            voiceCommandItem.isEnabled = true
            statusItem.button?.image = PaneCueBrandAssets.statusIcon
                ?? NSImage(
                    systemSymbolName: "rectangle.split.2x1",
                    accessibilityDescription: "PaneCue"
                )
        case .listening:
            voiceStateMessage = "Listening for a voice command…"
            voiceCommandItem.title = "Stop and Run Voice Command (⌥ Space)"
            voiceCommandItem.isEnabled = true
            statusItem.button?.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "PaneCue is listening"
            )
        case .processing:
            voiceStateMessage = "Choosing a window scenario…"
            voiceCommandItem.title = "Voice Command Is Processing…"
            voiceCommandItem.isEnabled = false
            statusItem.button?.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "PaneCue is processing a voice command"
            )
        }

        statusLineItem.title = message
            ?? voiceStateMessage
            ?? (
                trusted
                    ? (
                        windowManager.currentScenarioName.map { "\($0) is active" }
                            ?? (
                                PaneCueReleaseProfile.current.isExperimental
                                    && callVideoPreview.isCapturing
                                    ? "Floating video is active"
                                    : "Ready"
                            )
                    )
                    : "Accessibility access is required"
            )
        accessibilityItem.isHidden = trusted
        let suggestionsEnabled =
            PaneCueReleaseProfile.current.isExperimental
                ? autoMode.isEnabled
                : false
        autoModeItem.state = suggestionsEnabled ? .on : .off
        if PaneCueReleaseProfile.current.isExperimental {
            apiKeyStatusItem.title = apiKeyStore.hasKey
                ? "Voice: OpenAI key is in Keychain"
                : "Voice: OpenAI key is not configured"
        }
        restoreItem.isEnabled = windowManager.canRestore
            || (
                PaneCueReleaseProfile.current.isExperimental
                    && callVideoPreview.isCapturing
            )

        mainWindow.update(
            PaneCueDashboardSnapshot(
                statusMessage: statusLineItem.title,
                activeScenarioName: windowManager.currentScenarioName,
                voiceState: voiceCommand.state,
                canRestore: restoreItem.isEnabled,
                isAutoModeEnabled: suggestionsEnabled
            )
        )
    }

    private func configureGlobalHotKey() {
        do {
            globalHotKey = try GlobalHotKeyController { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    if PaneCueReleaseProfile.current.isExperimental {
                        self.toggleVoiceCommand()
                    } else {
                        self.mainWindow.show(section: .arrange)
                    }
                }
            }
        } catch {
            updateMenuState(message: error.localizedDescription)
        }
    }

    private func configureCustomScenarioHotKeys() {
        customScenarioHotKeys = nil
        do {
            let controller = try CustomScenarioHotKeyController(
                scenarios: customScenarioStore.scenarios
            ) { [weak self] scenarioID in
                Task { @MainActor [weak self] in
                    self?.runCustomScenario(id: scenarioID)
                }
            }
            customScenarioHotKeys = controller
            if !controller.unavailableShortcuts.isEmpty {
                updateMenuState(
                    message: "Some Cue shortcuts are already used by macOS or another app"
                )
            }
        } catch {
            updateMenuState(message: error.localizedDescription)
        }
    }

    @objc
    private func requestAccessibility() {
        _ = windowManager.requestAccessibilityPermission()
        updateMenuState(message: "Enable PaneCue in System Settings, then reopen this menu")
    }

    private func requestScreenRecordingAccess() {
        guard PaneCueReleaseProfile.current.isExperimental else {
            return
        }
        guard !CGPreflightScreenCaptureAccess() else {
            updateMenuState(message: "Screen Recording access is enabled")
            return
        }

        let defaults = UserDefaults.standard
        let requestKey = "PaneCue.didRequestScreenRecordingPermission"
        let hasRequested = defaults.bool(forKey: requestKey)
        defaults.set(true, forKey: requestKey)

        let granted = CGRequestScreenCaptureAccess()
        updateMenuState(
            message: granted
                ? "Screen Recording access is enabled"
                : "Screen Recording access was not granted"
        )
        if !granted, hasRequested {
            openPrivacyPane(.screenRecording)
        }
    }

    private func requestMicrophoneAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            updateMenuState(message: "Microphone access is enabled")
        case .notDetermined:
            Task { @MainActor [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                guard let self else {
                    return
                }
                updateMenuState(
                    message: granted
                        ? "Microphone access is enabled"
                        : "Microphone access was not granted"
                )
            }
        case .denied, .restricted:
            openPrivacyPane(.microphone)
        @unknown default:
            openPrivacyPane(.microphone)
        }
    }

    private func requestSpeechRecognitionAccess() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            updateMenuState(message: "Speech Recognition access is enabled")
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.updateMenuState(
                        message: status == .authorized
                            ? "Speech Recognition access is enabled"
                            : "Speech Recognition access was not granted"
                    )
                }
            }
        case .denied, .restricted:
            openPrivacyPane(.speechRecognition)
        @unknown default:
            openPrivacyPane(.speechRecognition)
        }
    }

    @objc
    private func showMainWindow() {
        mainWindow.show()
    }

    @objc
    private func editCustomScenarios() {
        mainWindow.show(section: .cues)
    }

    @objc
    private func applyCustomScenarioFromMenu(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString)
        else {
            return
        }

        runCustomScenario(id: id)
    }

    private func runCustomScenario(id: UUID) {
        guard let scenario = customScenarioStore.scenario(id: id) else {
            return
        }

        beginUserInitiatedScenario()
        Task { @MainActor in
            do {
                let summary = try await applyCustomScenario(scenario)
                updateMenuState(message: summary)
            } catch {
                presentError(error)
            }
        }
    }

    private func runBuiltInFromDashboard(
        _ action: VoiceCommandAction
    ) {
        if !PaneCueReleaseProfile.current.isExperimental,
           (
               action == .applyCodeAndCall
                   || action == .showBrowserVideo
           ) {
            return
        }
        beginUserInitiatedScenario()
        switch action {
        case .applyCodeAndCall:
            applyCodeAndCall()
        case .applyDocumentationAndCode:
            applyDocumentationAndCode()
        case .applyNotesAndBrowser:
            applyNotesAndBrowser()
        case .showBrowserVideo:
            showBrowserVideo()
        case .arrangeDynamicWorkspace,
             .applyCustomScenario,
             .restorePreviousLayout:
            break
        }
    }

    private func openPrivacyPane(_ pane: PaneCuePrivacyPane) {
        let anchor: String
        switch pane {
        case .screenRecording:
            anchor = "Privacy_ScreenCapture"
        case .microphone:
            anchor = "Privacy_Microphone"
        case .speechRecognition:
            anchor = "Privacy_SpeechRecognition"
        }

        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func configureOpenAIKey() {
        guard PaneCueReleaseProfile.current.isExperimental else {
            return
        }
        if voiceCommand.state != .idle {
            voiceCommand.cancel()
            voiceHUD.hide()
        }

        do {
            let message = try apiKeySettings.present()
            updateMenuState(message: message)
        } catch {
            presentError(error)
        }
    }

    @objc
    private func toggleAutoMode() {
        guard PaneCueReleaseProfile.current.isExperimental else {
            return
        }
        autoMode.toggle()
    }

    private func presentAutoModeSuggestion(
        _ suggestion: AutoModeSuggestion
    ) {
        autoModeSuggestionPanel.show(
            suggestion: suggestion,
            onApply: { [weak self] in
                guard let self else {
                    return
                }
                autoMode.markApplied(suggestion)
                updateMenuState(
                    message: "Suggestions Beta is applying \(suggestion.scenario.title)…"
                )
                runBuiltInFromDashboard(suggestion.scenario.action)
            },
            onDismiss: { [weak self] in
                guard let self else {
                    return
                }
                autoMode.dismiss(suggestion)
                updateMenuState(message: "Suggestions Beta is watching")
            }
        )
        updateMenuState(
            message: "Suggestions Beta suggests \(suggestion.scenario.title)"
        )
    }

    private func beginUserInitiatedScenario() {
        guard PaneCueReleaseProfile.current.isExperimental else {
            return
        }
        autoModeSuggestionPanel.hide()
        autoMode.pauseSuggestions(for: 60)
    }

    @objc
    private func toggleVoiceCommand() {
        guard PaneCueReleaseProfile.current.isExperimental else {
            mainWindow.show(section: .arrange)
            return
        }
        guard !commandLab.isListening else {
            presentError(CommandLabError.unavailable)
            return
        }

        switch voiceCommand.state {
        case .idle:
            Task { @MainActor in
                do {
                    try await voiceCommand.startListening()
                    voiceHUD.showListening()
                    updateMenuState()
                } catch {
                    voiceHUD.hide()
                    presentError(error)
                }
            }

        case .listening:
            Task { @MainActor in
                do {
                    let summary = try await voiceCommand.stopAndRun(
                        scenarios: customScenarioStore.scenarios.map {
                            scenario in
                            VoiceScenarioReference(
                                name: scenario.name,
                                activationPhrases: [
                                    scenario.voicePhrase
                                ].filter { !$0.isEmpty }
                            )
                        },
                        processingDidBegin: {
                            self.voiceHUD.showProcessing()
                            self.updateMenuState(
                                message: "Choosing a window scenario…"
                            )
                        },
                        executor: { call in
                            try await self.executeVoiceAction(call)
                        }
                    )
                    voiceHUD.showSuccess(summary)
                    updateMenuState(message: summary)
                } catch {
                    voiceHUD.hide()
                    presentError(error)
                }
            }

        case .processing:
            NSSound.beep()
        }
    }

    private func executeVoiceAction(
        _ call: RealtimeToolCall
    ) async throws -> String {
        if !PaneCueReleaseProfile.current.isExperimental,
           (
               call.action == .applyCodeAndCall
                   || call.action == .showBrowserVideo
           ) {
            throw PaneCueWindowError.operationFailed(
                details: "Call and browser video are available only in PaneCue Experimental."
            )
        }
        try ensureAccessibilityForApply()
        try await applicationLauncher.ensureApplications(
            for: call.action
        )

        switch call.action {
        case .applyCodeAndCall:
            let videoSummary = try await callVideoPreview.startCallCapture()
            do {
                let layoutSummary = try windowManager.applyCodeAndCallLayout()
                return "\(layoutSummary) · \(videoSummary)"
            } catch {
                await callVideoPreview.stopCapture()
                throw error
            }

        case .applyDocumentationAndCode:
            await callVideoPreview.stopCapture()
            return try windowManager.applyDocumentationAndCodeLayout()

        case .applyNotesAndBrowser:
            await callVideoPreview.stopCapture()
            return try windowManager.applyNotesAndBrowserLayout()

        case .showBrowserVideo:
            if windowManager.canRestore {
                _ = try windowManager.restorePreviousLayout()
            }
            return try await callVideoPreview.startBrowserVideoCapture()

        case .arrangeDynamicWorkspace:
            await callVideoPreview.stopCapture()
            let scenario = try DynamicWorkspaceScenarioBuilder.scenario(
                from: call.arguments
            )
            try await applicationLauncher.ensureApplications(
                for: scenario
            )
            return try windowManager.applyCustomLayout(scenario)

        case .applyCustomScenario:
            guard let name = call.arguments["scenario_name"],
                  let scenario = customScenarioStore.scenario(named: name)
            else {
                throw PaneCueWindowError.operationFailed(
                    details: "The requested Cue no longer exists. Open Cues and save it again."
                )
            }
            return try await applyCustomScenario(scenario)

        case .restorePreviousLayout:
            return try await restoreWorkspace()
        }
    }

    @objc
    private func applyDocumentationAndCode() {
        beginUserInitiatedScenario()
        Task { @MainActor in
            await callVideoPreview.stopCapture()
            do {
                try await applicationLauncher.ensureApplications(
                    for: .applyDocumentationAndCode
                )
                let summary = try windowManager.applyDocumentationAndCodeLayout()
                updateMenuState(message: summary)
            } catch {
                presentError(error)
            }
        }
    }

    @objc
    private func applyNotesAndBrowser() {
        beginUserInitiatedScenario()
        Task { @MainActor in
            await callVideoPreview.stopCapture()
            do {
                try await applicationLauncher.ensureApplications(
                    for: .applyNotesAndBrowser
                )
                let summary = try windowManager.applyNotesAndBrowserLayout()
                updateMenuState(message: summary)
            } catch {
                presentError(error)
            }
        }
    }

    @objc
    private func applyCodeAndCall() {
        guard PaneCueReleaseProfile.current.isExperimental else {
            return
        }
        beginUserInitiatedScenario()
        Task { @MainActor in
            do {
                try await applicationLauncher.ensureApplications(
                    for: .applyCodeAndCall
                )
                updateMenuState(message: "Starting call video…")
                let videoSummary = try await callVideoPreview.startCallCapture()
                let layoutSummary = try windowManager.applyCodeAndCallLayout()
                updateMenuState(message: "\(layoutSummary) · \(videoSummary)")
            } catch {
                await callVideoPreview.stopCapture()
                presentError(error)
            }
        }
    }

    @objc
    private func showBrowserVideo() {
        guard PaneCueReleaseProfile.current.isExperimental else {
            return
        }
        beginUserInitiatedScenario()
        Task { @MainActor in
            do {
                try await applicationLauncher.ensureApplications(
                    for: .showBrowserVideo
                )
                if windowManager.canRestore {
                    _ = try windowManager.restorePreviousLayout()
                }
                updateMenuState(message: "Extracting browser video…")
                let summary = try await callVideoPreview.startBrowserVideoCapture()
                updateMenuState(message: summary)
            } catch {
                await callVideoPreview.stopCapture()
                presentError(error)
            }
        }
    }

    private func applyCustomScenario(
        _ scenario: CustomScenario
    ) async throws -> String {
        try ensureAccessibilityForApply()
        await callVideoPreview.stopCapture()
        var effectiveScenario = scenario
        if !PaneCueReleaseProfile.current.isExperimental {
            effectiveScenario.conditions = ScenarioConditions()
        }
        try await applicationLauncher.ensureApplications(
            for: effectiveScenario
        )
        return try windowManager.applyCustomLayout(effectiveScenario)
    }

    private func ensureAccessibilityForApply() throws {
        guard !windowManager.hasAccessibilityPermission else {
            return
        }
        _ = windowManager.requestAccessibilityPermission()
        updateMenuState(
            message: "Accessibility access is required before Apply"
        )
        throw PaneCueWindowError.accessibilityPermissionRequired
    }

    @objc
    private func restorePreviousLayout() {
        autoModeSuggestionPanel.hide()
        Task { @MainActor in
            do {
                let summary = try await restoreWorkspace()
                updateMenuState(message: summary)
                autoMode.workspaceMayHaveChanged()
            } catch {
                presentError(error)
            }
        }
    }

    private func restoreWorkspace() async throws -> String {
        let hadFloatingVideo = callVideoPreview.isCapturing
        await callVideoPreview.stopCapture()

        if windowManager.canRestore {
            let layoutSummary = try windowManager.restorePreviousLayout()
            return hadFloatingVideo
                ? "\(layoutSummary) · Floating video closed"
                : layoutSummary
        }

        if hadFloatingVideo {
            return "Floating video closed"
        }

        throw PaneCueWindowError.noSnapshot
    }

    @objc
    private func quit() {
        Task { @MainActor in
            autoModeSuggestionPanel.hide()
            voiceCommand.cancel()
            commandLab.cancelListening()
            voiceHUD.hide()
            await offlinePack.shutdown()
            await callVideoPreview.stopCapture()
            NSApp.terminate(nil)
        }
    }

    private func presentError(_ error: Error) {
        updateMenuState(message: error.localizedDescription)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PaneCue couldn’t complete the action"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
