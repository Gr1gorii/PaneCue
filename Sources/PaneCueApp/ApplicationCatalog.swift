import AppKit
import ApplicationServices
import PaneCueCore

struct InstalledApplication: Hashable, Identifiable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let url: URL

    var id: String {
        bundleIdentifier
    }

    var scenarioApplication: ScenarioApplication {
        ScenarioApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }
}

@MainActor
enum ApplicationCatalog {
    static func installedApplications() -> [InstalledApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]
        var applicationsByIdentifier: [String: InstalledApplication] = [:]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app")
                        == .orderedSame,
                      let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier,
                      !bundleIdentifier.isEmpty
                else {
                    continue
                }

                let displayName = (
                    bundle.object(
                        forInfoDictionaryKey: "CFBundleDisplayName"
                    ) as? String
                ) ?? (
                    bundle.object(
                        forInfoDictionaryKey: "CFBundleName"
                    ) as? String
                ) ?? url.deletingPathExtension().lastPathComponent

                applicationsByIdentifier[bundleIdentifier] =
                    InstalledApplication(
                        bundleIdentifier: bundleIdentifier,
                        displayName: displayName,
                        url: url
                    )
            }
        }

        for application in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = application.bundleIdentifier,
                  let url = application.bundleURL,
                  application.activationPolicy == .regular
            else {
                continue
            }

            applicationsByIdentifier[bundleIdentifier] =
                InstalledApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: application.localizedName
                        ?? url.deletingPathExtension().lastPathComponent,
                    url: url
                )
        }

        return applicationsByIdentifier.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                == .orderedAscending
        }
    }
}

enum ScenarioApplicationLauncherError: LocalizedError {
    case applicationNotInstalled(name: String)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case let .applicationNotInstalled(name):
            return "PaneCue could not find \(name) on this Mac. Choose another app in the scenario editor."
        case let .invalidURL(value):
            return "PaneCue could not open “\(value)”. Enter a valid http or https URL in the scenario editor."
        }
    }
}

@MainActor
final class ScenarioApplicationLauncher {
    private let preferredBundleIdentifiers: [ApplicationRole: [String]] = [
        .ide: [
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.apple.dt.Xcode",
            "com.exafunction.windsurf",
            "dev.zed.Zed"
        ],
        .meeting: [
            "com.apple.FaceTime",
            "us.zoom.xos",
            "com.microsoft.teams2",
            "com.microsoft.teams"
        ],
        .notes: [
            "com.apple.Notes",
            "notion.id",
            "md.obsidian",
            "net.shinyfrog.bear"
        ],
        .documentation: [
            "com.kapeli.dashdoc",
            "com.apple.Preview"
        ]
    ]

    func ensureApplications(for action: VoiceCommandAction) async throws {
        switch action {
        case .applyCodeAndCall:
            try await ensureRole(.ide)
            try await ensureRole(.meeting)
        case .applyDocumentationAndCode:
            try await ensureRole(.ide)
            try await ensureBrowserOrDocumentation()
        case .applyNotesAndBrowser:
            try await ensureRole(.notes)
            try await ensureRole(.browser)
        case .showBrowserVideo:
            try await ensureRole(.browser)
        case .arrangeDynamicWorkspace,
             .applyCustomScenario,
             .restorePreviousLayout:
            break
        }
    }

    func ensureApplications(for scenario: CustomScenario) async throws {
        for window in scenario.windows where window.launchIfNeeded {
            switch window.target.kind {
            case .application:
                if let application = window.target.application {
                    try await ensureApplication(application)
                }
            case .role:
                try await ensureRole(window.target.role ?? .other)
            }
        }

        for window in scenario.windows {
            let trimmedURL = window.urlString.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmedURL.isEmpty else {
                continue
            }
            guard let url = Self.webURL(from: trimmedURL) else {
                throw ScenarioApplicationLauncherError.invalidURL(trimmedURL)
            }
            try await open(url, for: window.target)
        }
    }

    private func ensureBrowserOrDocumentation() async throws {
        if isRoleRunning(.browser) || isRoleRunning(.documentation) {
            return
        }

        if let documentationIdentifier =
            preferredBundleIdentifiers[.documentation]?.first(where: {
                NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: $0
                ) != nil
            }) {
            try await launch(
                bundleIdentifier: documentationIdentifier,
                fallbackName: "documentation app"
            )
            return
        }

        try await ensureRole(.browser)
    }

    private func ensureRole(_ role: ApplicationRole) async throws {
        guard !isRoleRunning(role) else {
            return
        }

        if role == .browser {
            guard let httpsURL = URL(string: "https://example.com"),
                  let browserURL = NSWorkspace.shared.urlForApplication(
                      toOpen: httpsURL
                  ),
                  let bundle = Bundle(url: browserURL),
                  let identifier = bundle.bundleIdentifier
            else {
                throw ScenarioApplicationLauncherError
                    .applicationNotInstalled(name: "a web browser")
            }

            try await launch(
                bundleIdentifier: identifier,
                fallbackName: "web browser"
            )
            return
        }

        guard let candidates = preferredBundleIdentifiers[role],
              let identifier = candidates.first(where: {
                  NSWorkspace.shared.urlForApplication(
                      withBundleIdentifier: $0
                  ) != nil
              })
        else {
            throw ScenarioApplicationLauncherError.applicationNotInstalled(
                name: role.rawValue
            )
        }

        try await launch(
            bundleIdentifier: identifier,
            fallbackName: role.rawValue
        )
    }

    private static func webURL(from value: String) -> URL? {
        let candidate: String
        if value.contains("://") {
            candidate = value
        } else {
            candidate = "https://\(value)"
        }

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return nil
        }
        return url
    }

    private func open(
        _ url: URL,
        for target: ScenarioWindowTarget
    ) async throws {
        if target.kind == .application,
           let identifier = target.application?.bundleIdentifier,
           let applicationURL = NSWorkspace.shared.urlForApplication(
               withBundleIdentifier: identifier
           ) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            _ = try await NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: configuration
            )
        } else if !NSWorkspace.shared.open(url) {
            throw ScenarioApplicationLauncherError.invalidURL(
                url.absoluteString
            )
        }

        try? await Task.sleep(for: .milliseconds(600))
    }

    private func ensureApplication(
        _ application: ScenarioApplication
    ) async throws {
        if !NSRunningApplication.runningApplications(
            withBundleIdentifier: application.bundleIdentifier
        ).isEmpty {
            return
        }

        try await launch(
            bundleIdentifier: application.bundleIdentifier,
            fallbackName: application.displayName
        )
    }

    private func launch(
        bundleIdentifier: String,
        fallbackName: String
    ) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            throw ScenarioApplicationLauncherError.applicationNotInstalled(
                name: fallbackName
            )
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let runningApplication = try await NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration
        )
        await waitForUsableWindow(of: runningApplication)
    }

    private func waitForUsableWindow(
        of application: NSRunningApplication
    ) async {
        guard AXIsProcessTrusted() else {
            try? await Task.sleep(for: .milliseconds(900))
            return
        }

        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )

        for _ in 0..<32 {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                applicationElement,
                kAXWindowsAttribute as CFString,
                &value
            )
            if result == .success,
               let windows = value as? [AXUIElement],
               !windows.isEmpty {
                return
            }

            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func isRoleRunning(_ role: ApplicationRole) -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            guard application.activationPolicy == .regular else {
                return false
            }
            return ApplicationRoleClassifier.role(
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.localizedName ?? "",
                windowTitle: ""
            ) == role
        }
    }
}
