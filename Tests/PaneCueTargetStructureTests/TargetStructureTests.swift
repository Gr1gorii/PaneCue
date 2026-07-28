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
