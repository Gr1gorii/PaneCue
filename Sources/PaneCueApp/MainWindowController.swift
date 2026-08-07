import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import PaneCueCore
@preconcurrency import Speech
import SwiftUI
import UniformTypeIdentifiers

enum PaneCueDashboardSection: String, CaseIterable, Identifiable {
    case arrange
    case cues
    case settings

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .arrange:
            return "Arrange"
        case .cues:
            return "Cues"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .arrange:
            return "rectangle.3.group"
        case .cues:
            return "rectangle.split.2x1"
        case .settings:
            return "gearshape"
        }
    }
}

enum PaneCuePrivacyPane {
    case screenRecording
    case microphone
    case speechRecognition
}

struct PaneCueDashboardSnapshot {
    let statusMessage: String
    let activeScenarioName: String?
    let voiceState: PaneCueVoiceState
    let canRestore: Bool
    let isAutoModeEnabled: Bool
    let quickCueShortcutStatus: QuickCueShortcutStatus
}

struct PaneCueDashboardActions {
    let runBuiltIn: @MainActor (VoiceCommandAction) -> Void
    let runCustom: @MainActor (UUID) -> Void
    let restore: @MainActor () -> Void
    let toggleVoice: @MainActor () -> Void
    let configureAPIKey: @MainActor () -> Void
    let requestAccessibility: @MainActor () -> Void
    let requestScreenRecordingAccess: @MainActor () -> Void
    let requestMicrophoneAccess: @MainActor () -> Void
    let requestSpeechRecognitionAccess: @MainActor () -> Void
    let openPrivacyPane: @MainActor (PaneCuePrivacyPane) -> Void
    let setAutoModeEnabled: @MainActor (Bool) -> Void
    let scenariosDidChange: @MainActor () -> Void
    let beginArrangement: @MainActor () -> Void
    let discardArrangement: @MainActor () -> Void
    let analyzeCommand: @MainActor
        (String, WorkspacePlan?) async throws -> CommandLabAnalysis
    let prepareWorkspacePlan: @MainActor
        (WorkspacePlan) async throws -> ArrangementPreview
    let selectArrangementCandidate: @MainActor
        (
            UUID,
            UUID,
            EphemeralWindowIdentifier
        ) async throws -> ArrangementPreview
    let arrangementState: @MainActor
        () async -> ArrangementCoordinatorState?
    let applyAnalyzedCommand: @MainActor
        (VoiceCommandIntent) async throws -> String
    let applyWorkspacePlan: @MainActor
        (WorkspacePlan) async throws -> WorkspaceApplyResult
    let rollbackWorkspace: @MainActor () async throws -> String
    let saveCommandCorrection: @MainActor
        (String, VoiceCommandIntent?) -> Void
    let savePlanCorrection: @MainActor
        (String, WorkspacePlan) -> Void
    let startCommandLabListening: @MainActor () async throws -> Void
    let stopCommandLabListening: @MainActor () async throws -> String
    let cancelCommandLabListening: @MainActor () -> Void
    let makeDiagnosticsReport: @MainActor () -> String
    let resetPersonalization: @MainActor () -> Int
    let clearApplyHistory: @MainActor () throws -> Int
}

@MainActor
final class PaneCueDashboardModel: ObservableObject {
    @Published var selectedSection: PaneCueDashboardSection = .arrange
    @Published private(set) var scenarios: [CustomScenario]
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var activeScenarioName: String?
    @Published private(set) var voiceState: PaneCueVoiceState = .idle
    @Published private(set) var canRestore = false
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var microphoneAuthorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var speechRecognitionAuthorizationStatus =
        SFSpeechRecognizer.authorizationStatus()
    @Published private(set) var hasAPIKey = false
    @Published private(set) var isAutoModeEnabled = false
    @Published private(set) var quickCueShortcutStatus:
        QuickCueShortcutStatus = .unavailable
    @Published private(set) var hasCompletedTextOnboarding = false
    @Published private(set) var editorRevision = 0
    @Published private(set) var arrangementRevision = 0
    @Published private(set) var arrangementPreview: ArrangementPreview?
    @Published private(set) var arrangementEditorSeed: ArrangementPreview?
    @Published var isOnboardingPresented: Bool

    let applications: [InstalledApplication]
    let aiSettings: AIEngineSettingsStore
    let connectivity: ConnectivityMonitor
    let offlinePack: OfflinePackManager

    private let store: CustomScenarioStore
    private let featureProvider: any PaneCueFeatureProvider
    private let actions: PaneCueDashboardActions
    private let defaults: UserDefaults

    private static let onboardingVersion = 1
    private static let onboardingVersionKey =
        PaneCuePersistenceKey.onboardingCompletedVersion
    private static let textOnboardingKey =
        PaneCuePersistenceKey.completedFirstApply

    var hasMicrophonePermission: Bool {
        microphoneAuthorizationStatus == .authorized
    }

    var microphoneActionTitle: String {
        microphoneAuthorizationStatus == .notDetermined
            ? "Request Access"
            : "Open Settings"
    }

    var hasSpeechRecognitionPermission: Bool {
        speechRecognitionAuthorizationStatus == .authorized
    }

    var speechRecognitionActionTitle: String {
        speechRecognitionAuthorizationStatus == .notDetermined
            ? "Request Access"
            : "Open Settings"
    }

    init(
        store: CustomScenarioStore,
        featureProvider: any PaneCueFeatureProvider,
        aiSettings: AIEngineSettingsStore,
        connectivity: ConnectivityMonitor,
        offlinePack: OfflinePackManager,
        defaults: UserDefaults = .standard,
        actions: PaneCueDashboardActions
    ) {
        self.store = store
        self.featureProvider = featureProvider
        self.aiSettings = aiSettings
        self.connectivity = connectivity
        self.offlinePack = offlinePack
        self.defaults = defaults
        self.actions = actions
        isOnboardingPresented =
            featureProvider.isExperimental
                && defaults.integer(forKey: Self.onboardingVersionKey)
                    < Self.onboardingVersion
        scenarios = store.scenarios
        applications = ApplicationCatalog.installedApplications()
        hasCompletedTextOnboarding = defaults.bool(
            forKey: Self.textOnboardingKey
        )
        refreshPermissions()
    }

    func update(_ snapshot: PaneCueDashboardSnapshot) {
        statusMessage = snapshot.statusMessage
        activeScenarioName = snapshot.activeScenarioName
        voiceState = snapshot.voiceState
        canRestore = snapshot.canRestore
        isAutoModeEnabled = snapshot.isAutoModeEnabled
        quickCueShortcutStatus = snapshot.quickCueShortcutStatus
        refreshPermissions()
    }

    func refreshPermissions() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        hasScreenRecordingPermission =
            featureProvider.hasScreenRecordingPermission
        microphoneAuthorizationStatus =
            AVCaptureDevice.authorizationStatus(for: .audio)
        speechRecognitionAuthorizationStatus =
            SFSpeechRecognizer.authorizationStatus()
        hasAPIKey = featureProvider.hasAPIKey
    }

    func openScenarios() {
        editorRevision += 1
        selectedSection = .cues
    }

    func startNewArrangement() {
        actions.beginArrangement()
        arrangementPreview = nil
        arrangementEditorSeed = nil
        arrangementRevision += 1
        selectedSection = .arrange
    }

    func discardArrangementPreview() {
        arrangementPreview = nil
        arrangementEditorSeed = nil
        actions.discardArrangement()
    }

    func stageArrangementPreviewForEditor(
        _ preview: ArrangementPreview
    ) {
        arrangementPreview = preview
        arrangementEditorSeed = preview
        selectedSection = .arrange
    }

    func consumeArrangementEditorSeed(_ previewID: UUID) {
        guard arrangementEditorSeed?.id == previewID else {
            return
        }
        arrangementEditorSeed = nil
    }

    func saveScenarios(_ updatedScenarios: [CustomScenario]) {
        store.replaceAll(with: updatedScenarios)
        scenarios = store.scenarios
        editorRevision += 1
        actions.scenariosDidChange()
        selectedSection = .cues
    }

    func runBuiltIn(_ action: VoiceCommandAction) {
        actions.runBuiltIn(action)
    }

    func runCustom(_ scenario: CustomScenario) {
        actions.runCustom(scenario.id)
    }

    func restore() {
        actions.restore()
    }

    func toggleVoice() {
        actions.toggleVoice()
    }

    func configureAPIKey() {
        actions.configureAPIKey()
    }

    func requestAccessibility() {
        actions.requestAccessibility()
    }

    func requestScreenRecordingAccess() {
        actions.requestScreenRecordingAccess()
    }

    func requestMicrophoneAccess() {
        actions.requestMicrophoneAccess()
    }

    func requestSpeechRecognitionAccess() {
        actions.requestSpeechRecognitionAccess()
    }

    func openPrivacyPane(_ pane: PaneCuePrivacyPane) {
        actions.openPrivacyPane(pane)
    }

    func presentOnboarding() {
        refreshPermissions()
        isOnboardingPresented = true
    }

    func completeOnboarding() {
        defaults.set(
            Self.onboardingVersion,
            forKey: Self.onboardingVersionKey
        )
        isOnboardingPresented = false
        selectedSection = .arrange
    }

    func setAutoModeEnabled(_ enabled: Bool) {
        actions.setAutoModeEnabled(enabled)
    }

    func analyzeCommand(
        _ transcript: String,
        currentPlan: WorkspacePlan?
    ) async throws -> CommandLabAnalysis {
        let analysis = try await actions.analyzeCommand(
            transcript,
            currentPlan
        )
        arrangementPreview = await actions.arrangementState()?.preview
        return analysis
    }

    func prepareWorkspacePlan(
        _ plan: WorkspacePlan
    ) async throws {
        arrangementPreview = try await actions.prepareWorkspacePlan(plan)
    }

    func selectArrangementCandidate(
        previewID: UUID,
        slotID: UUID,
        candidateID: EphemeralWindowIdentifier
    ) async throws {
        arrangementPreview = try await actions.selectArrangementCandidate(
            previewID,
            slotID,
            candidateID
        )
    }

    func applyAnalyzedCommand(
        _ intent: VoiceCommandIntent
    ) async throws -> String {
        let summary = try await actions.applyAnalyzedCommand(intent)
        completeTextOnboarding()
        return summary
    }

    func applyWorkspacePlan(
        _ plan: WorkspacePlan
    ) async throws -> WorkspaceApplyResult {
        do {
            let result = try await actions.applyWorkspacePlan(plan)
            arrangementPreview = await actions.arrangementState()?.preview
            recordSuccessfulTextArrangement(result)
            return result
        } catch {
            arrangementPreview = await actions.arrangementState()?.preview
            throw error
        }
    }

    func rollbackLastApply() async throws -> String {
        let summary = try await actions.rollbackWorkspace()
        arrangementPreview = nil
        return summary
    }

    func saveCommandCorrection(
        transcript: String,
        intent: VoiceCommandIntent?
    ) {
        actions.saveCommandCorrection(
            transcript,
            intent
        )
    }

    func savePlanCorrection(
        transcript: String,
        plan: WorkspacePlan
    ) {
        actions.savePlanCorrection(transcript, plan)
    }

    func saveWorkspacePlan(
        _ plan: WorkspacePlan,
        name: String
    ) throws -> String {
        guard let scenario = plan.scenario(named: name) else {
            throw PaneCueWindowError.operationFailed(
                details: "A saved Cue needs a name and at least two windows."
            )
        }
        var updated = scenarios
        if let index = updated.firstIndex(where: {
            $0.name.caseInsensitiveCompare(scenario.name)
                == .orderedSame
        }) {
            var replacement = scenario
            replacement.id = updated[index].id
            updated[index] = replacement
        } else {
            updated.append(scenario)
        }
        store.replaceAll(with: updated)
        scenarios = store.scenarios
        editorRevision += 1
        actions.scenariosDidChange()
        return "Saved “\(scenario.name)”"
    }

    func startCommandLabListening() async throws {
        try await actions.startCommandLabListening()
    }

    func stopCommandLabListening() async throws -> String {
        try await actions.stopCommandLabListening()
    }

    func cancelCommandLabListening() {
        actions.cancelCommandLabListening()
    }

    func makeDiagnosticsReport() -> String {
        actions.makeDiagnosticsReport()
    }

    @discardableResult
    func resetPersonalization() -> Int {
        actions.resetPersonalization()
    }

    @discardableResult
    func clearApplyHistory() throws -> Int {
        try actions.clearApplyHistory()
    }

    func recordSuccessfulTextArrangement(
        _ result: WorkspaceApplyResult
    ) {
        guard result.didChangeAnyWindow else {
            return
        }
        completeTextOnboarding()
    }

    private func completeTextOnboarding() {
        guard !hasCompletedTextOnboarding else {
            return
        }
        defaults.set(true, forKey: Self.textOnboardingKey)
        hasCompletedTextOnboarding = true
    }
}

@MainActor
final class MainWindowController {
    let model: PaneCueDashboardModel

    private let windowController: NSWindowController
    private var restoredSavedFrame = false
    private var scheduledInitialFrameValidation = false
    private var validatedInitialFrame = false

    init(
        store: CustomScenarioStore,
        featureProvider: any PaneCueFeatureProvider,
        aiSettings: AIEngineSettingsStore,
        connectivity: ConnectivityMonitor,
        offlinePack: OfflinePackManager,
        actions: PaneCueDashboardActions
    ) {
        model = PaneCueDashboardModel(
            store: store,
            featureProvider: featureProvider,
            aiSettings: aiSettings,
            connectivity: connectivity,
            offlinePack: offlinePack,
            actions: actions
        )

        let rootView = PaneCueDashboardView(model: model)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 1_020,
                height: 680
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "PaneCue"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 860, height: 570)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        let frameAutosaveName =
            PaneCuePersistenceKey.mainWindowFrameAutosaveName
        restoredSavedFrame = window.setFrameUsingName(
            frameAutosaveName
        )
        window.setFrameAutosaveName(frameAutosaveName)

        windowController = NSWindowController(window: window)
    }

    func show(
        section: PaneCueDashboardSection = .arrange
    ) {
        if section == .cues {
            model.openScenarios()
        } else {
            model.selectedSection = section
        }
        model.refreshPermissions()

        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        if let window = windowController.window {
            window.makeKeyAndOrderFront(nil)
            scheduleInitialFrameValidation(of: window)
        }
    }

    func show(preview: ArrangementPreview) {
        model.stageArrangementPreviewForEditor(preview)
        show(section: .arrange)
    }

    func update(_ snapshot: PaneCueDashboardSnapshot) {
        model.update(snapshot)
    }

    func refreshPermissions() {
        model.refreshPermissions()
    }

    private func scheduleInitialFrameValidation(of window: NSWindow) {
        guard !scheduledInitialFrameValidation,
              !validatedInitialFrame else {
            return
        }
        scheduledInitialFrameValidation = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self,
                  let window else {
                return
            }
            self.validateInitialFrame(of: window)
        }
    }

    private func validateInitialFrame(of window: NSWindow) {
        guard !validatedInitialFrame,
              let primaryScreen = NSScreen.screens.first else {
            return
        }
        validatedInitialFrame = true

        if restoredSavedFrame {
            let targetScreen = NSScreen.screens.max {
                ScreenGeometry.overlapArea($0.visibleFrame, window.frame)
                    < ScreenGeometry.overlapArea($1.visibleFrame, window.frame)
            }
            if let targetScreen,
               ScreenGeometry.overlapArea(targetScreen.visibleFrame, window.frame) > 0 {
                window.setFrame(
                    ScreenGeometry.containedFrame(
                        window.frame,
                        in: targetScreen.visibleFrame
                    ),
                    display: false
                )
                return
            }
        }

        window.setFrame(
            ScreenGeometry.centeredFrame(
                windowSize: window.frame.size,
                in: primaryScreen.visibleFrame
            ),
            display: false
        )
    }
}

private enum PaneCueBuiltInScenario: CaseIterable, Identifiable {
    case codeAndCall
    case documentationAndCode
    case notesAndBrowser
    case browserVideo

    var id: Self {
        self
    }

    var action: VoiceCommandAction {
        switch self {
        case .codeAndCall:
            return .applyCodeAndCall
        case .documentationAndCode:
            return .applyDocumentationAndCode
        case .notesAndBrowser:
            return .applyNotesAndBrowser
        case .browserVideo:
            return .showBrowserVideo
        }
    }

    var title: String {
        switch self {
        case .codeAndCall:
            return "Code + Call"
        case .documentationAndCode:
            return "Documentation + Code"
        case .notesAndBrowser:
            return "Notes + Browser"
        case .browserVideo:
            return "Browser Video"
        }
    }

    var detail: String {
        switch self {
        case .codeAndCall:
            return "Keep the editor dominant and float the call video."
        case .documentationAndCode:
            return "Place reference material beside your code."
        case .notesAndBrowser:
            return "Research in the browser and capture notes alongside it."
        case .browserVideo:
            return "Extract the player from the active browser window."
        }
    }

    var systemImage: String {
        switch self {
        case .codeAndCall:
            return "video.badge.ellipsis"
        case .documentationAndCode:
            return "book.pages"
        case .notesAndBrowser:
            return "note.text"
        case .browserVideo:
            return "play.rectangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .codeAndCall:
            return .purple
        case .documentationAndCode:
            return .blue
        case .notesAndBrowser:
            return .orange
        case .browserVideo:
            return .pink
        }
    }
}

private struct PaneCueDashboardView: View {
    @ObservedObject var model: PaneCueDashboardModel

    var body: some View {
        Group {
            if model.isOnboardingPresented {
                PaneCueOnboardingView(model: model)
            } else {
                dashboard
            }
        }
        .frame(minWidth: 860, minHeight: 570)
    }

    private var dashboard: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: 188,
                    ideal: 212,
                    max: 240
                )
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color.accentColor.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(
                PaneCueDashboardSection.allCases,
                selection: $model.selectedSection
            ) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            model.hasAccessibilityPermission
                                ? Color.green
                                : Color.orange
                        )
                        .frame(width: 8, height: 8)
                    Text(
                        model.hasAccessibilityPermission
                            ? "Window control ready"
                            : "Permission needed"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if PaneCueReleaseProfile.current.isExperimental {
                    Button {
                        model.toggleVoice()
                    } label: {
                        Label(
                            model.voiceState == .listening
                                ? "Run Voice Command"
                                : "Voice Command",
                            systemImage: model.voiceState == .listening
                                ? "waveform"
                                : "mic"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.voiceState == .processing)

                    Text("Quick Cue · ⌥ Space")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    Button {
                        model.startNewArrangement()
                    } label: {
                        Label("New Arrangement", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .arrange:
            CommandLabView(model: model)
                .id(model.arrangementRevision)
        case .cues:
            ScenarioEditorView(
                initialScenarios: model.scenarios,
                applications: model.applications,
                onSave: { model.saveScenarios($0) },
                onClose: {
                    model.selectedSection = .arrange
                }
            )
            .id(model.editorRevision)
        case .settings:
            PaneCueSettingsView(
                model: model,
                aiSettings: model.aiSettings,
                connectivity: model.connectivity,
                offlinePack: model.offlinePack
            )
        }
    }
}

private struct PaneCueOverviewView: View {
    @ObservedObject var model: PaneCueDashboardModel
    @State private var brandIconRevision = UUID()

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                statusRow
                AutoModeCard(model: model)

                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle(
                        "Quick Cues",
                        detail: "One click arranges the workspace."
                    )

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(PaneCueBuiltInScenario.allCases) { scenario in
                            BuiltInScenarioCard(scenario: scenario) {
                                model.runBuiltIn(scenario.action)
                            }
                        }
                    }
                }

                customScenarios
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 34)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .paneCueAppIconDidChange
            )
        ) { _ in
            brandIconRevision = UUID()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: PaneCueBrandAssets.appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .id(brandIconRevision)
                .frame(width: 62, height: 62)
                .shadow(
                    color: Color.blue.opacity(0.2),
                    radius: 14,
                    y: 7
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("PaneCue")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Your workspace, ready for what comes next.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.canRestore {
                Button {
                    model.restore()
                } label: {
                    Label("Restore Layout", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            StatusChip(
                title: "Window Control",
                detail: model.hasAccessibilityPermission
                    ? "Ready"
                    : "Needs access",
                systemImage: "macwindow",
                tint: model.hasAccessibilityPermission ? .green : .orange
            )
            StatusChip(
                title: "Voice",
                detail: model.hasAPIKey
                    ? (
                        model.hasMicrophonePermission
                            ? "Ready"
                            : "Key saved"
                    )
                    : "Setup needed",
                systemImage: "waveform",
                tint: model.hasAPIKey ? .blue : .orange
            )
            StatusChip(
                title: "Video",
                detail: model.hasScreenRecordingPermission
                    ? "Ready"
                    : "Needs access",
                systemImage: "play.rectangle",
                tint: model.hasScreenRecordingPermission ? .pink : .orange
            )
        }
    }

    @ViewBuilder
    private var customScenarios: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(
                    "Cues",
                    detail: model.scenarios.isEmpty
                        ? "Create a workspace around your own apps."
                        : "\(model.scenarios.count) saved"
                )

                Spacer()

                Button {
                    model.openScenarios()
                } label: {
                    Label(
                        model.scenarios.isEmpty ? "Create" : "Edit",
                        systemImage: model.scenarios.isEmpty
                            ? "plus"
                            : "slider.horizontal.3"
                    )
                }
            }

            if model.scenarios.isEmpty {
                Button {
                    model.openScenarios()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Build your first Cue")
                                .font(.headline)
                            Text(
                                "Choose two applications and decide how much space each one gets."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08))
                }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.scenarios) { scenario in
                        CustomScenarioCard(scenario: scenario) {
                            model.runCustom(scenario)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(
        _ title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BuiltInScenarioCard: View {
    let scenario: PaneCueBuiltInScenario
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: scenario.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(scenario.tint)
                        .frame(width: 38, height: 38)
                        .background(
                            scenario.tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 11)
                        )

                    Spacer()

                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scenario.tint)
                        .frame(width: 30, height: 30)
                        .background(
                            scenario.tint.opacity(0.1),
                            in: Circle()
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(scenario.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(scenario.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(scenario.tint.opacity(0.16))
        }
    }
}

private struct CustomScenarioCard: View {
    let scenario: CustomScenario
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ScenarioMiniature(windows: scenario.windows)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(
                        "\(scenario.windows.count) windows · \(scenario.windows.map(\.target.displayName).joined(separator: " + "))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08))
        }
    }
}

private struct ScenarioMiniature: View {
    let windows: [ScenarioWindowSlot]

    private var visibleWindows: [ScenarioWindowSlot] {
        let main = windows.filter { $0.display == .main }
        return main.isEmpty ? windows : main
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.07))

                ForEach(
                    Array(visibleWindows.enumerated()),
                    id: \.element.id
                ) { index, window in
                    let rect = window.gridRect.normalized
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            Color.accentColor.opacity(
                                index == 0 ? 0.9 : 0.28
                            )
                        )
                        .frame(
                            width: max(
                                geometry.size.width * rect.width - 2,
                                3
                            ),
                            height: max(
                                geometry.size.height * rect.height - 2,
                                3
                            )
                        )
                        .position(
                            x: geometry.size.width
                                * (rect.x + rect.width / 2),
                            y: geometry.size.height
                                * (rect.y + rect.height / 2)
                        )
                }
            }
        }
        .frame(width: 52, height: 34)
    }
}

private struct StatusChip: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 13)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.07))
        }
    }
}

private struct AutoModeCard: View {
    @ObservedObject var model: PaneCueDashboardModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(
                    Color.purple.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 13)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Auto Mode")
                        .font(.headline)
                    Text(model.isAutoModeEnabled ? "WATCHING" : "OFF")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(
                            model.isAutoModeEnabled
                                ? Color.purple
                                : Color.secondary
                        )
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            (
                                model.isAutoModeEnabled
                                    ? Color.purple
                                    : Color.secondary
                            )
                            .opacity(0.1),
                            in: Capsule()
                        )
                }

                Text(
                    "Suggests a layout from the apps you switch between. Nothing moves until you approve it."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { model.isAutoModeEnabled },
                    set: { model.setAutoModeEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.large)
        }
        .padding(18)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.purple.opacity(0.16))
        }
    }
}

private struct PaneCueSettingsView: View {
    @ObservedObject var model: PaneCueDashboardModel
    @ObservedObject var aiSettings: AIEngineSettingsStore
    @ObservedObject var connectivity: ConnectivityMonitor
    @ObservedObject var offlinePack: OfflinePackManager
    @State private var diagnosticsReport: String?
    @State private var isResetConfirmationPresented = false
    @State private var isClearHistoryConfirmationPresented = false
    @State private var privacyActionMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(
                        "PaneCue asks only when a feature needs access. Nothing is requested at launch."
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                }

                SettingsGroup(
                    title: "Permissions",
                    detail: "Access stays under your control in macOS."
                ) {
                    PermissionRow(
                        title: "Window Control",
                        detail: "Arrange and restore application windows",
                        systemImage: "macwindow",
                        isGranted: model.hasAccessibilityPermission,
                        actionTitle: "Grant Access"
                    ) {
                        model.requestAccessibility()
                    }

                    if PaneCueReleaseProfile.current.isExperimental {
                        Divider()

                        PermissionRow(
                            title: "Screen Recording",
                            detail: "Extract call and browser video",
                            systemImage: "record.circle",
                            isGranted: model.hasScreenRecordingPermission,
                            actionTitle: "Grant Access"
                        ) {
                            model.requestScreenRecordingAccess()
                        }
                    }

                    Divider()

                    PermissionRow(
                        title: "Microphone",
                        detail: "Listen only while a voice command is active",
                        systemImage: "mic",
                        isGranted: model.hasMicrophonePermission,
                        actionTitle: model.microphoneActionTitle
                    ) {
                        model.requestMicrophoneAccess()
                    }

                    Divider()

                    PermissionRow(
                        title: "Speech Recognition",
                        detail: "Transcribe commands locally without internet",
                        systemImage: "waveform.and.mic",
                        isGranted: model.hasSpeechRecognitionPermission,
                        actionTitle: model.speechRecognitionActionTitle
                    ) {
                        model.requestSpeechRecognitionAccess()
                    }

                    if PaneCueReleaseProfile.current.isExperimental {
                        Divider()

                        SettingRow(
                            title: "Guided Setup",
                            detail: "Review experimental permissions one at a time",
                            systemImage: "checklist",
                            statusColor: .blue
                        ) {
                            Button("Run Setup…") {
                                model.presentOnboarding()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if PaneCueReleaseProfile.current.isExperimental {
                    SettingsGroup(
                        title: "AI Processing · Experimental",
                        detail: "Choose when PaneCue Experimental may use the cloud."
                    ) {
                    SettingRow(
                        title: "Processing Mode",
                        detail: aiSettings.processingMode.detail,
                        systemImage: processingModeIcon,
                        statusColor: processingModeColor
                    ) {
                        Picker(
                            "Processing Mode",
                            selection: $aiSettings.processingMode
                        ) {
                            ForEach(
                                AIProcessingMode.allCases,
                                id: \.self
                            ) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 175)
                    }

                    Divider()

                    SettingRow(
                        title: "Connection",
                        detail: connectivity.isOnline
                            ? "Cloud services are available"
                            : "PaneCue will remain fully local",
                        systemImage: connectivity.isOnline
                            ? "network"
                            : "network.slash",
                        statusColor: connectivity.isOnline
                            ? .green
                            : .blue
                    ) {
                        Text(connectivity.isOnline ? "Online" : "Offline")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(
                                connectivity.isOnline ? .green : .blue
                            )
                    }

                    Divider()

                    SettingRow(
                        title: "Local Command Model",
                        detail: aiSettings.localCommandModel.detail,
                        systemImage: "cpu",
                        statusColor: .blue
                    ) {
                        Picker(
                            "Local Command Model",
                            selection: $aiSettings.localCommandModel
                        ) {
                            ForEach(
                                LocalCommandModel.allCases,
                                id: \.self
                            ) { localModel in
                                Text(localModel.displayName)
                                    .tag(localModel)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 175)
                        .disabled(aiSettings.processingMode == .cloud)
                    }

                    Divider()

                    SettingRow(
                        title: "Offline Pack",
                        detail: offlinePack.statusText,
                        systemImage: "internaldrive",
                        statusColor: offlinePackColor
                    ) {
                        offlinePackControl
                    }
                    }

                    SettingsGroup(
                        title: "Cloud Voice · Experimental",
                        detail: "Use Russian or English from the Voice Command control."
                    ) {
                    SettingRow(
                        title: "OpenAI API Key",
                        detail: model.hasAPIKey
                            ? "Saved securely in macOS Keychain"
                            : "Required only for Cloud mode",
                        systemImage: "key.fill",
                        statusColor: model.hasAPIKey ? .green : .orange
                    ) {
                        Button(model.hasAPIKey ? "Replace…" : "Add Key…") {
                            model.configureAPIKey()
                        }
                    }

                    Divider()

                    SettingRow(
                        title: "Voice Model",
                        detail: voiceModelDetail,
                        systemImage: "waveform.badge.sparkles",
                        statusColor: .purple
                    ) {
                        Text(voiceModelName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    }
                } else {
                    SettingsGroup(
                        title: "Local Intelligence",
                        detail: "The stable build processes arrangement commands on this Mac."
                    ) {
                        SettingRow(
                            title: "Processing",
                            detail: "No command text or window data is sent over the network",
                            systemImage: "lock.laptopcomputer",
                            statusColor: .green
                        ) {
                            Text("Offline Only")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.green)
                        }

                        Divider()

                        SettingRow(
                            title: "Command Model",
                            detail: "Bundled, lightweight parser for Russian and English",
                            systemImage: "cpu",
                            statusColor: .blue
                        ) {
                            Text("PaneCue Mini v2")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsGroup(
                    title: "Privacy & Local Data",
                    detail: "Nothing is transmitted automatically."
                ) {
                    SettingRow(
                        title: "Diagnostics",
                        detail: "Preview a sanitized local report before exporting it",
                        systemImage: "stethoscope",
                        statusColor: .blue
                    ) {
                        Button("Preview…") {
                            diagnosticsReport = model.makeDiagnosticsReport()
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    SettingRow(
                        title: "Clear Apply History",
                        detail: "Remove the local recovery records for the last five Apply operations",
                        systemImage: "clock.arrow.circlepath",
                        statusColor: .orange
                    ) {
                        Button("Clear…", role: .destructive) {
                            isClearHistoryConfirmationPresented = true
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    SettingRow(
                        title: "Reset Personalization",
                        detail: "Remove command corrections and local learning; Cues stay saved",
                        systemImage: "arrow.counterclockwise.circle",
                        statusColor: .orange
                    ) {
                        Button("Reset…", role: .destructive) {
                            isResetConfirmationPresented = true
                        }
                        .buttonStyle(.bordered)
                    }

                    if !privacyActionMessage.isEmpty {
                        Divider()
                        Text(privacyActionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                    }
                }

                SettingsGroup(
                    title: "App Behavior",
                    detail: "Fast access stays available when the window is closed."
                ) {
                    SettingRow(
                        title: "Quick Cue Shortcut",
                        detail: model.quickCueShortcutStatus.detail,
                        systemImage: "keyboard",
                        statusColor: quickCueShortcutColor
                    ) {
                        HStack(spacing: 9) {
                            Text(model.quickCueShortcutStatus.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(quickCueShortcutColor)
                            Text("⌥ Space")
                                .font(.body.monospaced().weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "Quick Cue shortcut, "
                                + model.quickCueShortcutStatus.title
                                + ", Option Space"
                        )
                    }

                    Divider()

                    if PaneCueReleaseProfile.current.isExperimental {
                        SettingRow(
                            title: "Suggestions Beta",
                            detail: "Suggest layouts locally and wait for approval",
                            systemImage: "sparkles.rectangle.stack",
                            statusColor: model.isAutoModeEnabled
                                ? .purple
                                : .secondary
                        ) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { model.isAutoModeEnabled },
                                    set: { model.setAutoModeEnabled($0) }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        Divider()
                    }

                    SettingRow(
                        title: "Menu Bar",
                        detail: "The PaneCue icon remains in the top bar",
                        systemImage: "menubar.rectangle",
                        statusColor: .blue
                    ) {
                        Label("Always On", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }

                Button("Refresh Status") {
                    model.refreshPermissions()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 840, alignment: .leading)
        }
        .sheet(
            isPresented: Binding(
                get: { diagnosticsReport != nil },
                set: { if !$0 { diagnosticsReport = nil } }
            )
        ) {
            DiagnosticsPreviewView(
                report: diagnosticsReport ?? ""
            )
        }
        .alert(
            "Reset Personalization?",
            isPresented: $isResetConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                let removedCount = model.resetPersonalization()
                privacyActionMessage = removedCount == 0
                    ? "Personalization was already empty."
                    : "Removed \(removedCount) saved correction\(removedCount == 1 ? "" : "s")."
            }
        } message: {
            Text(
                "This removes saved command corrections and local learning. Your Cues, permissions, and API key are not changed."
            )
        }
        .alert(
            "Clear Apply History?",
            isPresented: $isClearHistoryConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                do {
                    let removedCount = try model.clearApplyHistory()
                    privacyActionMessage = removedCount == 0
                        ? "Apply history was already empty."
                        : "Removed \(removedCount) Apply record\(removedCount == 1 ? "" : "s")."
                } catch {
                    privacyActionMessage =
                        "PaneCue could not clear Apply history."
                }
            }
        } message: {
            Text(
                "This removes only local window recovery records. Your Cues, permissions, personalization, and API key are not changed."
            )
        }
    }

    private var quickCueShortcutColor: Color {
        switch model.quickCueShortcutStatus {
        case .active:
            return .green
        case .conflict:
            return .orange
        case .unavailable:
            return .red
        }
    }

    private var processingModeIcon: String {
        switch aiSettings.processingMode {
        case .automatic:
            return "arrow.triangle.branch"
        case .offline:
            return "lock.laptopcomputer"
        case .cloud:
            return "cloud"
        }
    }

    private var processingModeColor: Color {
        switch aiSettings.processingMode {
        case .automatic:
            return .purple
        case .offline:
            return .blue
        case .cloud:
            return .cyan
        }
    }

    private var offlinePackColor: Color {
        switch offlinePack.state {
        case .ready:
            return .green
        case .downloading, .checking:
            return .blue
        case .notInstalled, .runtimeUnavailable, .failed:
            return .orange
        }
    }

    @ViewBuilder
    private var offlinePackControl: some View {
        switch offlinePack.state {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .notInstalled:
            Button("Prepare…") {
                offlinePack.prepare()
            }
            .buttonStyle(.borderedProminent)
        case .runtimeUnavailable:
            Text("Unavailable")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        case .failed:
            Button("Retry") {
                offlinePack.prepare()
            }
            .buttonStyle(.bordered)
        }
    }

    private var voiceModelName: String {
        switch aiSettings.processingMode {
        case .automatic:
            return "Automatic"
        case .offline:
            return aiSettings.localCommandModel.displayName
        case .cloud:
            return "gpt-realtime-2.1-mini"
        }
    }

    private var voiceModelDetail: String {
        switch aiSettings.processingMode {
        case .automatic:
            return "OpenAI online, local models when the network is unavailable"
        case .offline:
            return "No audio or command text leaves this Mac"
        case .cloud:
            return "Local models remain unloaded from memory"
        }
    }
}

private struct DiagnosticsPreviewView: View {
    let report: String

    @Environment(\.dismiss) private var dismiss
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background(
                        Color.blue.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics Preview")
                        .font(.title2.weight(.semibold))
                    Text(
                        "Review the complete report. No file is created until you press Export."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(22)

            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
                .background(Color(nsColor: .textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1))
                }
                .padding(.horizontal, 22)

            Label(
                "No window titles, application names, bundle identifiers, URLs, or document paths are included.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.top, 12)

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                Button {
                    export()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(22)
        }
        .frame(width: 720, height: 620)
        .alert(
            "Diagnostics Export Failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                exportError = nil
            }
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export PaneCue Diagnostics"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PaneCue-Diagnostics.json"

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            try Data(report.utf8).write(to: url, options: .atomic)
            dismiss()
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08))
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        SettingRow(
            title: title,
            detail: detail,
            systemImage: systemImage,
            statusColor: isGranted ? .green : .orange
        ) {
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let statusColor: Color
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 34, height: 34)
                .background(statusColor.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            trailing
        }
        .padding(.vertical, 13)
    }
}
