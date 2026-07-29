import AppKit
@preconcurrency import AVFoundation
import PaneCueCore
@preconcurrency import Speech

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let featureProvider: any PaneCueFeatureProvider
    private let windowManager = WindowManager()
    private let customScenarioStore = CustomScenarioStore()
    private let applicationLauncher = ScenarioApplicationLauncher()
    private let aiSettings = AIEngineSettingsStore()
    private let connectivity = ConnectivityMonitor()
    private let offlinePack = OfflinePackManager()
    private let commandLab = CommandLabService()
    private let voiceHUD = VoiceCommandHUDController()
    private let appIconController = PaneCueAppIconController()
    private let terminationCoordinator = PaneCueTerminationCoordinator()
    private lazy var arrangeCoordinator = ArrangeCoordinatorController(
        resolve: { [weak self] plan in
            guard let self else {
                throw CommandLabError.unavailable
            }
            return try windowManager.previewResolution(for: plan)
        },
        apply: { [weak self] plan, resolution in
            guard let self else {
                throw CommandLabError.unavailable
            }
            return try await executeArrangeApply(
                plan,
                resolution: resolution
            )
        },
        rollback: { [weak self] in
            guard let self else {
                throw CommandLabError.unavailable
            }
            return try await executeArrangeRollback()
        }
    )
    private lazy var mainWindow = MainWindowController(
        store: customScenarioStore,
        featureProvider: featureProvider,
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
                self?.configureCloudAccess()
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
                self?.featureProvider.setAutoModeEnabled(enabled)
            },
            scenariosDidChange: { [weak self] in
                self?.rebuildCustomScenariosMenu()
                self?.configureCustomScenarioHotKeys()
            },
            beginArrangement: { [weak self] in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    await arrangeCoordinator.beginEditing()
                }
            },
            discardArrangement: { [weak self] in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    await arrangeCoordinator.discard()
                }
            },
            analyzeCommand: {
                [weak self] transcript, currentPlan in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                let analysis = try await commandLab.analyze(
                    transcript: transcript,
                    currentPlan: currentPlan,
                    scenarios: voiceScenarioReferences,
                    savedScenarios: customScenarioStore.scenarios,
                    offlinePack: offlinePack
                )
                return try await arrangeCoordinator.prepare(
                    analysis,
                    savedScenarios: customScenarioStore.scenarios
                )
            },
            prepareWorkspacePlan: { [weak self] plan in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                return try await arrangeCoordinator.preparePlan(plan)
            },
            selectArrangementCandidate: {
                [weak self] previewID, slotID, candidateID in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                return try await arrangeCoordinator.selectCandidate(
                    previewID: previewID,
                    slotID: slotID,
                    candidateID: candidateID
                )
            },
            arrangementState: { [weak self] in
                guard let self else {
                    return nil
                }
                return await arrangeCoordinator.currentState()
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
                guard let self else {
                    throw CommandLabError.unavailable
                }
                return try await arrangeCoordinator.apply(plan)
            },
            rollbackWorkspace: { [weak self] in
                guard let self else {
                    throw CommandLabError.unavailable
                }
                return try await arrangeCoordinator.rollback()
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
                guard featureProvider.voiceState == .idle else {
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
                    correctionCount: commandLab.correctionCount,
                    features: featureProvider.diagnostics
                )
            },
            resetPersonalization: { [weak self] in
                guard let self else {
                    return 0
                }
                let removedCount = commandLab.resetPersonalization()
                if featureProvider.isExperimental {
                    featureProvider.resetAutoModePersonalization()
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
    private var restoreItem: NSMenuItem!
    private var customScenariosMenu: NSMenu!
    private var globalHotKey: GlobalHotKeyController?
    private var customScenarioHotKeys: CustomScenarioHotKeyController?

    init(featureProvider: any PaneCueFeatureProvider) {
        self.featureProvider = featureProvider
        super.init()
    }

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
        featureProvider.configure(
            context: PaneCueFeatureProviderContext(
                aiSettings: aiSettings,
                connectivity: connectivity,
                windowManager: windowManager,
                shouldPresentSuggestion: { [weak self] in
                    guard let self else {
                        return false
                    }
                    return featureProvider.voiceState == .idle
                        && !featureProvider.isVideoCaptureActive
                        && windowManager.currentScenarioName == nil
                        && NSApp.modalWindow == nil
                        && !featureProvider.isSuggestionVisible
                },
                suggestionHandler: { [weak self] suggestion in
                    self?.presentAutoModeSuggestion(suggestion)
                },
                stateDidChange: { [weak self] message in
                    self?.updateMenuState(message: message)
                },
                runFeatureAction: { [weak self] action in
                    self?.runBuiltInFromDashboard(action)
                },
                toggleVoiceCommand: { [weak self] in
                    self?.toggleVoiceCommand()
                },
                configureCloudAccess: { [weak self] in
                    self?.configureCloudAccess()
                }
            )
        )
        if featureProvider.isExperimental {
            aiSettings.modeDidChange = { [weak self] mode in
                guard let self else {
                    return
                }
                featureProvider.processingModeDidChange(mode)
                updateMenuState(message: mode.detail)
            }
            connectivity.statusDidChange = { [weak self] online in
                guard let self else {
                    return
                }
                featureProvider.connectivityDidChange(isOnline: online)
                updateMenuState(
                    message: online
                        ? "Internet connection available"
                        : "PaneCue is ready to use the Offline Pack"
                )
            }
        } else {
            aiSettings.processingMode = .offline
            aiSettings.localCommandModel = .smart
        }
        configureMainMenu()
        configureStatusItem()
        configureGlobalHotKey()
        configureCustomScenarioHotKeys()
        featureProvider.start()
        mainWindow.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appIconController.stop()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !terminationCoordinator.isComplete else {
            return .terminateNow
        }

        let request = terminationCoordinator.begin { [weak self] in
            await self?.performTerminationCleanup()
        }
        if request.startedCleanup {
            Task { @MainActor in
                await request.task.value
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
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

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "PaneCue")
        applicationMenu.addItem(
            withTitle: "About PaneCue",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Hide PaneCue",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = applicationMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Quit PaneCue",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redoItem = editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Delete",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
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

        featureProvider.installStatusMenuItems(in: menu)

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
        switch featureProvider.voiceState {
        case .idle:
            voiceStateMessage = nil
            statusItem.button?.image = PaneCueBrandAssets.statusIcon
                ?? NSImage(
                    systemSymbolName: "rectangle.split.2x1",
                    accessibilityDescription: "PaneCue"
                )
        case .listening:
            voiceStateMessage = "Listening for a voice command…"
            statusItem.button?.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "PaneCue is listening"
            )
        case .processing:
            voiceStateMessage = "Choosing a window scenario…"
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
                                featureProvider.isExperimental
                                    && featureProvider.isVideoCaptureActive
                                    ? "Floating video is active"
                                    : "Ready"
                            )
                    )
                    : "Accessibility access is required"
            )
        accessibilityItem.isHidden = trusted
        featureProvider.refreshStatusMenuItems()
        let suggestionsEnabled = featureProvider.isExperimental
            ? featureProvider.isAutoModeEnabled
            : false
        restoreItem.isEnabled = windowManager.canRestore
            || (
                featureProvider.isExperimental
                    && featureProvider.isVideoCaptureActive
            )

        mainWindow.update(
            PaneCueDashboardSnapshot(
                statusMessage: statusLineItem.title,
                activeScenarioName: windowManager.currentScenarioName,
                voiceState: featureProvider.voiceState,
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
                    if self.featureProvider.isExperimental {
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
        guard featureProvider.isExperimental else {
            return
        }
        updateMenuState(
            message: featureProvider.requestScreenRecordingAccess()
        )
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
        if !featureProvider.isExperimental,
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

    private func configureCloudAccess() {
        guard featureProvider.isExperimental else {
            return
        }
        if featureProvider.voiceState != .idle {
            featureProvider.cancelVoice()
            voiceHUD.hide()
        }

        do {
            let message = try featureProvider.configureAPIKey()
            updateMenuState(message: message)
        } catch {
            presentError(error)
        }
    }

    private func presentAutoModeSuggestion(
        _ suggestion: AutoModeSuggestion
    ) {
        featureProvider.presentAutoModeSuggestion(
            suggestion,
            onApply: { [weak self] in
                guard let self else {
                    return
                }
                updateMenuState(
                    message: "Suggestions Beta is applying \(suggestion.scenario.title)…"
                )
                runBuiltInFromDashboard(suggestion.scenario.action)
            },
            onDismiss: { [weak self] in
                guard let self else {
                    return
                }
                updateMenuState(message: "Suggestions Beta is watching")
            }
        )
        updateMenuState(
            message: "Suggestions Beta suggests \(suggestion.scenario.title)"
        )
    }

    private func beginUserInitiatedScenario() {
        guard featureProvider.isExperimental else {
            return
        }
        featureProvider.hideAutoModeSuggestion()
        featureProvider.pauseAutoMode(for: 60)
    }

    private func toggleVoiceCommand() {
        guard featureProvider.isExperimental else {
            mainWindow.show(section: .arrange)
            return
        }
        guard !commandLab.isListening else {
            presentError(CommandLabError.unavailable)
            return
        }

        switch featureProvider.voiceState {
        case .idle:
            Task { @MainActor in
                do {
                    try await featureProvider.startVoiceListening()
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
                    let summary = try await featureProvider.stopVoiceAndRun(
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
        if !featureProvider.isExperimental,
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
            let videoSummary = try await featureProvider.startCallCapture()
            do {
                let layoutSummary = try windowManager.applyCodeAndCallLayout()
                return "\(layoutSummary) · \(videoSummary)"
            } catch {
                await featureProvider.stopVideoCapture()
                throw error
            }

        case .applyDocumentationAndCode:
            await featureProvider.stopVideoCapture()
            return try windowManager.applyDocumentationAndCodeLayout()

        case .applyNotesAndBrowser:
            await featureProvider.stopVideoCapture()
            return try windowManager.applyNotesAndBrowserLayout()

        case .showBrowserVideo:
            if windowManager.canRestore {
                _ = try windowManager.restorePreviousLayout()
            }
            return try await featureProvider.startBrowserVideoCapture()

        case .arrangeDynamicWorkspace:
            await featureProvider.stopVideoCapture()
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

    private func applyDocumentationAndCode() {
        beginUserInitiatedScenario()
        Task { @MainActor in
            await featureProvider.stopVideoCapture()
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

    private func applyNotesAndBrowser() {
        beginUserInitiatedScenario()
        Task { @MainActor in
            await featureProvider.stopVideoCapture()
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

    private func applyCodeAndCall() {
        guard featureProvider.isExperimental else {
            return
        }
        beginUserInitiatedScenario()
        Task { @MainActor in
            do {
                try await applicationLauncher.ensureApplications(
                    for: .applyCodeAndCall
                )
                updateMenuState(message: "Starting call video…")
                let videoSummary = try await featureProvider.startCallCapture()
                let layoutSummary = try windowManager.applyCodeAndCallLayout()
                updateMenuState(message: "\(layoutSummary) · \(videoSummary)")
            } catch {
                await featureProvider.stopVideoCapture()
                presentError(error)
            }
        }
    }

    private func showBrowserVideo() {
        guard featureProvider.isExperimental else {
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
                let summary = try await featureProvider
                    .startBrowserVideoCapture()
                updateMenuState(message: summary)
            } catch {
                await featureProvider.stopVideoCapture()
                presentError(error)
            }
        }
    }

    private func applyCustomScenario(
        _ scenario: CustomScenario
    ) async throws -> String {
        try ensureAccessibilityForApply()
        await featureProvider.stopVideoCapture()
        var effectiveScenario = scenario
        if !featureProvider.isExperimental {
            effectiveScenario.conditions = ScenarioConditions()
        }
        try await applicationLauncher.ensureApplications(
            for: effectiveScenario
        )
        return try windowManager.applyCustomLayout(effectiveScenario)
    }

    private func executeArrangeApply(
        _ plan: WorkspacePlan,
        resolution: ArrangementTargetResolutionSet?
    ) async throws -> WorkspaceApplyResult {
        guard let scenario = plan.scenario(named: "Arrange") else {
            throw PaneCueWindowError.operationFailed(
                details: "Add at least two windows before applying this plan."
            )
        }
        try ensureAccessibilityForApply()
        beginUserInitiatedScenario()
        await featureProvider.stopVideoCapture()
        try await applicationLauncher.ensureApplications(for: scenario)
        let result = try windowManager.applyCustomLayoutDetailed(
            scenario,
            resolution: resolution
        )
        updateMenuState(message: result.summary)
        return result
    }

    private func executeArrangeRollback() async throws -> String {
        let summary = try await restoreWorkspace()
        updateMenuState(message: summary)
        featureProvider.autoModeWorkspaceMayHaveChanged()
        return summary
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
        featureProvider.hideAutoModeSuggestion()
        Task { @MainActor in
            do {
                let summary = try await restoreWorkspace()
                updateMenuState(message: summary)
                featureProvider.autoModeWorkspaceMayHaveChanged()
            } catch {
                presentError(error)
            }
        }
    }

    private func restoreWorkspace() async throws -> String {
        let hadFloatingVideo = featureProvider.isVideoCaptureActive
        await featureProvider.stopVideoCapture()

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
        NSApp.terminate(nil)
    }

    private func performTerminationCleanup() async {
        featureProvider.hideAutoModeSuggestion()
        featureProvider.cancelVoice()
        commandLab.cancelListening()
        voiceHUD.hide()
        await offlinePack.shutdown()
        await featureProvider.shutdown()
        appIconController.stop()
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
