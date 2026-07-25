import AppKit
import Foundation
import PaneCueCore

enum DynamicWorkspaceScenarioError: LocalizedError {
    case invalidCommand
    case applicationNotInstalled(String)

    var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "PaneCue understood the layout request but could not identify two windows."
        case let .applicationNotInstalled(name):
            return "PaneCue could not find \(name) on this Mac."
        }
    }
}

@MainActor
enum DynamicWorkspaceScenarioBuilder {
    static func scenario(
        from arguments: [String: String]
    ) throws -> CustomScenario {
        let primary = try target(
            kind: arguments[DynamicWorkspaceArgument.primaryKind],
            value: arguments[DynamicWorkspaceArgument.primaryValue],
            name: arguments[DynamicWorkspaceArgument.primaryName]
        )
        let secondary = try target(
            kind: arguments[DynamicWorkspaceArgument.secondaryKind],
            value: arguments[DynamicWorkspaceArgument.secondaryValue],
            name: arguments[DynamicWorkspaceArgument.secondaryName]
        )
        let ratio = min(
            max(
                Double(
                    arguments[DynamicWorkspaceArgument.primaryRatio]
                        ?? "0.65"
                ) ?? 0.65,
                0.5
            ),
            0.8
        )
        let axis = arguments[DynamicWorkspaceArgument.axis]
            ?? "horizontal"
        let primaryLeads =
            arguments[DynamicWorkspaceArgument.primaryPosition]
                != "trailing"

        let primaryRect: ScenarioGridRect
        let secondaryRect: ScenarioGridRect
        if axis == "vertical" {
            primaryRect = ScenarioGridRect(
                x: 0,
                y: primaryLeads ? 0 : 1 - ratio,
                width: 1,
                height: ratio
            )
            secondaryRect = ScenarioGridRect(
                x: 0,
                y: primaryLeads ? ratio : 0,
                width: 1,
                height: 1 - ratio
            )
        } else {
            primaryRect = ScenarioGridRect(
                x: primaryLeads ? 0 : 1 - ratio,
                y: 0,
                width: ratio,
                height: 1
            )
            secondaryRect = ScenarioGridRect(
                x: primaryLeads ? ratio : 0,
                y: 0,
                width: 1 - ratio,
                height: 1
            )
        }

        return CustomScenario(
            name: "Voice Layout",
            windows: [
                ScenarioWindowSlot(
                    target: primary,
                    gridRect: primaryRect
                ),
                ScenarioWindowSlot(
                    target: secondary,
                    gridRect: secondaryRect
                )
            ]
        )
    }

    private static func target(
        kind: String?,
        value: String?,
        name: String?
    ) throws -> ScenarioWindowTarget {
        guard let kind, let value, !value.isEmpty else {
            throw DynamicWorkspaceScenarioError.invalidCommand
        }

        if kind == "role",
           let role = ApplicationRole(rawValue: value) {
            return ScenarioWindowTarget(role: role)
        }

        guard kind == "application" else {
            throw DynamicWorkspaceScenarioError.invalidCommand
        }

        let displayName = name?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? value
        if NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: value
        ) != nil {
            return ScenarioWindowTarget(
                application: ScenarioApplication(
                    bundleIdentifier: value,
                    displayName: displayName
                )
            )
        }

        let normalizedName = normalize(displayName)
        if let installed = ApplicationCatalog.installedApplications()
            .first(where: {
                let candidate = normalize($0.displayName)
                return candidate == normalizedName
                    || candidate.contains(normalizedName)
                    || normalizedName.contains(candidate)
            }) {
            return ScenarioWindowTarget(
                application: installed.scenarioApplication
            )
        }

        throw DynamicWorkspaceScenarioError.applicationNotInstalled(
            displayName
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-zа-яё0-9]+"#,
                with: "",
                options: .regularExpression
            )
    }
}
