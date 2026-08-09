import Foundation
import PaneCueCore

/// Connects the existing Arrange UI to the shared Core coordinator without
/// giving the view a second window-execution path.
@MainActor
final class ArrangeCoordinatorController {
    typealias ResolutionExecution = @MainActor @Sendable
        (ArrangementDraft) async throws -> ArrangementTargetResolutionSet
    typealias ApplyExecution = @MainActor @Sendable
        (
            WorkspacePlan,
            ArrangementTargetResolutionSet?
        ) async throws -> WorkspaceApplyResult
    typealias RollbackExecution = @MainActor @Sendable
        () async throws -> String

    private let coordinator: ArrangementCoordinator

    init(
        resolve: ResolutionExecution?,
        apply: @escaping ApplyExecution,
        rollback: @escaping RollbackExecution
    ) {
        coordinator = ArrangementCoordinator(
            pipeline: ArrangementCoordinatorPipeline(
                preparePreview: { draft in
                    if let resolve {
                        let resolution = try await resolve(draft)
                        return ArrangementPreviewPreparation(
                            resolution: resolution,
                            isPlanValid: draft.plan.windows.count >= 2
                        )
                    }
                    return ArrangementPreviewPreparation(
                        eligibility: draft.plan.windows.count >= 2
                            ? .ready
                            : .blocked
                    )
                },
                revalidatePreview: { preview in
                    guard let resolve else {
                        return ArrangementPreviewPreparation(
                            eligibility: eligibility(for: preview)
                        )
                    }
                    let fresh = try await resolve(preview.draft)
                    let resolution = preview.resolution?
                        .revalidating(against: fresh) ?? fresh
                    return ArrangementPreviewPreparation(
                        resolution: resolution,
                        isPlanValid: preview.plan.windows.count >= 2
                    )
                },
                apply: { preview in
                    try await apply(preview.plan, preview.resolution)
                },
                rollback: rollback
            )
        )
    }

    convenience init(
        apply: @escaping @MainActor @Sendable
            (WorkspacePlan) async throws -> WorkspaceApplyResult,
        rollback: @escaping RollbackExecution
    ) {
        self.init(
            resolve: nil,
            apply: { plan, _ in
                try await apply(plan)
            },
            rollback: rollback
        )
    }

    func prepare(
        _ analysis: CommandLabAnalysis,
        source: ArrangementRequestSource = .arrange,
        savedScenarios: [CustomScenario] = []
    ) async throws -> CommandLabAnalysis {
        switch analysis {
        case let .plan(plan, summary):
            let preview = try await prepare(plan, source: source)
            return .plan(preview.plan, summary: summary)
        case let .action(intent):
            if let plan = WorkspacePlan.from(
                intent: intent,
                scenarios: savedScenarios
            ) {
                let preview = try await prepare(
                    plan,
                    source: source == .arrange
                        && intent.action == .applyCustomScenario
                        ? .savedCue
                        : source
                )
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

        let preview: ArrangementPreview
        if let current = await coordinator.currentPreview(),
           current.id == plan.id,
           targetsMatch(current.plan, plan) {
            preview = current.plan == plan
                ? current
                : try await coordinator.updatePreviewPlan(
                    previewID: current.id,
                    plan: plan
                )
        } else {
            preview = try await prepare(plan, source: .arrange)
        }
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

    func preparePlan(
        _ plan: WorkspacePlan
    ) async throws -> ArrangementPreview {
        let current = await coordinator.currentPreview()
        let source = current?.id == plan.id
            ? current?.source ?? .arrange
            : .arrange
        return try await prepare(plan, source: source)
    }

    func preparePaneCueLinkPlan(
        _ plan: WorkspacePlan
    ) async throws -> ArrangementPreview {
        try await prepare(plan, source: .paneCueLink)
    }

    func selectCandidate(
        previewID: UUID,
        slotID: UUID,
        candidateID: EphemeralWindowIdentifier
    ) async throws -> ArrangementPreview {
        try await coordinator.selectCandidate(
            previewID: previewID,
            slotID: slotID,
            candidateID: candidateID
        )
    }

    private func prepare(
        _ plan: WorkspacePlan,
        source: ArrangementRequestSource
    ) async throws -> ArrangementPreview {
        try await coordinator.preparePreview(
            id: plan.id,
            source: source,
            makeDraft: { plan }
        )
    }
}

private func eligibility(
    for preview: ArrangementPreview
) -> ArrangementPreviewEligibility {
    preview.plan.windows.count >= 2
        && !(preview.resolution?.requiresCandidateSelection ?? false)
        ? .ready
        : .blocked
}

private func targetsMatch(
    _ first: WorkspacePlan,
    _ second: WorkspacePlan
) -> Bool {
    guard first.windows.count == second.windows.count else {
        return false
    }
    return zip(first.windows, second.windows).allSatisfy { lhs, rhs in
        lhs.id == rhs.id
            && lhs.target == rhs.target
            && lhs.display == rhs.display
    }
}
