import Foundation
import PaneCueCore
import Testing
@testable import PaneCueApp

@Suite("Arrange coordinator integration")
@MainActor
struct ArrangeCoordinatorControllerTests {
    @Test
    func previewApplyAndRollbackUseOneCoordinator() async throws {
        let recorder = ArrangeExecutionRecorder()
        let controller = makeController(recorder: recorder)
        let plan = makeArrangePlan()

        let analysis = try await controller.prepare(
            .plan(plan, summary: "Preview ready")
        )
        guard case let .plan(preparedPlan, summary) = analysis else {
            Issue.record("Arrange did not return a coordinated Preview")
            return
        }

        #expect(preparedPlan == plan)
        #expect(summary == "Preview ready")
        #expect((await controller.currentState()).phase == .ready)
        #expect(await recorder.applyCount() == 0)

        let result = try await controller.apply(preparedPlan)
        #expect(result.didChangeAnyWindow)
        #expect((await controller.currentState()).phase == .result)
        #expect(await recorder.applyCount() == 1)

        let rollbackSummary = try await controller.rollback()
        #expect(rollbackSummary == "Layout restored")
        #expect((await controller.currentState()).phase == .idle)
        #expect(await recorder.rollbackCount() == 1)
    }

    @Test
    func editingAndDiscardNeverCrossTheExecutionBoundary() async throws {
        let recorder = ArrangeExecutionRecorder()
        let controller = makeController(recorder: recorder)

        await controller.beginEditing()
        #expect((await controller.currentState()).phase == .editing)

        _ = try await controller.prepare(
            .plan(makeArrangePlan(), summary: "Preview ready")
        )
        await controller.discard()

        let state = await controller.currentState()
        #expect(state.phase == .idle)
        #expect(state.preview == nil)
        #expect(await recorder.applyCount() == 0)
        #expect(await recorder.rollbackCount() == 0)
    }

    @Test
    func savedArrangementActionStillBecomesACoordinatedPreview() async throws {
        let recorder = ArrangeExecutionRecorder()
        let controller = makeController(recorder: recorder)

        let analysis = try await controller.prepare(
            .action(
                VoiceCommandIntent(action: .applyNotesAndBrowser)
            )
        )

        guard case let .plan(plan, _) = analysis else {
            Issue.record("Saved arrangement action bypassed Preview")
            return
        }

        #expect(plan.windows.count == 2)
        #expect((await controller.currentState()).phase == .ready)
        #expect(await recorder.applyCount() == 0)
    }

    @Test
    func oneWindowDraftKeepsTheExistingApplyError() async throws {
        let recorder = ArrangeExecutionRecorder()
        let controller = makeController(recorder: recorder)
        let plan = WorkspacePlan.tiled(
            targets: [ScenarioWindowTarget(role: .ide)]
        )

        do {
            _ = try await controller.apply(plan)
            Issue.record("A one-window draft crossed the Apply boundary")
        } catch {
            #expect(
                error.localizedDescription
                    == "Add at least two windows before applying this plan."
            )
        }

        #expect(await recorder.applyCount() == 0)
    }

    private func makeController(
        recorder: ArrangeExecutionRecorder
    ) -> ArrangeCoordinatorController {
        ArrangeCoordinatorController(
            apply: { plan in
                await recorder.recordApply()
                return makeArrangeResult(for: plan)
            },
            rollback: {
                await recorder.recordRollback()
                return "Layout restored"
            }
        )
    }
}

private actor ArrangeExecutionRecorder {
    private var applies = 0
    private var rollbacks = 0

    func recordApply() {
        applies += 1
    }

    func recordRollback() {
        rollbacks += 1
    }

    func applyCount() -> Int {
        applies
    }

    func rollbackCount() -> Int {
        rollbacks
    }
}

private func makeArrangePlan() -> WorkspacePlan {
    WorkspacePlan.tiled(
        targets: [
            ScenarioWindowTarget(role: .ide),
            ScenarioWindowTarget(role: .notes)
        ]
    )
}

private func makeArrangeResult(
    for plan: WorkspacePlan
) -> WorkspaceApplyResult {
    WorkspaceApplyResult(
        scenarioName: "Arrange",
        outcomes: plan.windows.map { slot in
            WorkspaceApplyOutcome(
                id: slot.id,
                targetName: slot.target.displayName,
                status: .moved
            )
        },
        canRollback: true
    )
}
