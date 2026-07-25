import Foundation
import Testing
@testable import PaneCueCore

@Suite("Workspace Plan")
struct WorkspacePlanTests {
    @Test
    func createsAThreeWindowDraftFromOneCommand() {
        let plan = WorkspacePlanCommandInterpreter.initialPlan(
            from: "Открой VS Code, заметки и терминал снизу"
        )

        #expect(plan?.windows.count == 3)
        #expect(
            plan?.windows.map(\.target.displayName)
                == ["VS Code", "Any notes app", "Terminal"]
        )
        #expect(plan?.windows[0].gridRect.width == 2.0 / 3.0)
        #expect(plan?.windows[2].gridRect.y == 0.5)
    }

    @Test
    func followUpResizesTheNamedWindow() throws {
        let initial = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Открой VS Code и заметки"
            )
        )
        let notesBefore = try #require(
            initial.windows.first {
                $0.target.role == .notes
            }
        )

        let result = WorkspacePlanCommandInterpreter.interpret(
            "Заметки сделай еще меньше",
            currentPlan: initial
        )
        guard case let .updated(updated, _) = result else {
            Issue.record("Expected an updated plan")
            return
        }
        let notesAfter = try #require(
            updated.windows.first {
                $0.target.role == .notes
            }
        )

        #expect(notesAfter.gridRect.width < notesBefore.gridRect.width)
        #expect(updated.windows.count == 2)
    }

    @Test
    func addsAThirdWindowAtTheRequestedEdge() throws {
        let initial = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Открой VS Code и заметки"
            )
        )
        let result = WorkspacePlanCommandInterpreter.interpret(
            "Добавь терминал снизу",
            currentPlan: initial
        )
        guard case let .updated(updated, _) = result else {
            Issue.record("Expected an updated plan")
            return
        }

        #expect(updated.windows.count == 3)
        #expect(updated.windows.last?.target.displayName == "Terminal")
        #expect(updated.windows.last?.gridRect.y == 0.65)
        #expect(updated.windows.last?.gridRect.width == 1)
        #expect(updated.selectedWindowID == updated.windows.last?.id)
    }

    @Test
    func pronounUsesTheLastSelectedWindow() throws {
        let initial = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Открой VS Code и заметки"
            )
        )
        guard case let .updated(withTerminal, _) =
            WorkspacePlanCommandInterpreter.interpret(
                "Добавь терминал снизу",
                currentPlan: initial
            ) else {
            Issue.record("Expected Terminal to be added")
            return
        }
        let before = try #require(withTerminal.windows.last)

        guard case let .updated(resized, _) =
            WorkspacePlanCommandInterpreter.interpret(
                "Сделай его чуть меньше",
                currentPlan: withTerminal
            ) else {
            Issue.record("Expected selected window to resize")
            return
        }
        let after = try #require(
            resized.windows.first { $0.id == before.id }
        )

        #expect(after.gridRect.width < before.gridRect.width)
        #expect(after.gridRect.height < before.gridRect.height)
    }

    @Test
    func supportsUndoAndNamedSaveCommands() throws {
        let plan = try #require(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Open Xcode and Safari"
            )
        )

        #expect(
            WorkspacePlanCommandInterpreter.interpret(
                "Undo last change",
                currentPlan: plan
            ) == .undo
        )
        #expect(
            WorkspacePlanCommandInterpreter.interpret(
                "Сохрани это как Разработка",
                currentPlan: plan
            ) == .save(name: "Разработка")
        )
    }

    @Test
    func rejectsQuestionsAndCapsPlansAtEightWindows() {
        #expect(
            WorkspacePlanCommandInterpreter.initialPlan(
                from: "Можно ли открыть VS Code и Notes?"
            ) == nil
        )

        let targets = (0..<12).map { index in
            ScenarioWindowTarget(
                application: ScenarioApplication(
                    bundleIdentifier: "test.app.\(index)",
                    displayName: "App \(index)"
                )
            )
        }
        let plan = WorkspacePlan.tiled(targets: targets)
        #expect(plan.windows.count == 8)
    }

    @Test
    func roundTripsAnEditableDraft() throws {
        let plan = WorkspacePlan.tiled(
            targets: [
                ScenarioWindowTarget(role: .ide),
                ScenarioWindowTarget(role: .browser),
                ScenarioWindowTarget(role: .notes)
            ]
        )

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(
            WorkspacePlan.self,
            from: data
        )

        #expect(decoded == plan)
        #expect(decoded.selectedWindowID == plan.windows.last?.id)
    }
}
