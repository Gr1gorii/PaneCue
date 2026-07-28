import Foundation
import Testing
@testable import PaneCueApp
import PaneCueExperimentalFeatures

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
    }

    @Test
    func experimentalFeatureTargetCanBeLoadedIndependently() {
        PaneCueExperimentalFeatureSet.prepareForLaunch()
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
