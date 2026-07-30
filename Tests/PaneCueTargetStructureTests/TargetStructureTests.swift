import AppKit
import Foundation
import Testing
@testable import PaneCueApp
@testable import PaneCueExperimentalFeatures

@Suite("SwiftPM target structure")
struct TargetStructureTests {
    @Test
    func stableExecutableHasNoExperimentalDependency() throws {
        let manifest = try sourceText(at: "Package.swift")
            .replacingOccurrences(
                of: #"\s+"#,
                with: "",
                options: .regularExpression
            )

        #expect(
            manifest.contains(
                #".executableTarget(name:"PaneCue",dependencies:["PaneCueApp"])"#
            )
        )
        #expect(
            !manifest.contains(
                #".executableTarget(name:"PaneCue",dependencies:["PaneCueExperimentalFeatures"]"#
            )
        )
        #expect(
            !manifest.contains(
                #".executableTarget(name:"PaneCue",dependencies:["PaneCueBenchmarkKit"]"#
            )
        )
    }

    @Test
    func dialogueBenchmarkRemainsExternalAndAggregateOnly() throws {
        let manifest = try sourceText(at: "Package.swift")
        let ignore = try sourceText(at: ".gitignore")
        let runner = try sourceText(
            at: "Sources/PaneCueDialogueBenchmark/main.swift"
        )
        let ci = try sourceText(at: ".github/workflows/ci.yml")

        #expect(manifest.contains("PaneCueDialogueBenchmark"))
        #expect(manifest.contains("PaneCueBenchmarkKit"))
        #expect(ignore.contains(".panecue-evaluation/"))
        #expect(runner.contains("corpusMustBeExternal"))
        #expect(!runner.contains("utterance"))
        #expect(ci.contains("PaneCueDialogueBenchmark"))
    }

    @Test
    func quickCueShortcutStaysEphemeralAndLocal() throws {
        let appDelegate = try sourceText(
            at: "Sources/PaneCueApp/AppDelegate.swift"
        )
        let panel = try sourceText(
            at: "Sources/PaneCueApp/QuickCuePanelController.swift"
        )
        let session = try sourceText(
            at: "Sources/PaneCueApp/QuickCuePanelSession.swift"
        )

        #expect(appDelegate.contains("self?.quickCue.present()"))
        #expect(panel.contains("NSApp.activate(ignoringOtherApps: true)"))
        #expect(panel.contains("panel.makeKeyAndOrderFront(nil)"))
        #expect(panel.contains("panel.makeFirstResponder(commandField)"))
        #expect(panel.contains("cancelOperation"))
        #expect(!panel.contains("UserDefaults"))
        #expect(!panel.contains("Logger"))
        #expect(!session.contains("UserDefaults"))
        #expect(!session.contains("Logger"))
    }

    @Test
    func experimentalImplementationsLiveOutsideStableSources() {
        let stableSources = repositoryRoot
            .appendingPathComponent("Sources/PaneCueApp")
        let experimentalSources = repositoryRoot
            .appendingPathComponent("Sources/PaneCueExperimentalFeatures")
        let experimentalFiles = [
            "AutoModeController.swift",
            "AutoModeSuggestionPanelController.swift",
            "CallVideoPreviewController.swift",
            "ChromeVideoSessionController.swift",
            "ExperimentalPaneCueFeatureProvider.swift",
            "ExperimentalOfflinePackManager.swift",
            "OllamaLocalCommandService.swift",
            "OpenAIAPIKeySettingsController.swift",
            "OpenAIAPIKeyStore.swift",
            "RealtimeVoiceCommandController.swift"
        ]

        for file in experimentalFiles {
            #expect(
                !FileManager.default.fileExists(
                    atPath: stableSources
                        .appendingPathComponent(file)
                        .path
                )
            )
            #expect(
                FileManager.default.fileExists(
                    atPath: experimentalSources
                        .appendingPathComponent(file)
                        .path
                )
            )
        }
    }

    @Test
    func executablesHaveIndependentBootstraps() throws {
        let stableMain = try sourceText(at: "Sources/PaneCue/main.swift")
        let experimentalMain = try sourceText(
            at: "Sources/PaneCueExperimental/main.swift"
        )

        #expect(stableMain.contains("import PaneCueApp"))
        #expect(!stableMain.contains("PaneCueExperimentalFeatures"))
        #expect(
            experimentalMain.contains(
                "import PaneCueExperimentalFeatures"
            )
        )
        #expect(
            experimentalMain.contains(
                "ExperimentalPaneCueFeatureProvider()"
            )
        )
    }

    @Test
    @MainActor
    func providersExposeDifferentCapabilityProfiles() {
        let stable = StablePaneCueFeatureProvider()
        let experimental = ExperimentalPaneCueFeatureProvider()

        #expect(!stable.isExperimental)
        #expect(stable.voiceState == .idle)
        #expect(!stable.isVideoCaptureActive)
        #expect(stable.diagnostics.profile == "Main")
        #expect(experimental.isExperimental)
        #expect(experimental.voiceState == .idle)
        #expect(experimental.diagnostics.profile == "Experimental")
    }

    @Test
    @MainActor
    func stableProviderRejectsExperimentalWork() async {
        let stable = StablePaneCueFeatureProvider()
        var rejectedVoice = false
        var rejectedCall = false

        do {
            try await stable.startVoiceListening()
        } catch {
            rejectedVoice = true
        }
        do {
            _ = try await stable.startCallCapture()
        } catch {
            rejectedCall = true
        }

        #expect(rejectedVoice)
        #expect(rejectedCall)
        #expect(!stable.isVideoCaptureActive)
    }

    @Test
    @MainActor
    func stableProviderContributesNoExperimentalMenuItems() {
        let stable = StablePaneCueFeatureProvider()
        let menu = NSMenu()

        stable.installStatusMenuItems(in: menu)
        stable.refreshStatusMenuItems()

        #expect(menu.items.isEmpty)
    }

    @Test
    @MainActor
    func experimentalProviderKeepsItsFeatureMenuItems() {
        let experimental = ExperimentalPaneCueFeatureProvider()
        let menu = NSMenu()

        experimental.installStatusMenuItems(in: menu)

        let titles = menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)
        #expect(titles.contains("OpenAI API Key…"))
        #expect(titles.contains("Start Voice Command"))
        #expect(titles.contains("Suggestions Beta"))
        #expect(titles.contains("Code + Call"))
        #expect(titles.contains("Documentation + Code"))
        #expect(titles.contains("Notes + Browser"))
        #expect(titles.contains("Browser Video"))
    }

    @Test
    func stableAppHasNoForbiddenImplementationReferences() throws {
        let stableDirectory = repositoryRoot
            .appendingPathComponent("Sources/PaneCueApp")
        let files = try FileManager.default.contentsOfDirectory(
            at: stableDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let source = try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let forbiddenReferences = [
            "RealtimeVoiceCommandController",
            "ChromeVideoSessionController",
            "CallVideoPreviewController",
            "OllamaLocalCommandService",
            "OpenAIAPIKeyStore",
            "OpenAIAPIKeySettingsController",
            "ScreenCaptureKit",
            "api.openai.com",
            "localhost:11434",
            "osascript"
        ]

        for reference in forbiddenReferences {
            #expect(!source.contains(reference))
        }

        let appDelegate = try sourceText(
            at: "Sources/PaneCueApp/AppDelegate.swift"
        )
        let experimentalSelectors = [
            "#selector(configureCloudAccess)",
            "#selector(toggleVoiceCommand)",
            "#selector(toggleAutoMode)",
            "#selector(applyCodeAndCall)",
            "#selector(showBrowserVideo)"
        ]
        for selector in experimentalSelectors {
            #expect(!appDelegate.contains(selector))
        }
    }

    @Test
    func binarySeparationGateIsRequiredByCIAndAcceptance() throws {
        let gate = try sourceText(
            at: "scripts/verify_stable_binary_separation.sh"
        )
        let ci = try sourceText(at: ".github/workflows/ci.yml")
        let acceptance = try sourceText(
            at: "scripts/run_v01_acceptance.sh"
        )

        #expect(gate.contains("codesign -d --entitlements"))
        #expect(gate.contains("otool -L"))
        #expect(gate.contains("otool -ov"))
        #expect(gate.contains("wss://api.openai.com"))
        #expect(gate.contains("127.0.0.1:11434"))
        #expect(gate.contains("execute targetTab javascript"))
        #expect(ci.contains("verify_stable_binary_separation.sh"))
        #expect(acceptance.contains("verify_stable_binary_separation.sh"))
    }

    @Test
    func stableArrangementSourcesContainNoNetworkClient() throws {
        let directories = [
            repositoryRoot.appendingPathComponent("Sources/PaneCueCore"),
            repositoryRoot.appendingPathComponent("Sources/PaneCueApp")
        ]
        let files = try directories.flatMap { directory in
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "swift" }
        }
        let source = try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let requestAPIs = [
            "URLSession",
            "URLRequest",
            "NWConnection",
            "webSocketTask",
            "dataTask(with:"
        ]

        for requestAPI in requestAPIs {
            #expect(!source.contains(requestAPI))
        }
    }

    @Test
    func chromeCleanupOnlyUsesCurrentSessionOwnership() throws {
        let source = try sourceText(
            at: "Sources/PaneCueExperimentalFeatures/ChromeVideoSessionController.swift"
        )

        #expect(!source.contains("< -5000"))
        #expect(!source.contains("closeAbandonedSourceWindow"))
        #expect(!source.contains("every window whose given name"))
        #expect(source.contains("session.placeholderTabID"))
        #expect(source.contains("URL of placeholderTab starts with \"chrome://newtab\""))
    }

    @Test
    func ollamaOwnershipExcludesModelsAlreadyRunning() {
        var ownership = OllamaModelOwnership()

        ownership.recordPaneCueLoad(
            model: "shared-model:latest",
            priorPresence: .running
        )
        ownership.recordPaneCueLoad(
            model: "unknown-model:latest",
            priorPresence: .unknown
        )
        ownership.recordPaneCueLoad(
            model: "panecue-qwen3:1.0",
            priorPresence: .notRunning
        )

        #expect(!ownership.owns(model: "shared-model"))
        #expect(!ownership.owns(model: "unknown-model"))
        #expect(ownership.owns(model: "PANECUE-QWEN3:1.0"))
        #expect(ownership.modelNames == ["panecue-qwen3:1.0"])

        ownership.recordUnload(model: "panecue-qwen3:1.0")
        #expect(ownership.modelNames.isEmpty)
    }

    @Test
    @MainActor
    func terminationCleanupRunsOnlyOnce() async {
        let coordinator = PaneCueTerminationCoordinator()
        var cleanupCount = 0

        let first = coordinator.begin {
            cleanupCount += 1
        }
        let second = coordinator.begin {
            cleanupCount += 1
        }

        #expect(first.startedCleanup)
        #expect(!second.startedCleanup)
        await first.task.value
        await second.task.value
        #expect(cleanupCount == 1)
        #expect(coordinator.isComplete)
    }

    private func sourceText(at path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
