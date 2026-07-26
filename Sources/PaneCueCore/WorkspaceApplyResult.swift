import Foundation

public enum WorkspaceApplyOutcomeStatus: String, Codable, Hashable, Sendable {
    case moved
    case unchanged
    case skipped
    case failed
}

public struct WorkspaceApplyOutcome: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let targetName: String
    public let applicationName: String?
    public let status: WorkspaceApplyOutcomeStatus
    public let reason: String?
    public let matchesPreview: Bool

    public init(
        id: UUID,
        targetName: String,
        applicationName: String? = nil,
        status: WorkspaceApplyOutcomeStatus,
        reason: String? = nil,
        matchesPreview: Bool? = nil
    ) {
        self.id = id
        self.targetName = targetName
        self.applicationName = applicationName
        self.status = status
        self.reason = reason
        self.matchesPreview = matchesPreview ?? (status == .moved)
    }
}

public struct WorkspaceApplyResult: Codable, Hashable, Sendable {
    public let scenarioName: String
    public let outcomes: [WorkspaceApplyOutcome]
    public let canRollback: Bool

    public init(
        scenarioName: String,
        outcomes: [WorkspaceApplyOutcome],
        canRollback: Bool
    ) {
        self.scenarioName = scenarioName
        self.outcomes = outcomes
        self.canRollback = canRollback
    }

    public var movedCount: Int {
        outcomes.count { $0.status == .moved }
    }

    public var unchangedCount: Int {
        outcomes.count { $0.status == .unchanged }
    }

    public var skippedCount: Int {
        outcomes.count { $0.status == .skipped }
    }

    public var failedCount: Int {
        outcomes.count { $0.status == .failed }
    }

    public var didChangeAnyWindow: Bool {
        movedCount > 0
    }

    public var satisfiedCount: Int {
        outcomes.count { $0.matchesPreview }
    }

    public var isPartial: Bool {
        didChangeAnyWindow && satisfiedCount < outcomes.count
    }

    public var summary: String {
        let total = outcomes.count
        guard total > 0 else {
            return "No windows were available to arrange"
        }

        if satisfiedCount == total, movedCount == total {
            return "\(scenarioName) applied to \(total) window\(total == 1 ? "" : "s")"
        }

        if satisfiedCount == total, movedCount > 0 {
            let alreadyPlaced = total - movedCount
            return "\(scenarioName) ready · \(movedCount) moved, \(alreadyPlaced) already in place"
        }

        if didChangeAnyWindow {
            return "\(scenarioName) applied to \(satisfiedCount) of \(total) windows"
        }

        if satisfiedCount == total, unchangedCount == total {
            return "All \(total) windows were already in place"
        }

        return "No windows changed"
    }
}
