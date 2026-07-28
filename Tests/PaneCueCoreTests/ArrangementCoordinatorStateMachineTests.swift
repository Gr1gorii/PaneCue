import Foundation
import Testing
@testable import PaneCueCore

@Suite("Arrangement coordinator state machine")
struct ArrangementCoordinatorStateMachineTests {
    @Test
    func followsTheFrozenHappyPath() async throws {
        let parseStarted = AsyncGate()
        let parseRelease = AsyncGate()
        let resolveStarted = AsyncGate()
        let resolveRelease = AsyncGate()
        let applyStarted = AsyncGate()
        let applyRelease = AsyncGate()
        let restoreStarted = AsyncGate()
        let restoreRelease = AsyncGate()
        let coordinator = ArrangementCoordinator(
            pipeline: ArrangementCoordinatorPipeline(
                preparePreview: { _ in
                    await resolveStarted.open()
                    await resolveRelease.wait()
                    return .ready
                },
                revalidatePreview: { _ in .ready },
                apply: { preview in
                    await applyStarted.open()
                    await applyRelease.wait()
                    return makeStateMachineResult(for: preview)
                },
                rollback: {
                    await restoreStarted.open()
                    await restoreRelease.wait()
                    return "Layout restored"
                }
            )
        )

        #expect((await coordinator.currentState()).phase == .idle)
        await coordinator.beginEditing()
        #expect((await coordinator.currentState()).phase == .editing)

        let previewTask = Task {
            try await coordinator.preparePreview(
                source: .arrange,
                makeDraft: {
                    await parseStarted.open()
                    await parseRelease.wait()
                    return makeStateMachinePlan()
                }
            )
        }
        await parseStarted.wait()
        #expect((await coordinator.currentState()).phase == .parsing)

        await parseRelease.open()
        await resolveStarted.wait()
        #expect((await coordinator.currentState()).phase == .resolving)

        await resolveRelease.open()
        let preview = try await previewTask.value
        let readyState = await coordinator.currentState()
        #expect(readyState.phase == .ready)
        #expect(readyState.canApply)
        #expect(readyState.preview?.id == preview.id)

        let applyTask = Task {
            try await coordinator.apply(
                previewID: preview.id,
                authority: .directUserAction
            )
        }
        await applyStarted.wait()
        #expect((await coordinator.currentState()).phase == .applying)

        await applyRelease.open()
        let result = try await applyTask.value
        let resultState = await coordinator.currentState()
        #expect(resultState.phase == .result)
        #expect(resultState.result == result)
        #expect(resultState.canRollback)

        let restoreTask = Task {
            try await coordinator.rollback(
                authority: .directUserAction
            )
        }
        await restoreStarted.wait()
        #expect((await coordinator.currentState()).phase == .restoring)

        await restoreRelease.open()
        _ = try await restoreTask.value
        let finalState = await coordinator.currentState()
        #expect(finalState.phase == .idle)
        #expect(finalState.preview == nil)
        #expect(finalState.result == nil)
        #expect(!finalState.canRollback)
    }

    @Test
    func blockedPreviewRequiresSelectionBeforeApply() async throws {
        let mutationCount = AsyncCounter()
        let coordinator = ArrangementCoordinator(
            pipeline: ArrangementCoordinatorPipeline(
                preparePreview: { _ in .blocked },
                revalidatePreview: { _ in .ready },
                apply: { preview in
                    await mutationCount.increment()
                    return makeStateMachineResult(for: preview)
                },
                rollback: { "Layout restored" }
            )
        )
        let preview = try await coordinator.preparePreview(
            source: .quickCue,
            makeDraft: { makeStateMachinePlan() }
        )

        let blockedState = await coordinator.currentState()
        #expect(blockedState.phase == .awaitingSelection)
        #expect(!blockedState.canApply)

        do {
            _ = try await coordinator.apply(
                previewID: preview.id,
                authority: .directUserAction
            )
            Issue.record("Apply was available before target selection")
        } catch let error as ArrangementCoordinatorError {
            #expect(error == .previewNotReady)
        }
        #expect(await mutationCount.value() == 0)

        _ = try await coordinator.updatePreviewEligibility(
            previewID: preview.id,
            eligibility: .ready
        )
        #expect((await coordinator.currentState()).phase == .ready)

        _ = try await coordinator.apply(
            previewID: preview.id,
            authority: .directUserAction
        )
        #expect(await mutationCount.value() == 1)
    }

    @Test
    func newerRequestCancelsObsoleteParsing() async throws {
        let oldParseStarted = AsyncGate()
        let oldParseCancelled = AsyncGate()
        let coordinator = makeImmediateStateMachineCoordinator()

        let obsoleteTask = Task {
            try await coordinator.preparePreview(
                source: .quickCue,
                makeDraft: {
                    await oldParseStarted.open()
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        await oldParseCancelled.open()
                        throw error
                    }
                    return makeStateMachinePlan()
                }
            )
        }
        await oldParseStarted.wait()

        let latest = try await coordinator.preparePreview(
            source: .arrange,
            makeDraft: { makeStateMachinePlan() }
        )
        await oldParseCancelled.wait()

        do {
            _ = try await obsoleteTask.value
            Issue.record("An obsolete parsing task produced a Preview")
        } catch let error as ArrangementCoordinatorError {
            #expect(error == .preparationSuperseded)
        }

        let state = await coordinator.currentState()
        #expect(state.phase == .ready)
        #expect(state.preview?.id == latest.id)
    }

    @Test
    func coordinatorNeverRunsTwoApplyTransactions() async throws {
        let applyStarted = AsyncGate()
        let applyRelease = AsyncGate()
        let mutationCount = AsyncCounter()
        let coordinator = ArrangementCoordinator(
            pipeline: ArrangementCoordinatorPipeline(
                preparePreview: { _ in .ready },
                revalidatePreview: { _ in .ready },
                apply: { preview in
                    await mutationCount.increment()
                    await applyStarted.open()
                    await applyRelease.wait()
                    return makeStateMachineResult(for: preview)
                },
                rollback: { "Layout restored" }
            )
        )
        let preview = try await coordinator.preparePreview(
            source: .savedCue,
            makeDraft: { makeStateMachinePlan() }
        )

        let firstApply = Task {
            try await coordinator.apply(
                previewID: preview.id,
                authority: .directUserAction
            )
        }
        await applyStarted.wait()

        do {
            _ = try await coordinator.apply(
                previewID: preview.id,
                authority: .directUserAction
            )
            Issue.record("A second Apply crossed the transaction gate")
        } catch let error as ArrangementCoordinatorError {
            #expect(error == .applyAlreadyInProgress)
        }

        await applyRelease.open()
        _ = try await firstApply.value
        #expect(await mutationCount.value() == 1)
        #expect((await coordinator.currentState()).phase == .result)
    }

    @Test
    func closingUICancelsPreparationWithoutApplying() async throws {
        let parseStarted = AsyncGate()
        let mutationCount = AsyncCounter()
        let coordinator = ArrangementCoordinator(
            pipeline: ArrangementCoordinatorPipeline(
                preparePreview: { _ in .ready },
                revalidatePreview: { _ in .ready },
                apply: { preview in
                    await mutationCount.increment()
                    return makeStateMachineResult(for: preview)
                },
                rollback: { "Layout restored" }
            )
        )
        let preparation = Task {
            try await coordinator.preparePreview(
                source: .paneCueLink,
                makeDraft: {
                    await parseStarted.open()
                    try await Task.sleep(for: .seconds(30))
                    return makeStateMachinePlan()
                }
            )
        }
        await parseStarted.wait()

        await coordinator.discardPreview()

        do {
            _ = try await preparation.value
            Issue.record("A closed UI retained its parsing result")
        } catch let error as ArrangementCoordinatorError {
            #expect(error == .preparationSuperseded)
        }

        let state = await coordinator.currentState()
        #expect(state.phase == .idle)
        #expect(state.preview == nil)
        #expect(await mutationCount.value() == 0)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else {
            return
        }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor AsyncCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private func makeImmediateStateMachineCoordinator()
    -> ArrangementCoordinator {
    ArrangementCoordinator(
        pipeline: ArrangementCoordinatorPipeline(
            preparePreview: { _ in .ready },
            revalidatePreview: { _ in .ready },
            apply: { preview in
                makeStateMachineResult(for: preview)
            },
            rollback: { "Layout restored" }
        )
    )
}

private func makeStateMachinePlan() -> WorkspacePlan {
    WorkspacePlan.tiled(
        targets: [
            ScenarioWindowTarget(role: .ide),
            ScenarioWindowTarget(role: .notes)
        ]
    )
}

private func makeStateMachineResult(
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
