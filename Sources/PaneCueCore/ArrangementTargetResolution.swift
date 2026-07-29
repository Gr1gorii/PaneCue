import Foundation

/// An identifier that is valid only for the current local window inventory.
///
/// It is intentionally not `Codable`: Preview may use it to bind a visible
/// choice, but corrections, diagnostics, and the Apply Journal must not retain
/// this value as durable application data.
public struct EphemeralWindowIdentifier: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The explainable reason that produced a resolved Preview target.
/// User-facing copy lands in V02-032; this enum keeps the Core contract free
/// of confidence percentages and localized prose.
public enum ArrangementTargetMatchReason: Hashable, Sendable {
    case specificApplication
    case matchedRole(ApplicationRole)
    case selectedByUser
    case onlyMatchingWindow
    case savedCueMapping
}

/// Privacy-safe metadata for the exact window selected for a Preview slot.
/// Window titles, document paths, URLs, and content are deliberately absent.
public struct ResolvedArrangementTarget: Hashable, Sendable {
    public let bundleIdentifier: String
    public let windowIdentifier: EphemeralWindowIdentifier
    public let display: ScenarioDisplayTarget
    public let matchReason: ArrangementTargetMatchReason
    public let localizedApplicationName: String

    public init(
        bundleIdentifier: String,
        windowIdentifier: EphemeralWindowIdentifier,
        display: ScenarioDisplayTarget,
        matchReason: ArrangementTargetMatchReason,
        localizedApplicationName: String
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.windowIdentifier = windowIdentifier
        self.display = display
        self.matchReason = matchReason
        self.localizedApplicationName = localizedApplicationName
    }
}

/// Why a matching slot cannot currently become a resolved target.
public enum UnsupportedArrangementTargetReason: Hashable, Sendable {
    case fullScreen
    case minimized
    case unchangeable
    case externalDisplayUnavailable
    case conditionNotMet
    case missingBundleIdentifier
}

/// One local candidate shown by Preview while the user resolves ambiguity.
/// The optional differentiator is display-only ephemeral data. This type is
/// deliberately not `Codable`, so titles cannot enter saved Cues, corrections,
/// diagnostics, or the Apply Journal through this model.
public struct ArrangementTargetCandidate: Hashable, Identifiable, Sendable {
    public let windowIdentifier: EphemeralWindowIdentifier
    public let bundleIdentifier: String?
    public let display: ScenarioDisplayTarget
    public let localizedApplicationName: String
    public let localDifferentiator: String?
    public let unsupportedReason: UnsupportedArrangementTargetReason?

    public var id: EphemeralWindowIdentifier {
        windowIdentifier
    }

    public var isSelectable: Bool {
        bundleIdentifier != nil && unsupportedReason == nil
    }

    public init(
        windowIdentifier: EphemeralWindowIdentifier,
        bundleIdentifier: String?,
        display: ScenarioDisplayTarget,
        localizedApplicationName: String,
        localDifferentiator: String? = nil,
        unsupportedReason: UnsupportedArrangementTargetReason? = nil
    ) {
        self.windowIdentifier = windowIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.display = display
        self.localizedApplicationName = localizedApplicationName
        self.localDifferentiator = localDifferentiator
        self.unsupportedReason = unsupportedReason
    }
}

/// The frozen v0.2 target-resolution states for one Preview slot.
public enum ArrangementTargetResolutionState: Hashable, Sendable {
    case resolved(ResolvedArrangementTarget)
    case ambiguous(candidateCount: Int)
    case missing
    case unsupported(UnsupportedArrangementTargetReason)

    public var isResolved: Bool {
        if case .resolved = self {
            return true
        }
        return false
    }
}

public struct ArrangementSlotResolution: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let state: ArrangementTargetResolutionState
    public let candidates: [ArrangementTargetCandidate]

    public init(
        id: UUID,
        state: ArrangementTargetResolutionState,
        candidates: [ArrangementTargetCandidate] = []
    ) {
        self.id = id
        self.state = state
        self.candidates = candidates
    }
}

public enum ArrangementTargetSelectionError: LocalizedError, Equatable,
    Sendable {
    case slotUnavailable
    case slotDoesNotNeedSelection
    case candidateUnavailable
    case candidateUnsupported

    public var errorDescription: String? {
        switch self {
        case .slotUnavailable:
            return "This Preview slot is no longer available."
        case .slotDoesNotNeedSelection:
            return "This Preview slot no longer needs a window selection."
        case .candidateUnavailable:
            return "This window is no longer a candidate for the selected slot."
        case .candidateUnsupported:
            return "This window cannot be arranged in its current state."
        }
    }
}

/// One complete, ordered resolution pass for a Preview.
public struct ArrangementTargetResolutionSet: Hashable, Sendable {
    public let slots: [ArrangementSlotResolution]

    public init(slots: [ArrangementSlotResolution]) {
        self.slots = slots
    }

    public var isReadyForApply: Bool {
        !slots.isEmpty && slots.allSatisfy { $0.state.isResolved }
    }

    /// Ambiguity is the only state that requires a direct candidate choice.
    /// Missing or unsupported targets may still produce the existing partial
    /// Apply result or be launched by the application layer.
    public var requiresCandidateSelection: Bool {
        slots.contains { slot in
            if case .ambiguous = slot.state {
                return true
            }
            return false
        }
    }

    public subscript(slotID: UUID) -> ArrangementSlotResolution? {
        slots.first { $0.id == slotID }
    }

    public var selectedCandidateIDsBySlot: [UUID: String] {
        slots.reduce(into: [:]) { result, slot in
            guard case let .resolved(target) = slot.state else {
                return
            }
            result[slot.id] = target.windowIdentifier.rawValue
        }
    }

    public func selecting(
        _ candidateID: EphemeralWindowIdentifier,
        for slotID: UUID
    ) throws -> ArrangementTargetResolutionSet {
        guard let selectedSlot = self[slotID] else {
            throw ArrangementTargetSelectionError.slotUnavailable
        }
        guard case .ambiguous = selectedSlot.state else {
            throw ArrangementTargetSelectionError.slotDoesNotNeedSelection
        }
        guard let selectedCandidate = selectedSlot.candidates.first(
            where: { $0.id == candidateID }
        ) else {
            throw ArrangementTargetSelectionError.candidateUnavailable
        }
        guard selectedCandidate.isSelectable else {
            throw ArrangementTargetSelectionError.candidateUnsupported
        }

        return ArrangementTargetResolutionSet(
            slots: slots.map { slot in
                if slot.id == slotID {
                    return ArrangementSlotResolution(
                        id: slot.id,
                        state: resolvedState(
                            for: selectedCandidate,
                            reason: .selectedByUser
                        ),
                        candidates: slot.candidates
                    )
                }

                guard case .ambiguous = slot.state,
                      slot.candidates.contains(where: {
                          $0.id == candidateID
                      }) else {
                    return slot
                }

                let remaining = slot.candidates.filter {
                    $0.id != candidateID
                }
                return ArrangementSlotResolution(
                    id: slot.id,
                    state: stateAfterClaimingCandidate(from: remaining),
                    candidates: remaining
                )
            }
        )
    }

    private func stateAfterClaimingCandidate(
        from candidates: [ArrangementTargetCandidate]
    ) -> ArrangementTargetResolutionState {
        switch candidates.count {
        case 0:
            return .missing
        case 1:
            return resolvedState(
                for: candidates[0],
                reason: .onlyMatchingWindow
            )
        default:
            return .ambiguous(candidateCount: candidates.count)
        }
    }

    private func resolvedState(
        for candidate: ArrangementTargetCandidate,
        reason: ArrangementTargetMatchReason
    ) -> ArrangementTargetResolutionState {
        if let unsupportedReason = candidate.unsupportedReason {
            return .unsupported(unsupportedReason)
        }
        guard let bundleIdentifier = candidate.bundleIdentifier else {
            return .unsupported(.missingBundleIdentifier)
        }
        return .resolved(
            ResolvedArrangementTarget(
                bundleIdentifier: bundleIdentifier,
                windowIdentifier: candidate.windowIdentifier,
                display: candidate.display,
                matchReason: reason,
                localizedApplicationName:
                    candidate.localizedApplicationName
            )
        )
    }
}

/// Converts the existing deterministic preflight into the explicit Preview
/// model without changing the v0.1 Apply implementation.
public enum WorkspaceTargetResolver {
    public static func resolve(
        scenario: CustomScenario,
        inventory: [WorkspaceWindowInventoryItem],
        hasExternalDisplay: Bool,
        hasActiveCall: Bool,
        localDifferentiators: [EphemeralWindowIdentifier: String] = [:]
    ) -> ArrangementTargetResolutionSet {
        let inventoryByID = inventory.reduce(into: [:]) { result, item in
            result[item.id] = item
        }
        let slotsByID = scenario.windows.reduce(into: [:]) { result, slot in
            result[slot.id] = slot
        }
        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: inventory,
            hasExternalDisplay: hasExternalDisplay,
            hasActiveCall: hasActiveCall
        )

        return ArrangementTargetResolutionSet(
            slots: decisions.map { decision in
                ArrangementSlotResolution(
                    id: decision.id,
                    state: state(
                        for: decision,
                        slot: slotsByID[decision.id],
                        inventoryByID: inventoryByID
                    ),
                    candidates: decision.candidateIDs.compactMap {
                        candidate(
                            inventoryByID[$0],
                            localDifferentiators: localDifferentiators
                        )
                    }
                )
            }
        )
    }

    private static func state(
        for decision: WorkspaceApplyPreflightDecision,
        slot: ScenarioWindowSlot?,
        inventoryByID: [String: WorkspaceWindowInventoryItem]
    ) -> ArrangementTargetResolutionState {
        switch decision.status {
        case let .ready(candidateID):
            guard let candidate = inventoryByID[candidateID],
                  let slot else {
                return .missing
            }
            guard let bundleIdentifier = candidate.bundleIdentifier else {
                return .unsupported(.missingBundleIdentifier)
            }
            return .resolved(
                ResolvedArrangementTarget(
                    bundleIdentifier: bundleIdentifier,
                    windowIdentifier: EphemeralWindowIdentifier(
                        rawValue: candidate.id
                    ),
                    display: candidate.display,
                    matchReason: matchReason(for: slot.target),
                    localizedApplicationName: candidate.applicationName
                )
            )

        case let .ambiguous(candidateCount):
            return .ambiguous(candidateCount: candidateCount)
        case .missing:
            return .missing
        case .fullScreen:
            return .unsupported(.fullScreen)
        case .minimized:
            return .unsupported(.minimized)
        case .unchangeable:
            return .unsupported(.unchangeable)
        case .externalDisplayUnavailable:
            return .unsupported(.externalDisplayUnavailable)
        case .conditionNotMet:
            return .unsupported(.conditionNotMet)
        }
    }

    private static func matchReason(
        for target: ScenarioWindowTarget
    ) -> ArrangementTargetMatchReason {
        switch target.kind {
        case .application:
            return .specificApplication
        case .role:
            return .matchedRole(target.role ?? .other)
        }
    }

    private static func candidate(
        _ item: WorkspaceWindowInventoryItem?,
        localDifferentiators: [EphemeralWindowIdentifier: String]
    ) -> ArrangementTargetCandidate? {
        guard let item else {
            return nil
        }
        let identifier = EphemeralWindowIdentifier(rawValue: item.id)
        return ArrangementTargetCandidate(
            windowIdentifier: identifier,
            bundleIdentifier: item.bundleIdentifier,
            display: item.display,
            localizedApplicationName: item.applicationName,
            localDifferentiator: localDifferentiators[identifier],
            unsupportedReason: unsupportedReason(for: item)
        )
    }

    private static func unsupportedReason(
        for item: WorkspaceWindowInventoryItem
    ) -> UnsupportedArrangementTargetReason? {
        if item.isFullScreen {
            return .fullScreen
        }
        if item.isMinimized {
            return .minimized
        }
        if !item.canSetFrame {
            return .unchangeable
        }
        if item.bundleIdentifier == nil {
            return .missingBundleIdentifier
        }
        return nil
    }
}
