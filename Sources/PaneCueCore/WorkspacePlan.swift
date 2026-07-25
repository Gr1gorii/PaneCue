import Foundation

/// A safe, editable draft of a workspace. Unlike a saved scenario, a plan may
/// temporarily contain a single window while the user is still refining it.
public struct WorkspacePlan: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var windows: [ScenarioWindowSlot]
    public var selectedWindowID: UUID?
    public var revision: Int

    public init(
        id: UUID = UUID(),
        name: String = "Workspace Draft",
        windows: [ScenarioWindowSlot],
        selectedWindowID: UUID? = nil,
        revision: Int = 1
    ) {
        let normalizedWindows = Array(windows.prefix(8)).map { window in
            var normalized = window
            normalized.target = normalized.target.normalized
            normalized.gridRect.normalize()
            return normalized
        }
        self.id = id
        self.name = name
        self.windows = normalizedWindows
        self.selectedWindowID = selectedWindowID.flatMap { candidate in
            normalizedWindows.contains(where: { $0.id == candidate })
                ? candidate
                : nil
        } ?? normalizedWindows.last?.id
        self.revision = max(revision, 1)
    }

    public init(scenario: CustomScenario) {
        self.init(
            name: scenario.name,
            windows: scenario.windows,
            selectedWindowID: scenario.windows.last?.id
        )
    }

    public var selectedWindowIndex: Int? {
        guard let selectedWindowID else {
            return nil
        }
        return windows.firstIndex { $0.id == selectedWindowID }
    }

    public func scenario(named name: String) -> CustomScenario? {
        let trimmed = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard windows.count >= 2, !trimmed.isEmpty else {
            return nil
        }
        return CustomScenario(
            name: trimmed,
            windows: windows
        )
    }

    public static func tiled(
        targets: [ScenarioWindowTarget],
        name: String = "Workspace Draft"
    ) -> WorkspacePlan {
        let uniqueTargets = Array(targets.prefix(8))
        let rects = balancedRects(count: uniqueTargets.count)
        let slots = zip(uniqueTargets, rects).map { target, rect in
            ScenarioWindowSlot(
                target: target,
                gridRect: rect
            )
        }
        return WorkspacePlan(
            name: name,
            windows: slots,
            selectedWindowID: slots.last?.id
        )
    }

    public static func from(
        intent: VoiceCommandIntent,
        scenarios: [CustomScenario] = []
    ) -> WorkspacePlan? {
        switch intent.action {
        case .applyDocumentationAndCode:
            return tiled(
                targets: [
                    ScenarioWindowTarget(role: .ide),
                    ScenarioWindowTarget(role: .documentation)
                ],
                name: "Documentation + Code"
            )

        case .applyNotesAndBrowser:
            return tiled(
                targets: [
                    ScenarioWindowTarget(role: .browser),
                    ScenarioWindowTarget(role: .notes)
                ],
                name: "Notes + Browser"
            )

        case .arrangeDynamicWorkspace:
            guard let primary = target(
                kind: intent.arguments[
                    DynamicWorkspaceArgument.primaryKind
                ],
                value: intent.arguments[
                    DynamicWorkspaceArgument.primaryValue
                ],
                name: intent.arguments[
                    DynamicWorkspaceArgument.primaryName
                ]
            ),
            let secondary = target(
                kind: intent.arguments[
                    DynamicWorkspaceArgument.secondaryKind
                ],
                value: intent.arguments[
                    DynamicWorkspaceArgument.secondaryValue
                ],
                name: intent.arguments[
                    DynamicWorkspaceArgument.secondaryName
                ]
            ) else {
                return nil
            }

            let ratio = min(
                max(
                    Double(
                        intent.arguments[
                            DynamicWorkspaceArgument.primaryRatio
                        ] ?? "0.65"
                    ) ?? 0.65,
                    0.5
                ),
                0.8
            )
            let vertical =
                intent.arguments[DynamicWorkspaceArgument.axis]
                    == "vertical"
            let leads =
                intent.arguments[
                    DynamicWorkspaceArgument.primaryPosition
                ] != "trailing"

            let primaryRect: ScenarioGridRect
            let secondaryRect: ScenarioGridRect
            if vertical {
                primaryRect = ScenarioGridRect(
                    x: 0,
                    y: leads ? 0 : 1 - ratio,
                    width: 1,
                    height: ratio
                )
                secondaryRect = ScenarioGridRect(
                    x: 0,
                    y: leads ? ratio : 0,
                    width: 1,
                    height: 1 - ratio
                )
            } else {
                primaryRect = ScenarioGridRect(
                    x: leads ? 0 : 1 - ratio,
                    y: 0,
                    width: ratio,
                    height: 1
                )
                secondaryRect = ScenarioGridRect(
                    x: leads ? ratio : 0,
                    y: 0,
                    width: 1 - ratio,
                    height: 1
                )
            }

            let slots = [
                ScenarioWindowSlot(
                    target: primary,
                    gridRect: primaryRect
                ),
                ScenarioWindowSlot(
                    target: secondary,
                    gridRect: secondaryRect
                )
            ]
            return WorkspacePlan(
                windows: slots,
                selectedWindowID: slots.first?.id
            )

        case .applyCustomScenario:
            guard let requestedName =
                intent.arguments["scenario_name"],
                let scenario = scenarios.first(where: {
                    $0.name.caseInsensitiveCompare(requestedName)
                        == .orderedSame
                        || (
                            !$0.voicePhrase.isEmpty
                                && $0.voicePhrase
                                    .caseInsensitiveCompare(
                                        requestedName
                                    ) == .orderedSame
                        )
                }) else {
                return nil
            }
            return WorkspacePlan(scenario: scenario)

        case .applyCodeAndCall,
             .showBrowserVideo,
             .restorePreviousLayout:
            return nil
        }
    }

    public static func balancedRects(
        count: Int
    ) -> [ScenarioGridRect] {
        let count = min(max(count, 0), 8)
        switch count {
        case 0:
            return []
        case 1:
            return [
                ScenarioGridRect(x: 0, y: 0, width: 1, height: 1)
            ]
        case 2:
            return [
                ScenarioGridRect(
                    x: 0,
                    y: 0,
                    width: 0.65,
                    height: 1
                ),
                ScenarioGridRect(
                    x: 0.65,
                    y: 0,
                    width: 0.35,
                    height: 1
                )
            ]
        case 3:
            return [
                ScenarioGridRect(
                    x: 0,
                    y: 0,
                    width: 2.0 / 3.0,
                    height: 1
                ),
                ScenarioGridRect(
                    x: 2.0 / 3.0,
                    y: 0,
                    width: 1.0 / 3.0,
                    height: 0.5
                ),
                ScenarioGridRect(
                    x: 2.0 / 3.0,
                    y: 0.5,
                    width: 1.0 / 3.0,
                    height: 0.5
                )
            ]
        case 4:
            return gridRects(count: count, columns: 2)
        default:
            let columns = Int(ceil(sqrt(Double(count))))
            return gridRects(count: count, columns: columns)
        }
    }

    private static func gridRects(
        count: Int,
        columns: Int
    ) -> [ScenarioGridRect] {
        let rows = Int(ceil(Double(count) / Double(columns)))
        return (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            return ScenarioGridRect(
                x: Double(column) / Double(columns),
                y: Double(row) / Double(rows),
                width: 1 / Double(columns),
                height: 1 / Double(rows)
            )
        }
    }

    private static func target(
        kind: String?,
        value: String?,
        name: String?
    ) -> ScenarioWindowTarget? {
        guard let kind, let value, !value.isEmpty else {
            return nil
        }
        if kind == "role", let role = ApplicationRole(rawValue: value) {
            return ScenarioWindowTarget(role: role)
        }
        guard kind == "application" else {
            return nil
        }
        return ScenarioWindowTarget(
            application: ScenarioApplication(
                bundleIdentifier: value,
                displayName: name ?? value
            )
        )
    }
}
