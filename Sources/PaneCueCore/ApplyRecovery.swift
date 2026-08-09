import Foundation

public struct ApplyRecoveryCandidate: Hashable, Sendable {
    public let windowIdentifier: String
    public let applicationBundleIdentifier: String?
    public let processIdentifier: Int32

    public init(
        windowIdentifier: String,
        applicationBundleIdentifier: String?,
        processIdentifier: Int32
    ) {
        self.windowIdentifier = windowIdentifier
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public enum ApplyRecoveryMatchState: Equatable, Sendable {
    case matched(candidateWindowIdentifier: String)
    case missing
    case ambiguous
    case displayUnavailable
}

public struct ApplyRecoveryWindowResolution: Equatable, Sendable {
    public let journalWindowIdentifier: String
    public let state: ApplyRecoveryMatchState

    public init(
        journalWindowIdentifier: String,
        state: ApplyRecoveryMatchState
    ) {
        self.journalWindowIdentifier = journalWindowIdentifier
        self.state = state
    }
}

public struct ApplyRecoveryPlan: Equatable, Sendable {
    public let transactionID: UUID
    public let windows: [ApplyRecoveryWindowResolution]

    public init(
        transactionID: UUID,
        windows: [ApplyRecoveryWindowResolution]
    ) {
        self.transactionID = transactionID
        self.windows = windows
    }

    public var restorableWindowCount: Int {
        windows.count {
            if case .matched = $0.state {
                return true
            }
            return false
        }
    }
}

public enum ApplyRecoveryPlanner {
    public static func plan(
        transaction: ApplyJournalTransaction,
        candidates: [ApplyRecoveryCandidate],
        availableDisplaySignatures: Set<String>
    ) -> ApplyRecoveryPlan {
        var resolutions = Array<ApplyRecoveryWindowResolution?>(
            repeating: nil,
            count: transaction.windows.count
        )
        var usedCandidateIdentifiers = Set<String>()
        var unresolvedByIdentity: [WindowIdentity: [Int]] = [:]

        for (index, window) in transaction.windows.enumerated() {
            guard availableDisplaySignatures.contains(
                window.originalDisplaySignature
            ) else {
                resolutions[index] = ApplyRecoveryWindowResolution(
                    journalWindowIdentifier: window.windowIdentifier,
                    state: .displayUnavailable
                )
                continue
            }

            let identity = WindowIdentity(
                applicationBundleIdentifier:
                    window.applicationBundleIdentifier,
                processIdentifier: window.processIdentifier
            )
            let identityCandidates = candidates.filter {
                identity.matches($0)
                    && !usedCandidateIdentifiers.contains(
                        $0.windowIdentifier
                    )
            }
            let exactCandidates = identityCandidates.filter {
                $0.windowIdentifier == window.windowIdentifier
            }

            if exactCandidates.count == 1,
               let exactCandidate = exactCandidates.first {
                usedCandidateIdentifiers.insert(
                    exactCandidate.windowIdentifier
                )
                resolutions[index] = ApplyRecoveryWindowResolution(
                    journalWindowIdentifier: window.windowIdentifier,
                    state: .matched(
                        candidateWindowIdentifier:
                            exactCandidate.windowIdentifier
                    )
                )
            } else if exactCandidates.count > 1 {
                resolutions[index] = ApplyRecoveryWindowResolution(
                    journalWindowIdentifier: window.windowIdentifier,
                    state: .ambiguous
                )
            } else {
                unresolvedByIdentity[identity, default: []].append(index)
            }
        }

        for (identity, recordIndexes) in unresolvedByIdentity {
            let availableCandidates = candidates.filter {
                identity.matches($0)
                    && !usedCandidateIdentifiers.contains(
                        $0.windowIdentifier
                    )
            }

            if recordIndexes.count == 1,
               availableCandidates.count == 1,
               let recordIndex = recordIndexes.first,
               let candidate = availableCandidates.first {
                usedCandidateIdentifiers.insert(candidate.windowIdentifier)
                let window = transaction.windows[recordIndex]
                resolutions[recordIndex] = ApplyRecoveryWindowResolution(
                    journalWindowIdentifier: window.windowIdentifier,
                    state: .matched(
                        candidateWindowIdentifier: candidate.windowIdentifier
                    )
                )
                continue
            }

            let state: ApplyRecoveryMatchState = availableCandidates.isEmpty
                ? .missing
                : .ambiguous
            for recordIndex in recordIndexes {
                let window = transaction.windows[recordIndex]
                resolutions[recordIndex] = ApplyRecoveryWindowResolution(
                    journalWindowIdentifier: window.windowIdentifier,
                    state: state
                )
            }
        }

        return ApplyRecoveryPlan(
            transactionID: transaction.id,
            windows: resolutions.enumerated().map { index, resolution in
                resolution ?? ApplyRecoveryWindowResolution(
                    journalWindowIdentifier:
                        transaction.windows[index].windowIdentifier,
                    state: .missing
                )
            }
        )
    }
}

public enum ApplyRecoveryOutcomeState: Equatable, Sendable {
    case restored
    case unchanged
    case skippedMissing
    case skippedAmbiguous
    case skippedDisplayUnavailable
    case failed
}

public struct ApplyRecoveryWindowOutcome: Equatable, Sendable {
    public let journalWindowIdentifier: String
    public let state: ApplyRecoveryOutcomeState

    public init(
        journalWindowIdentifier: String,
        state: ApplyRecoveryOutcomeState
    ) {
        self.journalWindowIdentifier = journalWindowIdentifier
        self.state = state
    }
}

public struct ApplyRecoveryResult: Equatable, Sendable {
    public let transactionID: UUID
    public let outcomes: [ApplyRecoveryWindowOutcome]
    public let didPersistCompletion: Bool

    public init(
        transactionID: UUID,
        outcomes: [ApplyRecoveryWindowOutcome],
        didPersistCompletion: Bool
    ) {
        self.transactionID = transactionID
        self.outcomes = outcomes
        self.didPersistCompletion = didPersistCompletion
    }

    public var restoredCount: Int {
        count(.restored)
    }

    public var unchangedCount: Int {
        count(.unchanged)
    }

    public var skippedCount: Int {
        missingCount + ambiguousCount + displayUnavailableCount
    }

    public var missingCount: Int {
        count(.skippedMissing)
    }

    public var ambiguousCount: Int {
        count(.skippedAmbiguous)
    }

    public var displayUnavailableCount: Int {
        count(.skippedDisplayUnavailable)
    }

    public var failedCount: Int {
        count(.failed)
    }

    public var resultState: ApplyJournalResultState {
        let satisfiedCount = restoredCount + unchangedCount
        if satisfiedCount > 0,
           skippedCount > 0 || failedCount > 0 {
            return .partial
        }
        if restoredCount > 0 {
            return .succeeded
        }
        if failedCount > 0 || skippedCount > 0 {
            return .failed
        }
        return .noChange
    }

    public var title: String {
        if resultState == .succeeded {
            return "Previous layout restored"
        }
        if resultState == .partial {
            return "Previous layout partially restored"
        }
        if resultState == .noChange {
            return "Previous layout was already restored"
        }
        return "Previous layout couldn’t be restored"
    }

    public var summary: String {
        var parts: [String] = []
        appendCount(restoredCount, label: "restored", to: &parts)
        appendCount(unchangedCount, label: "already in place", to: &parts)
        appendCount(missingCount, label: "missing", to: &parts)
        appendCount(ambiguousCount, label: "ambiguous", to: &parts)
        appendCount(
            displayUnavailableCount,
            label: "display unavailable",
            to: &parts
        )
        appendCount(failedCount, label: "failed", to: &parts)
        if !didPersistCompletion {
            parts.append("history update failed")
        }
        return parts.isEmpty ? "No windows required recovery" : parts.joined(
            separator: " · "
        )
    }

    private func count(_ state: ApplyRecoveryOutcomeState) -> Int {
        outcomes.count { $0.state == state }
    }

    private func appendCount(
        _ count: Int,
        label: String,
        to parts: inout [String]
    ) {
        guard count > 0 else {
            return
        }
        parts.append("\(count) \(label)")
    }
}

private struct WindowIdentity: Hashable {
    let applicationBundleIdentifier: String?
    let processIdentifier: Int32

    func matches(_ candidate: ApplyRecoveryCandidate) -> Bool {
        guard candidate.processIdentifier == processIdentifier else {
            return false
        }
        guard let applicationBundleIdentifier else {
            return candidate.applicationBundleIdentifier == nil
        }
        return candidate.applicationBundleIdentifier
            == applicationBundleIdentifier
    }
}
