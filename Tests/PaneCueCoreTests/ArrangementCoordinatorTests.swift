import Foundation
import Testing
@testable import PaneCueCore

@Suite("Arrangement coordinator")
struct ArrangementCoordinatorTests {
    @Test
    func allConsumersCreatePreviewWithoutApplying() async throws {
        let events = ArrangementEventRecorder()
        let coordinator = makeCoordinator(events: events)

        for (index, source) in ArrangementRequestSource.allCases.enumerated() {
            let previewID = UUID(
                uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)"
            )!
            let preview = try await coordinator.preparePreview(
                id: previewID,
                source: source,
                makeDraft: { makeWorkspacePlan() }
            )

            #expect(preview.id == previewID)
            #expect(preview.source == source)
            #expect(preview.eligibility == .ready)
        }

        let recordedEvents = await events.snapshot()
        #expect(
            recordedEvents
                == Array(
                    repeating: ArrangementEvent.prepared,
                    count: ArrangementRequestSource.allCases.count
                )
        )
    }

    @Test
    func directApplyRevalidatesBeforeTheMutationBoundary() async throws {
        let events = ArrangementEventRecorder()
        let coordinator = makeCoordinator(events: events)
        let preview = try await coordinator.preparePreview(
            source: .arrange,
            makeDraft: { makeWorkspacePlan() }
        )

        let result = try await coordinator.apply(
            previewID: preview.id,
            authority: .directUserAction
        )

        let recordedEvents = await events.snapshot()
        #expect(recordedEvents == [.prepared, .revalidated, .applied])
        #expect(result.didChangeAnyWindow)
        #expect(result.canRollback)
    }

    @Test
    func blockedRevalidationNeverCrossesTheMutationBoundary() async throws {
        let events = ArrangementEventRecorder()
        let coordinator = makeCoordinator(
            events: events,
            revalidatedEligibility: .blocked
        )
        let preview = try await coordinator.preparePreview(
            source: .quickCue,
            makeDraft: { makeWorkspacePlan() }
        )

        do {
            _ = try await coordinator.apply(
                previewID: preview.id,
                authority: .directUserAction
            )
            Issue.record("A blocked Preview crossed the Apply gate")
        } catch let error as ArrangementCoordinatorError {
            #expect(error == .previewNotReady)
        }

        let recordedEvents = await events.snapshot()
        #expect(recordedEvents == [.prepared, .revalidated])
        #expect(
            await coordinator.currentPreview()?.eligibility == .blocked
        )
    }

    @Test
    func stalePreviewCannotApplyAfterAReplacement() async throws {
        let events = ArrangementEventRecorder()
        let coordinator = makeCoordinator(events: events)
        let first = try await coordinator.preparePreview(
            source: .paneCueLink,
            makeDraft: { makeWorkspacePlan() }
        )
        let second = try await coordinator.preparePreview(
            source: .savedCue,
            makeDraft: { makeWorkspacePlan() }
        )

        do {
            _ = try await coordinator.apply(
                previewID: first.id,
                authority: .directUserAction
            )
            Issue.record("A replaced Preview crossed the Apply gate")
        } catch let error as ArrangementCoordinatorError {
            #expect(error == .stalePreview)
        }

        let recordedEvents = await events.snapshot()
        #expect(recordedEvents == [.prepared, .prepared])
        #expect(await coordinator.currentPreview()?.id == second.id)
    }

    @Test
    func discardAndRollbackHaveNoImplicitSideEffects() async throws {
        let events = ArrangementEventRecorder()
        let coordinator = makeCoordinator(events: events)
        let discarded = try await coordinator.preparePreview(
            source: .quickCue,
            makeDraft: { makeWorkspacePlan() }
        )
        await coordinator.discardPreview(id: discarded.id)

        do {
            _ = try await coordinator.rollback(
                authority: .directUserAction
            )
            Issue.record("Rollback ran before an eligible Apply")
        } catch let error as ArrangementCoordinatorError {
            #expect(error == .rollbackUnavailable)
        }

        let applied = try await coordinator.preparePreview(
            source: .arrange,
            makeDraft: { makeWorkspacePlan() }
        )
        _ = try await coordinator.apply(
            previewID: applied.id,
            authority: .directUserAction
        )
        let summary = try await coordinator.rollback(
            authority: .directUserAction
        )

        let recordedEvents = await events.snapshot()
        #expect(
            recordedEvents
                == [.prepared, .prepared, .revalidated, .applied, .rolledBack]
        )
        #expect(summary == "Layout restored")
    }

    private func makeCoordinator(
        events: ArrangementEventRecorder,
        preparedEligibility: ArrangementPreviewEligibility = .ready,
        revalidatedEligibility: ArrangementPreviewEligibility = .ready
    ) -> ArrangementCoordinator {
        ArrangementCoordinator(
            pipeline: ArrangementCoordinatorPipeline(
                preparePreview: { _ in
                    await events.append(.prepared)
                    return ArrangementPreviewPreparation(
                        eligibility: preparedEligibility
                    )
                },
                revalidatePreview: { _ in
                    await events.append(.revalidated)
                    return ArrangementPreviewPreparation(
                        eligibility: revalidatedEligibility
                    )
                },
                apply: { preview in
                    await events.append(.applied)
                    return makeApplyResult(for: preview)
                },
                rollback: {
                    await events.append(.rolledBack)
                    return "Layout restored"
                }
            )
        )
    }
}

private enum ArrangementEvent: Equatable, Sendable {
    case prepared
    case revalidated
    case applied
    case rolledBack
}

private actor ArrangementEventRecorder {
    private var events: [ArrangementEvent] = []

    func append(_ event: ArrangementEvent) {
        events.append(event)
    }

    func snapshot() -> [ArrangementEvent] {
        events
    }
}

private func makeWorkspacePlan() -> WorkspacePlan {
    WorkspacePlan.tiled(
        targets: [
            ScenarioWindowTarget(role: .ide),
            ScenarioWindowTarget(role: .notes)
        ]
    )
}

private func makeApplyResult(
    for preview: ArrangementPreview
) -> WorkspaceApplyResult {
    WorkspaceApplyResult(
        scenarioName: "Arrange",
        outcomes: preview.plan.windows.map { slot in
            WorkspaceApplyOutcome(
                id: slot.id,
                targetName: slot.target.displayName,
                status: .moved
            )
        },
        canRollback: true
    )
}
