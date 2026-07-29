import Foundation

/// Privacy-safe metadata used to decide whether a preview can still be
/// applied. Window titles are deliberately excluded.
public struct WorkspaceWindowInventoryItem: Hashable, Identifiable, Sendable {
    public let id: String
    public let bundleIdentifier: String?
    public let applicationName: String
    public let role: ApplicationRole
    public let display: ScenarioDisplayTarget
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let canSetFrame: Bool

    public init(
        id: String,
        bundleIdentifier: String?,
        applicationName: String,
        role: ApplicationRole,
        display: ScenarioDisplayTarget = .main,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        canSetFrame: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.role = role
        self.display = display
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
    public let candidateIDs: [String]

    public init(
        id: UUID,
        targetName: String,
        status: WorkspaceApplyPreflightStatus,
        candidateIDs: [String] = []
    ) {
        self.id = id
        self.targetName = targetName
        self.status = status
        self.candidateIDs = candidateIDs
    }
}

public enum WorkspaceApplyPreflight {
    public static func evaluate(
        scenario: CustomScenario,
        inventory: [WorkspaceWindowInventoryItem],
        hasExternalDisplay: Bool,
        hasActiveCall: Bool,
        selectedCandidateIDsBySlot: [UUID: String] = [:]
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

            let candidates = matchingCandidates(
                for: slot,
                inventory: inventory,
                claimedCandidateIDs: claimedCandidateIDs,
                selectedCandidateID: selectedCandidateIDsBySlot[slot.id]
            )

            guard !candidates.isEmpty else {
                return decision(for: slot, status: .missing)
            }
            guard candidates.count == 1, let candidate = candidates.first else {
                return decision(
                    for: slot,
                    status: .ambiguous(candidateCount: candidates.count),
                    candidateIDs: candidates.map(\.id)
                )
            }

            if candidate.isFullScreen {
                return decision(
                    for: slot,
                    status: .fullScreen(candidateID: candidate.id),
                    candidateIDs: [candidate.id]
                )
            }
            if candidate.isMinimized {
                return decision(
                    for: slot,
                    status: .minimized(candidateID: candidate.id),
                    candidateIDs: [candidate.id]
                )
            }
            if !candidate.canSetFrame {
                return decision(
                    for: slot,
                    status: .unchangeable(candidateID: candidate.id),
                    candidateIDs: [candidate.id]
                )
            }

            claimedCandidateIDs.insert(candidate.id)
            return decision(
                for: slot,
                status: .ready(candidateID: candidate.id),
                candidateIDs: [candidate.id]
            )
        }
    }

    private static func decision(
        for slot: ScenarioWindowSlot,
        status: WorkspaceApplyPreflightStatus,
        candidateIDs: [String] = []
    ) -> WorkspaceApplyPreflightDecision {
        WorkspaceApplyPreflightDecision(
            id: slot.id,
            targetName: slot.target.displayName,
            status: status,
            candidateIDs: candidateIDs
        )
    }

    private static func matchingCandidates(
        for slot: ScenarioWindowSlot,
        inventory: [WorkspaceWindowInventoryItem],
        claimedCandidateIDs: Set<String>,
        selectedCandidateID: String?
    ) -> [WorkspaceWindowInventoryItem] {
        inventory.filter { candidate in
            guard !claimedCandidateIDs.contains(candidate.id),
                  matches(slot.target, candidate: candidate) else {
                return false
            }
            guard let selectedCandidateID else {
                return true
            }
            return candidate.id == selectedCandidateID
        }
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
