import Foundation

/// Privacy-safe metadata used to decide whether a preview can still be
/// applied. Window titles are deliberately excluded.
public struct WorkspaceWindowInventoryItem: Hashable, Identifiable, Sendable {
    public let id: String
    public let bundleIdentifier: String?
    public let applicationName: String
    public let role: ApplicationRole
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let canSetFrame: Bool

    public init(
        id: String,
        bundleIdentifier: String?,
        applicationName: String,
        role: ApplicationRole,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        canSetFrame: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.role = role
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.canSetFrame = canSetFrame
    }
}

public enum WorkspaceApplyPreflightStatus: Hashable, Sendable {
    case ready(candidateID: String)
    case missing
    case ambiguous(candidateCount: Int)
    case fullScreen(candidateID: String)
    case minimized(candidateID: String)
    case unchangeable(candidateID: String)
    case externalDisplayUnavailable
    case conditionNotMet

    public var candidateID: String? {
        switch self {
        case let .ready(candidateID),
             let .fullScreen(candidateID),
             let .minimized(candidateID),
             let .unchangeable(candidateID):
            return candidateID
        case .missing,
             .ambiguous,
             .externalDisplayUnavailable,
             .conditionNotMet:
            return nil
        }
    }
}

public struct WorkspaceApplyPreflightDecision: Hashable, Identifiable,
    Sendable {
    public let id: UUID
    public let targetName: String
    public let status: WorkspaceApplyPreflightStatus

    public init(
        id: UUID,
        targetName: String,
        status: WorkspaceApplyPreflightStatus
    ) {
        self.id = id
        self.targetName = targetName
        self.status = status
    }
}

public enum WorkspaceApplyPreflight {
    public static func evaluate(
        scenario: CustomScenario,
        inventory: [WorkspaceWindowInventoryItem],
        hasExternalDisplay: Bool,
        hasActiveCall: Bool
    ) -> [WorkspaceApplyPreflightDecision] {
        if scenario.conditions.requiresExternalDisplay,
           !hasExternalDisplay {
            return scenario.windows.map {
                decision(for: $0, status: .conditionNotMet)
            }
        }

        if scenario.conditions.onlyDuringCall, !hasActiveCall {
            return scenario.windows.map {
                decision(for: $0, status: .conditionNotMet)
            }
        }

        var claimedCandidateIDs: Set<String> = []
        return scenario.windows.map { slot in
            if slot.display == .external, !hasExternalDisplay {
                return decision(
                    for: slot,
                    status: .externalDisplayUnavailable
                )
            }

            let candidates = inventory.filter { candidate in
                matches(slot.target, candidate: candidate)
                    && !claimedCandidateIDs.contains(candidate.id)
            }

            guard !candidates.isEmpty else {
                return decision(for: slot, status: .missing)
            }
            guard candidates.count == 1, let candidate = candidates.first else {
                return decision(
                    for: slot,
                    status: .ambiguous(candidateCount: candidates.count)
                )
            }

            if candidate.isFullScreen {
                return decision(
                    for: slot,
                    status: .fullScreen(candidateID: candidate.id)
                )
            }
            if candidate.isMinimized {
                return decision(
                    for: slot,
                    status: .minimized(candidateID: candidate.id)
                )
            }
            if !candidate.canSetFrame {
                return decision(
                    for: slot,
                    status: .unchangeable(candidateID: candidate.id)
                )
            }

            claimedCandidateIDs.insert(candidate.id)
            return decision(
                for: slot,
                status: .ready(candidateID: candidate.id)
            )
        }
    }

    private static func decision(
        for slot: ScenarioWindowSlot,
        status: WorkspaceApplyPreflightStatus
    ) -> WorkspaceApplyPreflightDecision {
        WorkspaceApplyPreflightDecision(
            id: slot.id,
            targetName: slot.target.displayName,
            status: status
        )
    }

    private static func matches(
        _ target: ScenarioWindowTarget,
        candidate: WorkspaceWindowInventoryItem
    ) -> Bool {
        switch target.kind {
        case .application:
            guard let expected = target.application?.bundleIdentifier,
                  let actual = candidate.bundleIdentifier else {
                return false
            }
            return actual.caseInsensitiveCompare(expected) == .orderedSame
        case .role:
            return candidate.role == (target.role ?? .other)
        }
    }
}
