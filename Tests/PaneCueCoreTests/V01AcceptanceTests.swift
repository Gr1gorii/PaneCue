import CoreGraphics
import Foundation
import Testing
@testable import PaneCueCore

@Suite("v0.1 acceptance")
struct V01AcceptanceTests {
    @Test
    func frozenHeroCommandCreatesThreeWindowPreview() throws {
        let plan = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "VS Code большой слева, Safari справа, Terminal маленький снизу"
            )
        )

        #expect(plan.windows.count == 3)
        #expect(plan.windows.map(\.target.displayName) == [
            "VS Code",
            "Safari",
            "Terminal"
        ])
        #expect(plan.windows[0].gridRect.width > plan.windows[1].gridRect.width)
    }

    @Test
    func browserNotesAndSmallTerminalKeepTheFrozenGeometry() throws {
        let plan = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Chrome большой слева, Заметки справа сверху, Терминал маленький справа снизу"
            )
        )

        #expect(plan.windows.map(\.target.displayName) == [
            "Chrome",
            "Any notes app",
            "Terminal"
        ])
        #expect(abs(plan.windows[0].gridRect.width - 2.0 / 3.0) < 0.000_001)
        #expect(plan.windows[0].gridRect.height == 1)
        #expect(abs(plan.windows[1].gridRect.x - 2.0 / 3.0) < 0.000_001)
        #expect(plan.windows[1].gridRect.y == 0)
        #expect(plan.windows[1].gridRect.height == 0.5)
        #expect(abs(plan.windows[2].gridRect.x - 2.0 / 3.0) < 0.000_001)
        #expect(plan.windows[2].gridRect.y == 0.5)
        #expect(plan.windows[2].gridRect.height == 0.5)
    }

    @Test
    func russianOfflineJourneyReachesReversibleApply() throws {
        let initial = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Открой VS Code, заметки и терминал"
            )
        )
        #expect(initial.windows.count == 3)

        guard case let .updated(refined, _) =
            WorkspacePlanCommandInterpreter.interpret(
                "Заметки сделай чуть поменьше",
                currentPlan: initial
            ) else {
            Issue.record("Expected the follow-up to refine the preview")
            return
        }
        let scenario = try #require(refined.scenario(named: "Arrange"))
        let preflight = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: [
                item(
                    "ide",
                    role: .ide,
                    bundleIdentifier: "com.microsoft.VSCode"
                ),
                item("notes", role: .notes),
                item(
                    "terminal",
                    role: .other,
                    bundleIdentifier: "com.apple.Terminal"
                )
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )
        #expect(preflight.allSatisfy { decision in
            if case .ready = decision.status { return true }
            return false
        })

        let result = WorkspaceApplyResult(
            scenarioName: scenario.name,
            outcomes: scenario.windows.map {
                WorkspaceApplyOutcome(
                    id: $0.id,
                    targetName: $0.target.displayName,
                    status: .moved
                )
            },
            canRollback: true
        )
        #expect(result.didChangeAnyWindow)
        #expect(result.canRollback)
        #expect(!result.isPartial)
    }

    @Test
    func englishThreeWindowCommandBuildsSafePreview() throws {
        let plan = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Open Xcode, Safari and Notes"
            )
        )

        #expect(plan.windows.count == 3)
        #expect(plan.windows.map(\.target.displayName) == [
            "Xcode",
            "Safari",
            "Any notes app"
        ])
        #expect(plan.scenario(named: "Arrange") != nil)
    }

    @Test
    func mouseEditCommitsToTheFrozenGrid() {
        let start = ScenarioGridRect(
            x: 0,
            y: 0,
            width: 0.65,
            height: 1
        )
        let preview = ScenarioGridInteraction.resizedRect(
            from: start,
            handle: .trailing,
            translation: CGSize(width: -137, height: 0),
            canvasSize: CGSize(width: 1_200, height: 800)
        )
        let committed = ScenarioGridInteraction.snappedResizedRect(
            preview,
            handle: .trailing
        )

        #expect(committed.width < start.width)
        #expect(
            abs(
                committed.width * Double(ScenarioGridResolution.columns)
                    - (committed.width
                        * Double(ScenarioGridResolution.columns)).rounded()
            ) < 0.000_001
        )
    }

    @Test
    func partialApplyKeepsRollbackAndExplainsEveryTarget() {
        let result = WorkspaceApplyResult(
            scenarioName: "Arrange",
            outcomes: [
                WorkspaceApplyOutcome(
                    id: UUID(),
                    targetName: "VS Code",
                    status: .moved
                ),
                WorkspaceApplyOutcome(
                    id: UUID(),
                    targetName: "Notes",
                    status: .unchanged,
                    reason: "This window cannot be resized."
                ),
                WorkspaceApplyOutcome(
                    id: UUID(),
                    targetName: "Browser",
                    status: .skipped,
                    reason: "The matching window was closed."
                )
            ],
            canRollback: true
        )

        #expect(result.isPartial)
        #expect(result.canRollback)
        #expect(result.outcomes.allSatisfy {
            $0.status == .moved || $0.reason != nil
        })
    }

    @Test
    func cueSurvivesExportImportAndPlanRecreation() throws {
        let plan = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Open VS Code and Notes"
            )
        )
        let cue = try #require(plan.scenario(named: "Development"))
        let encoded = try CueArchive(cues: [cue]).encodedData()
        let restoredCue = try #require(
            CueArchive.decode(encoded).cues.first
        )
        let restoredPlan = WorkspacePlan(scenario: restoredCue)

        #expect(restoredCue.name == "Development")
        #expect(restoredPlan.windows == plan.windows)
    }

    @Test
    func unsafeOrQuestionLikeCommandsRemainNoAction() {
        #expect(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Is it possible to open VS Code and Notes?"
            ) == nil
        )
        #expect(
            OfflineVoiceCommandParser.explicitlyDeclinesAction(
                from: "Не открывай VS Code и заметки"
            )
        )
    }

    private func item(
        _ id: String,
        role: ApplicationRole,
        bundleIdentifier: String? = nil
    ) -> WorkspaceWindowInventoryItem {
        WorkspaceWindowInventoryItem(
            id: id,
            bundleIdentifier: bundleIdentifier,
            applicationName: "Fixture",
            role: role
        )
    }
}
