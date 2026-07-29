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

    public init(
        id: UUID,
        state: ArrangementTargetResolutionState
    ) {
        self.id = id
        self.state = state
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

    public subscript(slotID: UUID) -> ArrangementSlotResolution? {
        slots.first { $0.id == slotID }
    }
}

/// Converts the existing deterministic preflight into the explicit Preview
/// model without changing the v0.1 Apply implementation.
public enum WorkspaceTargetResolver {
    public static func resolve(
        scenario: CustomScenario,
        inventory: [WorkspaceWindowInventoryItem],
        hasExternalDisplay: Bool,
        hasActiveCall: Bool
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
                    )
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
}
