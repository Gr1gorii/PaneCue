import PaneCueCore

/// Connects the existing Arrange UI to the shared Core coordinator without
/// giving the view a second window-execution path.
@MainActor
final class ArrangeCoordinatorController {
    typealias ApplyExecution = @MainActor @Sendable
        (WorkspacePlan) async throws -> WorkspaceApplyResult
    typealias RollbackExecution = @MainActor @Sendable
        () async throws -> String

    private let coordinator: ArrangementCoordinator

    init(
        apply: @escaping ApplyExecution,
        rollback: @escaping RollbackExecution
    ) {
        coordinator = ArrangementCoordinator(
            pipeline: ArrangementCoordinatorPipeline(
                preparePreview: { draft in
                    eligibility(for: draft.plan)
                },
                revalidatePreview: { preview in
                    eligibility(for: preview.plan)
                },
                apply: { preview in
                    try await apply(preview.plan)
                },
                rollback: rollback
            )
        )
    }

    func prepare(
        _ analysis: CommandLabAnalysis,
        savedScenarios: [CustomScenario] = []
    ) async throws -> CommandLabAnalysis {
        switch analysis {
        case let .plan(plan, summary):
            let preview = try await prepare(plan)
            return .plan(preview.plan, summary: summary)
        case let .action(intent):
            if let plan = WorkspacePlan.from(
                intent: intent,
                scenarios: savedScenarios
            ) {
                let preview = try await prepare(plan)
                return .plan(
                    preview.plan,
                    summary: "Created a workspace plan"
                )
            }
            await coordinator.discardPreview()
            return analysis
        case .undo, .savePlan, .noAction:
            return analysis
        }
    }

    func apply(
        _ plan: WorkspacePlan
    ) async throws -> WorkspaceApplyResult {
        guard plan.windows.count >= 2 else {
            throw PaneCueWindowError.operationFailed(
                details: "Add at least two windows before applying this plan."
            )
        }

        let preview = try await prepare(plan)
        return try await coordinator.apply(
            previewID: preview.id,
            authority: .directUserAction
        )
    }

    func rollback() async throws -> String {
        try await coordinator.rollback(authority: .directUserAction)
    }

    func beginEditing() async {
        await coordinator.beginEditing()
    }

    func discard() async {
        await coordinator.discardPreview()
    }

    func currentState() async -> ArrangementCoordinatorState {
        await coordinator.currentState()
    }

    private func prepare(
        _ plan: WorkspacePlan
    ) async throws -> ArrangementPreview {
        try await coordinator.preparePreview(
            id: plan.id,
            source: .arrange,
            makeDraft: { plan }
        )
    }
}

private func eligibility(
    for plan: WorkspacePlan
) -> ArrangementPreviewEligibility {
    plan.windows.count >= 2 ? .ready : .blocked
}
