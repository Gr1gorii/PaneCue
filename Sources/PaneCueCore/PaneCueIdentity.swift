public enum PaneCueIdentity {
    public static let bundleIdentifier = "io.github.gr1gorii.PaneCue"

    public static func subsystem(_ component: String) -> String {
        "\(bundleIdentifier).\(component)"
    }
}

public struct PaneCueReleaseIdentity: Equatable, Sendable {
    public let version: String
    public let build: String

    public init(infoDictionary: [String: Any]?) {
        version = infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "development"
        build = infoDictionary?["CFBundleVersion"] as? String
            ?? "development"
    }
}

public enum PaneCuePersistenceKey {
    public static let customScenarios = "PaneCue.customScenarios.v2"
    public static let legacyCustomScenarios = "PaneCue.customScenarios.v1"
    public static let commandCorrections = "PaneCue.CommandLabCorrections.v1"
    public static let processingMode = "PaneCue.AIProcessingMode"
    public static let localCommandModel = "PaneCue.LocalCommandModel"
    public static let onboardingCompletedVersion =
        "PaneCue.Onboarding.completedVersion"
    public static let completedFirstApply =
        "PaneCue.Arrange.completedFirstApply"
    public static let mainWindowFrameAutosaveName = "PaneCue.MainWindow"
}
