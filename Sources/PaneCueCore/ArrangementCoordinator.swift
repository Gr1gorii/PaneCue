import Foundation

/// The four product surfaces that may create an arrangement Preview.
///
/// This is deliberately safe metadata. The originating command, transcript,
/// window title, document path, and URL are never retained by the coordinator.
public enum ArrangementRequestSource: String, CaseIterable, Codable, Sendable {
    case arrange
    case quickCue
    case paneCueLink
    case savedCue
}

/// An in-memory draft produced by local parsing or by loading a saved Cue.
public struct ArrangementDraft: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let source: ArrangementRequestSource
    public let plan: WorkspacePlan

    public init(
        id: UUID = UUID(),
        source: ArrangementRequestSource,
        plan: WorkspacePlan
    ) {
        self.id = id
        self.source = source
        self.plan = plan
    }
}

/// The coarse Apply gate derived from slot-level resolution and plan validity.
public enum ArrangementPreviewEligibility: Hashable, Sendable {
    case ready
    case blocked
}

/// The one Preview representation shared by Arrange, Quick Cue, PaneCue Links,
/// and saved Cues.
public struct ArrangementPreview: Hashable, Identifiable, Sendable {
    public let draft: ArrangementDraft
    public let eligibility: ArrangementPreviewEligibility
    public let resolution: ArrangementTargetResolutionSet?

    public init(
        draft: ArrangementDraft,
        eligibility: ArrangementPreviewEligibility,
        resolution: ArrangementTargetResolutionSet? = nil
    ) {
        self.draft = draft
        self.eligibility = eligibility
        self.resolution = resolution
    }

    public var id: UUID {
        draft.id
    }

    public var source: ArrangementRequestSource {
        draft.source
    }

    public var plan: WorkspacePlan {
        draft.plan
    }

    fileprivate func revalidated(
        as eligibility: ArrangementPreviewEligibility
    ) -> ArrangementPreview {
        ArrangementPreview(
            draft: draft,
            eligibility: eligibility,
            resolution: resolution
        )
    }

    fileprivate func updating(
        resolution: ArrangementTargetResolutionSet
    ) -> ArrangementPreview {
        ArrangementPreview(
            draft: draft,
            eligibility: draft.plan.windows.count >= 2
                && !resolution.requiresCandidateSelection
                ? .ready
                : .blocked,
            resolution: resolution
        )
    }

    fileprivate func updating(plan: WorkspacePlan) -> ArrangementPreview {
        ArrangementPreview(
            draft: ArrangementDraft(
                id: draft.id,
                source: draft.source,
                plan: plan
            ),
            eligibility: eligibility,
            resolution: resolution
        )
    }
}

/// The result of the Preview preparation boundary. Legacy callers may return
/// `.ready` or `.blocked`; Arrange supplies the full slot-level resolution.
public struct ArrangementPreviewPreparation: Hashable, Sendable {
    public let eligibility: ArrangementPreviewEligibility
    public let resolution: ArrangementTargetResolutionSet?

    public static let ready = ArrangementPreviewPreparation(
        eligibility: .ready
    )
    public static let blocked = ArrangementPreviewPreparation(
        eligibility: .blocked
    )

    public init(eligibility: ArrangementPreviewEligibility) {
        self.eligibility = eligibility
        resolution = nil
    }

    public init(
        resolution: ArrangementTargetResolutionSet,
        isPlanValid: Bool = true
    ) {
        self.resolution = resolution
        eligibility = isPlanValid && !resolution.requiresCandidateSelection
            ? .ready
            : .blocked
    }
}

/// Apply can only be requested by a visible, direct action inside PaneCue.
/// There is intentionally no default value at the coordinator call site.
public enum ArrangementApplyAuthority: Sendable {
    case directUserAction
}

/// Undo and Rollback use the same explicit-authority rule as Apply.
public enum ArrangementRollbackAuthority: Sendable {
    case directUserAction
}

public enum ArrangementCoordinatorPhase: String, Codable, Hashable, Sendable {
    case idle
    case editing
    case parsing
    case resolving
    case awaitingSelection
    case ready
    case applying
    case result
    case restoring
}

public struct ArrangementCoordinatorState: Hashable, Sendable {
    public let phase: ArrangementCoordinatorPhase
    public let preview: ArrangementPreview?
    public let result: WorkspaceApplyResult?
    public let canRollback: Bool

    public var canApply: Bool {
        phase == .ready
    }

    fileprivate init(
        phase: ArrangementCoordinatorPhase,
        preview: ArrangementPreview?,
        result: WorkspaceApplyResult?,
        canRollback: Bool
    ) {
        self.phase = phase
        self.preview = preview
        self.result = result
        self.canRollback = canRollback
    }
}

public enum ArrangementCoordinatorError: LocalizedError, Equatable, Sendable {
    case preparationSuperseded
    case stalePreview
    case previewNotReady
    case applyUnavailable
    case applyAlreadyInProgress
    case rollbackUnavailable
    case restoreAlreadyInProgress
    case transactionInProgress

    public var errorDescription: String? {
        switch self {
        case .preparationSuperseded:
            return "A newer arrangement request replaced this one."
        case .stalePreview:
            return "This Preview is no longer active. Review the latest plan before applying it."
        case .previewNotReady:
            return "Resolve every required window before applying this Preview."
        case .applyUnavailable:
            return "Apply is available only for a ready Preview."
        case .applyAlreadyInProgress:
            return "PaneCue is already applying an arrangement."
        case .rollbackUnavailable:
            return "There is no arrangement available to restore."
        case .restoreAlreadyInProgress:
            return "PaneCue is already restoring an arrangement."
        case .transactionInProgress:
            return "Wait for the current arrangement operation to finish."
        }
    }
}

/// Injectable boundaries for the arrangement pipeline.
///
/// `preparePreview` is the target-resolution boundary. `revalidatePreview`
/// runs immediately before Apply. `apply` is the sole mutation boundary and
/// is where the versioned Journal adapter will wrap window mutation in
/// V02-060. Keeping these operations behind one value prevents entry points
/// from growing independent execution paths.
public struct ArrangementCoordinatorPipeline: Sendable {
    public typealias PreviewPreparation = @Sendable
        (ArrangementDraft) async throws -> ArrangementPreviewPreparation
    public typealias PreviewRevalidation = @Sendable
        (ArrangementPreview) async throws -> ArrangementPreviewEligibility
    public typealias ApplyExecution = @MainActor @Sendable
        (ArrangementPreview) async throws -> WorkspaceApplyResult
    public typealias RollbackExecution = @MainActor @Sendable
        () async throws -> String

    fileprivate let preparePreview: PreviewPreparation
    fileprivate let revalidatePreview: PreviewRevalidation
    fileprivate let apply: ApplyExecution
    fileprivate let rollback: RollbackExecution

    public init(
        preparePreview: @escaping PreviewPreparation,
        revalidatePreview: @escaping PreviewRevalidation,
        apply: @escaping ApplyExecution,
        rollback: @escaping RollbackExecution
    ) {
        self.preparePreview = preparePreview
        self.revalidatePreview = revalidatePreview
        self.apply = apply
        self.rollback = rollback
    }
}

/// The single orchestration boundary for all PaneCue arrangement consumers.
///
/// A consumer supplies local draft work as a non-retained closure. The
/// coordinator then owns Preview preparation, the explicit Apply gate,
/// revalidation, the one execution boundary, result tracking, and Rollback.
/// Closing a UI should call `discardPreview`; it never causes Apply.
public actor ArrangementCoordinator {
    private let pipeline: ArrangementCoordinatorPipeline
    private var phase: ArrangementCoordinatorPhase = .idle
    private var activePreview: ArrangementPreview?
    private var lastResult: WorkspaceApplyResult?
    private var canRollback = false
    private var preparationID: UUID?
    private var parsingTask: Task<WorkspacePlan, Error>?

    public init(pipeline: ArrangementCoordinatorPipeline) {
        self.pipeline = pipeline
    }

    public func currentState() -> ArrangementCoordinatorState {
        ArrangementCoordinatorState(
            phase: phase,
            preview: activePreview,
            result: lastResult,
            canRollback: canRollback
        )
    }

    public func beginEditing() {
        guard !isTransactionInProgress else {
            return
        }
        supersedePreparation()
        activePreview = nil
        lastResult = nil
        canRollback = false
        phase = .editing
    }

    public func preparePreview(
        id: UUID = UUID(),
        source: ArrangementRequestSource,
        makeDraft: @escaping @Sendable () async throws -> WorkspacePlan
    ) async throws -> ArrangementPreview {
        guard !isTransactionInProgress else {
            throw ArrangementCoordinatorError.transactionInProgress
        }

        supersedePreparation()
        let requestID = UUID()
        preparationID = requestID
        activePreview = nil
        lastResult = nil
        canRollback = false
        phase = .parsing

        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let plan = try await makeDraft()
            try Task.checkCancellation()
            return plan
        }
        parsingTask = task

        let plan: WorkspacePlan
        do {
            plan = try await task.value
        } catch {
            guard preparationID == requestID else {
                throw ArrangementCoordinatorError.preparationSuperseded
            }
            finishPreparation()
            phase = .editing
            if error is CancellationError {
                throw ArrangementCoordinatorError.preparationSuperseded
            }
            throw error
        }

        guard preparationID == requestID else {
            throw ArrangementCoordinatorError.preparationSuperseded
        }
        parsingTask = nil
        phase = .resolving

        let draft = ArrangementDraft(
            id: id,
            source: source,
            plan: plan
        )
        let preparation: ArrangementPreviewPreparation
        do {
            preparation = try await pipeline.preparePreview(draft)
        } catch {
            guard preparationID == requestID else {
                throw ArrangementCoordinatorError.preparationSuperseded
            }
            finishPreparation()
            phase = .editing
            throw error
        }

        guard preparationID == requestID else {
            throw ArrangementCoordinatorError.preparationSuperseded
        }
        finishPreparation()
        let preview = ArrangementPreview(
            draft: draft,
            eligibility: preparation.eligibility,
            resolution: preparation.resolution
        )
        activePreview = preview
        phase = phaseForEligibility(preparation.eligibility)
        return preview
    }

    public func currentPreview() -> ArrangementPreview? {
        activePreview
    }

    @discardableResult
    public func updatePreviewEligibility(
        previewID: UUID,
        eligibility: ArrangementPreviewEligibility
    ) throws -> ArrangementPreview {
        guard let preview = activePreview,
              preview.id == previewID else {
            throw ArrangementCoordinatorError.stalePreview
        }
        guard phase == .awaitingSelection || phase == .ready else {
            throw ArrangementCoordinatorError.applyUnavailable
        }

        let updated = preview.revalidated(as: eligibility)
        activePreview = updated
        phase = phaseForEligibility(eligibility)
        return updated
    }

    @discardableResult
    public func selectCandidate(
        previewID: UUID,
        slotID: UUID,
        candidateID: EphemeralWindowIdentifier
    ) throws -> ArrangementPreview {
        guard let preview = activePreview,
              preview.id == previewID else {
            throw ArrangementCoordinatorError.stalePreview
        }
        guard phase == .awaitingSelection || phase == .ready else {
            throw ArrangementCoordinatorError.applyUnavailable
        }
        guard let resolution = preview.resolution else {
            throw ArrangementTargetSelectionError.slotUnavailable
        }

        let updatedResolution = try resolution.selecting(
            candidateID,
            for: slotID
        )
        let updated = preview.updating(resolution: updatedResolution)
        activePreview = updated
        phase = phaseForEligibility(updated.eligibility)
        return updated
    }

    @discardableResult
    public func updatePreviewPlan(
        previewID: UUID,
        plan: WorkspacePlan
    ) throws -> ArrangementPreview {
        guard let preview = activePreview,
              preview.id == previewID else {
            throw ArrangementCoordinatorError.stalePreview
        }
        guard phase == .awaitingSelection || phase == .ready else {
            throw ArrangementCoordinatorError.applyUnavailable
        }

        let updated = preview.updating(plan: plan)
        activePreview = updated
        return updated
    }

    public func discardPreview(id: UUID? = nil) {
        guard !isTransactionInProgress else {
            return
        }
        guard id == nil || activePreview?.id == id else {
            return
        }
        supersedePreparation()
        activePreview = nil
        lastResult = nil
        canRollback = false
        phase = .idle
    }

    public func apply(
        previewID: UUID,
        authority: ArrangementApplyAuthority
    ) async throws -> WorkspaceApplyResult {
        switch authority {
        case .directUserAction:
            break
        }

        guard let preview = activePreview,
              preview.id == previewID else {
            throw ArrangementCoordinatorError.stalePreview
        }
        if phase == .applying {
            throw ArrangementCoordinatorError.applyAlreadyInProgress
        }
        guard phase == .ready else {
            if phase == .awaitingSelection {
                throw ArrangementCoordinatorError.previewNotReady
            }
            throw ArrangementCoordinatorError.applyUnavailable
        }

        phase = .applying
        let eligibility: ArrangementPreviewEligibility
        do {
            eligibility = try await pipeline.revalidatePreview(preview)
        } catch {
            phase = .ready
            throw error
        }
        let revalidatedPreview = preview.revalidated(as: eligibility)
        activePreview = revalidatedPreview

        guard eligibility == .ready else {
            phase = .awaitingSelection
            throw ArrangementCoordinatorError.previewNotReady
        }

        let result: WorkspaceApplyResult
        do {
            result = try await pipeline.apply(revalidatedPreview)
        } catch {
            phase = .ready
            throw error
        }
        lastResult = result
        canRollback = result.canRollback
        phase = .result
        return result
    }

    public func rollback(
        authority: ArrangementRollbackAuthority
    ) async throws -> String {
        switch authority {
        case .directUserAction:
            break
        }

        if phase == .restoring {
            throw ArrangementCoordinatorError.restoreAlreadyInProgress
        }
        guard phase == .result, canRollback else {
            throw ArrangementCoordinatorError.rollbackUnavailable
        }

        phase = .restoring
        let summary: String
        do {
            summary = try await pipeline.rollback()
        } catch {
            phase = .result
            throw error
        }
        canRollback = false
        activePreview = nil
        lastResult = nil
        phase = .idle
        return summary
    }

    private var isTransactionInProgress: Bool {
        phase == .applying || phase == .restoring
    }

    private func phaseForEligibility(
        _ eligibility: ArrangementPreviewEligibility
    ) -> ArrangementCoordinatorPhase {
        switch eligibility {
        case .ready:
            return .ready
        case .blocked:
            return .awaitingSelection
        }
    }

    private func supersedePreparation() {
        parsingTask?.cancel()
        finishPreparation()
    }

    private func finishPreparation() {
        parsingTask = nil
        preparationID = nil
    }
}
