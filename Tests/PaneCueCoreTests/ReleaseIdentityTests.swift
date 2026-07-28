import Foundation
import Testing
@testable import PaneCueCore

@Suite("Release identity")
struct ReleaseIdentityTests {
    @Test
    func stableBundleUsesV02Identity() throws {
        let plist = try infoPlist(named: "Info.plist")

        #expect(plist["CFBundleShortVersionString"] as? String == "0.2.0")
        #expect(plist["CFBundleVersion"] as? String == "14")
        #expect(
            plist["CFBundleIdentifier"] as? String
                == PaneCueIdentity.bundleIdentifier
        )
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
    }

    @Test
    func experimentalBundleKeepsTheSameReleaseNumber() throws {
        let plist = try infoPlist(named: "Info-Experimental.plist")

        #expect(plist["CFBundleShortVersionString"] as? String == "0.2.0")
        #expect(plist["CFBundleVersion"] as? String == "14")
        #expect(
            plist["CFBundleIdentifier"] as? String
                == "io.github.gr1gorii.PaneCue.experimental"
        )
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
    }

    @Test
    func diagnosticsIdentityReadsBundleVersionAndBuild() {
        let identity = PaneCueReleaseIdentity(infoDictionary: [
            "CFBundleShortVersionString": "0.2.0",
            "CFBundleVersion": "14"
        ])

        #expect(identity.version == "0.2.0")
        #expect(identity.build == "14")
    }

    @Test
    func diagnosticsIdentityHasSafeDevelopmentFallback() {
        let identity = PaneCueReleaseIdentity(infoDictionary: nil)

        #expect(identity.version == "development")
        #expect(identity.build == "development")
    }

    @Test
    func v01PersistenceKeysRemainStable() {
        #expect(
            PaneCuePersistenceKey.customScenarios
                == "PaneCue.customScenarios.v2"
        )
        #expect(
            PaneCuePersistenceKey.legacyCustomScenarios
                == "PaneCue.customScenarios.v1"
        )
        #expect(
            PaneCuePersistenceKey.commandCorrections
                == "PaneCue.CommandLabCorrections.v1"
        )
        #expect(
            PaneCuePersistenceKey.processingMode
                == "PaneCue.AIProcessingMode"
        )
        #expect(
            PaneCuePersistenceKey.localCommandModel
                == "PaneCue.LocalCommandModel"
        )
        #expect(
            PaneCuePersistenceKey.onboardingCompletedVersion
                == "PaneCue.Onboarding.completedVersion"
        )
        #expect(
            PaneCuePersistenceKey.completedFirstApply
                == "PaneCue.Arrange.completedFirstApply"
        )
        #expect(
            PaneCuePersistenceKey.mainWindowFrameAutosaveName
                == "PaneCue.MainWindow"
        )
    }

    @Test
    func persistedAISettingsRawValuesRemainDecodable() {
        #expect(AIProcessingMode(rawValue: "automatic") == .automatic)
        #expect(AIProcessingMode(rawValue: "offline") == .offline)
        #expect(AIProcessingMode(rawValue: "cloud") == .cloud)
        #expect(LocalCommandModel(rawValue: "smart") == .smart)
        #expect(
            LocalCommandModel(rawValue: "functionGemma")
                == .functionGemma
        )
        #expect(LocalCommandModel(rawValue: "qwen") == .qwen)
    }

    @Test
    func sourceLicenseRemainsMPL2() throws {
        let licenseURL = repositoryRoot.appendingPathComponent("LICENSE")
        let license = try String(contentsOf: licenseURL, encoding: .utf8)

        #expect(license.hasPrefix("Mozilla Public License Version 2.0"))
    }

    private func infoPlist(named name: String) throws -> [String: Any] {
        let url = repositoryRoot
            .appendingPathComponent("Resources")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try #require(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
