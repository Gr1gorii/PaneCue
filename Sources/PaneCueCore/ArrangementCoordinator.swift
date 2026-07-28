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

/// The coarse Apply gate used until slot-level resolution lands in V02-030.
public enum ArrangementPreviewEligibility: Hashable, Sendable {
    case ready
    case blocked
}

/// The one Preview representation shared by Arrange, Quick Cue, PaneCue Links,
/// and saved Cues.
public struct ArrangementPreview: Hashable, Identifiable, Sendable {
    public let draft: ArrangementDraft
    public let eligibility: ArrangementPreviewEligibility

    public init(
        draft: ArrangementDraft,
        eligibility: ArrangementPreviewEligibility
    ) {
        self.draft = draft
        self.eligibility = eligibility
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
            eligibility: eligibility
        )
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

public enum ArrangementCoordinatorError: LocalizedError, Equatable, Sendable {
    case stalePreview
    case previewNotReady
    case rollbackUnavailable

    public var errorDescription: String? {
        switch self {
        case .stalePreview:
            return "This Preview is no longer active. Review the latest plan before applying it."
        case .previewNotReady:
            return "Resolve every required window before applying this Preview."
        case .rollbackUnavailable:
            return "There is no arrangement available to restore."
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
        (ArrangementDraft) async throws -> ArrangementPreviewEligibility
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
    private var activePreview: ArrangementPreview?
    private var canRollback = false

    public init(pipeline: ArrangementCoordinatorPipeline) {
        self.pipeline = pipeline
    }

    public func preparePreview(
        id: UUID = UUID(),
        source: ArrangementRequestSource,
        makeDraft: @Sendable () async throws -> WorkspacePlan
    ) async throws -> ArrangementPreview {
        let plan = try await makeDraft()
        let draft = ArrangementDraft(
            id: id,
            source: source,
            plan: plan
        )
        let eligibility = try await pipeline.preparePreview(draft)
        let preview = ArrangementPreview(
            draft: draft,
            eligibility: eligibility
        )
        activePreview = preview
        return preview
    }

    public func currentPreview() -> ArrangementPreview? {
        activePreview
    }

    public func discardPreview(id: UUID? = nil) {
        guard id == nil || activePreview?.id == id else {
            return
        }
        activePreview = nil
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

        let eligibility = try await pipeline.revalidatePreview(preview)
        let revalidatedPreview = preview.revalidated(as: eligibility)
        activePreview = revalidatedPreview

        guard eligibility == .ready else {
            throw ArrangementCoordinatorError.previewNotReady
        }

        let result = try await pipeline.apply(revalidatedPreview)
        canRollback = result.canRollback
        return result
    }

    public func rollback(
        authority: ArrangementRollbackAuthority
    ) async throws -> String {
        switch authority {
        case .directUserAction:
            break
        }

        guard canRollback else {
            throw ArrangementCoordinatorError.rollbackUnavailable
        }

        let summary = try await pipeline.rollback()
        canRollback = false
        return summary
    }
}
