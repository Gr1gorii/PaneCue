import Foundation
import Testing
@testable import PaneCueCore

@Suite("Workspace apply result")
struct WorkspaceApplyResultTests {
    @Test
    func reportsCompleteApply() {
        let result = WorkspaceApplyResult(
            scenarioName: "Arrange",
            outcomes: [
                outcome(.moved, name: "VS Code"),
                outcome(.moved, name: "Notes")
            ],
            canRollback: true
        )

        #expect(result.didChangeAnyWindow)
        #expect(!result.isPartial)
        #expect(result.movedCount == 2)
        #expect(result.summary == "Arrange applied to 2 windows")
    }

    @Test
    func reportsPartialApplyAndKeepsRollbackAvailable() {
        let result = WorkspaceApplyResult(
            scenarioName: "Arrange",
            outcomes: [
                outcome(.moved, name: "VS Code"),
                outcome(
                    .skipped,
                    name: "Notes",
                    reason: "The window was closed."
                ),
                outcome(
                    .failed,
                    name: "Terminal",
                    reason: "The application rejected the position."
                )
            ],
            canRollback: true
        )

        #expect(result.isPartial)
        #expect(result.movedCount == 1)
        #expect(result.skippedCount == 1)
        #expect(result.failedCount == 1)
        #expect(result.canRollback)
        #expect(result.summary == "Arrange applied to 1 of 3 windows")
    }

    @Test
    func noChangeDoesNotClaimSuccess() {
        let result = WorkspaceApplyResult(
            scenarioName: "Arrange",
            outcomes: [
                outcome(.unchanged, name: "VS Code"),
                outcome(.skipped, name: "Notes")
            ],
            canRollback: false
        )

        #expect(!result.didChangeAnyWindow)
        #expect(!result.isPartial)
        #expect(result.summary == "No windows changed")

        let unchangeable = WorkspaceApplyResult(
            scenarioName: "Arrange",
            outcomes: [
                outcome(.unchanged, name: "VS Code"),
                outcome(.unchanged, name: "Notes")
            ],
            canRollback: false
        )
        #expect(unchangeable.summary == "No windows changed")
    }

    @Test
    func distinguishesAlreadyPlacedFromUnchangeable() {
        let complete = WorkspaceApplyResult(
            scenarioName: "Arrange",
            outcomes: [
                outcome(.moved, name: "VS Code"),
                outcome(
                    .unchanged,
                    name: "Notes",
                    matchesPreview: true
                )
            ],
            canRollback: true
        )
        let partial = WorkspaceApplyResult(
            scenarioName: "Arrange",
            outcomes: [
                outcome(.moved, name: "VS Code"),
                outcome(.unchanged, name: "Notes")
            ],
            canRollback: true
        )

        #expect(!complete.isPartial)
        #expect(complete.satisfiedCount == 2)
        #expect(complete.summary == "Arrange ready · 1 moved, 1 already in place")
        #expect(partial.isPartial)
        #expect(partial.satisfiedCount == 1)
    }

    private func outcome(
        _ status: WorkspaceApplyOutcomeStatus,
        name: String,
        reason: String? = nil,
        matchesPreview: Bool? = nil
    ) -> WorkspaceApplyOutcome {
        WorkspaceApplyOutcome(
            id: UUID(),
            targetName: name,
            status: status,
            reason: reason,
            matchesPreview: matchesPreview
        )
    }
}
