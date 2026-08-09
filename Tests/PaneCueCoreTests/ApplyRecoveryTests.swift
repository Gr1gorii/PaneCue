import Foundation
import Testing
@testable import PaneCueCore

@Suite("Interrupted Apply recovery")
struct ApplyRecoveryTests {
    @Test
    func journalReturnsOnlyTheNewestPendingTransaction() throws {
        let fixture = RecoveryJournalFixture()
        defer { fixture.remove() }
        let completedID = UUID()
        let olderPendingID = UUID()
        let newestPendingID = UUID()

        try fixture.store.begin(
            windows: [makeWindow(identifier: "completed")],
            id: completedID,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        try fixture.store.complete(
            id: completedID,
            resultState: .succeeded,
            windowResults: ["completed": .moved]
        )
        try fixture.store.begin(
            windows: [makeWindow(identifier: "older")],
            id: olderPendingID,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        try fixture.store.begin(
            windows: [makeWindow(identifier: "newest")],
            id: newestPendingID,
            timestamp: Date(timeIntervalSince1970: 3)
        )

        #expect(try fixture.store.pendingTransaction()?.id == newestPendingID)
    }

    @Test
    func completedJournalHasNoRecoveryOffer() throws {
        let fixture = RecoveryJournalFixture()
        defer { fixture.remove() }
        let window = makeWindow(identifier: "completed")
        let id = try fixture.store.begin(windows: [window])
        try fixture.store.complete(
            id: id,
            resultState: .succeeded,
            windowResults: [window.windowIdentifier: .moved]
        )

        #expect(try fixture.store.pendingTransaction() == nil)
    }

    @Test
    func laterCompletedApplySupersedesAnOlderPendingTransaction() throws {
        let fixture = RecoveryJournalFixture()
        defer { fixture.remove() }
        try fixture.store.begin(
            windows: [makeWindow(identifier: "interrupted")]
        )
        let completedWindow = makeWindow(identifier: "later")
        let completedID = try fixture.store.begin(
            windows: [completedWindow]
        )
        try fixture.store.complete(
            id: completedID,
            resultState: .succeeded,
            windowResults: [completedWindow.windowIdentifier: .moved]
        )

        #expect(try fixture.store.pendingTransaction() == nil)
    }

    @Test
    func exactWindowIdentifierWinsAndLeavesASafeFallback() {
        let transaction = makeTransaction(
            windows: [
                makeWindow(identifier: "exact"),
                makeWindow(identifier: "changed")
            ]
        )
        let plan = ApplyRecoveryPlanner.plan(
            transaction: transaction,
            candidates: [
                makeCandidate(identifier: "exact"),
                makeCandidate(identifier: "replacement")
            ],
            availableDisplaySignatures: ["display-main"]
        )

        #expect(
            plan.windows.map(\.state) == [
                .matched(candidateWindowIdentifier: "exact"),
                .matched(candidateWindowIdentifier: "replacement")
            ]
        )
        #expect(plan.restorableWindowCount == 2)
    }

    @Test
    func oneRecordAndOneIdentityCandidateIsUnambiguous() {
        let transaction = makeTransaction(
            windows: [makeWindow(identifier: "previous")]
        )
        let plan = ApplyRecoveryPlanner.plan(
            transaction: transaction,
            candidates: [makeCandidate(identifier: "current")],
            availableDisplaySignatures: ["display-main"]
        )

        #expect(
            plan.windows.first?.state
                == .matched(candidateWindowIdentifier: "current")
        )
    }

    @Test
    func severalCandidatesAreAmbiguousWithoutAnExactIdentifier() {
        let transaction = makeTransaction(
            windows: [makeWindow(identifier: "previous")]
        )
        let plan = ApplyRecoveryPlanner.plan(
            transaction: transaction,
            candidates: [
                makeCandidate(identifier: "first"),
                makeCandidate(identifier: "second")
            ],
            availableDisplaySignatures: ["display-main"]
        )

        #expect(plan.windows.first?.state == .ambiguous)
        #expect(plan.restorableWindowCount == 0)
    }

    @Test
    func severalJournalWindowsNeverGuessOneRemainingCandidate() {
        let transaction = makeTransaction(
            windows: [
                makeWindow(identifier: "previous-a"),
                makeWindow(identifier: "previous-b")
            ]
        )
        let plan = ApplyRecoveryPlanner.plan(
            transaction: transaction,
            candidates: [makeCandidate(identifier: "current")],
            availableDisplaySignatures: ["display-main"]
        )

        #expect(plan.windows.map(\.state) == [.ambiguous, .ambiguous])
    }

    @Test
    func missingIdentityAndDisplayAreReportedSeparately() {
        let transaction = makeTransaction(
            windows: [
                makeWindow(identifier: "missing"),
                makeWindow(
                    identifier: "other-display",
                    displaySignature: "display-external"
                )
            ]
        )
        let plan = ApplyRecoveryPlanner.plan(
            transaction: transaction,
            candidates: [
                makeCandidate(
                    identifier: "wrong-process",
                    processIdentifier: 999
                )
            ],
            availableDisplaySignatures: ["display-main"]
        )

        #expect(
            plan.windows.map(\.state) == [
                .missing,
                .displayUnavailable
            ]
        )
    }

    @Test
    func partialResultIsTruthfulAndPrivacySafe() {
        let result = ApplyRecoveryResult(
            transactionID: UUID(),
            outcomes: [
                ApplyRecoveryWindowOutcome(
                    journalWindowIdentifier: "one",
                    state: .restored
                ),
                ApplyRecoveryWindowOutcome(
                    journalWindowIdentifier: "two",
                    state: .skippedAmbiguous
                ),
                ApplyRecoveryWindowOutcome(
                    journalWindowIdentifier: "three",
                    state: .failed
                )
            ],
            didPersistCompletion: true
        )

        #expect(result.resultState == .partial)
        #expect(result.title == "Previous layout partially restored")
        #expect(result.summary == "1 restored · 1 ambiguous · 1 failed")
    }

    @Test
    func alreadyRestoredAndMissingWindowsProduceAPartialResult() {
        let result = ApplyRecoveryResult(
            transactionID: UUID(),
            outcomes: [
                ApplyRecoveryWindowOutcome(
                    journalWindowIdentifier: "satisfied",
                    state: .unchanged
                ),
                ApplyRecoveryWindowOutcome(
                    journalWindowIdentifier: "missing",
                    state: .skippedMissing
                )
            ],
            didPersistCompletion: true
        )

        #expect(result.resultState == .partial)
        #expect(result.summary == "1 already in place · 1 missing")
    }

    private func makeTransaction(
        windows: [ApplyJournalWindowRecord]
    ) -> ApplyJournalTransaction {
        ApplyJournalTransaction(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 10),
            windows: windows
        )
    }

    private func makeWindow(
        identifier: String,
        processIdentifier: Int32 = 321,
        displaySignature: String = "display-main"
    ) -> ApplyJournalWindowRecord {
        ApplyJournalWindowRecord(
            applicationBundleIdentifier: "com.example.recovery",
            processIdentifier: processIdentifier,
            windowIdentifier: identifier,
            originalFrame: ApplyJournalFrame(
                x: 40,
                y: 60,
                width: 720,
                height: 540
            ),
            originalDisplaySignature: displaySignature,
            wasVisible: true,
            wasMinimized: false
        )
    }

    private func makeCandidate(
        identifier: String,
        processIdentifier: Int32 = 321
    ) -> ApplyRecoveryCandidate {
        ApplyRecoveryCandidate(
            windowIdentifier: identifier,
            applicationBundleIdentifier: "com.example.recovery",
            processIdentifier: processIdentifier
        )
    }
}

private struct RecoveryJournalFixture {
    let rootURL: URL
    let store: ApplyJournalStore

    init() {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = ApplyJournalStore(
            fileURL: rootURL.appendingPathComponent("journal.json")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
