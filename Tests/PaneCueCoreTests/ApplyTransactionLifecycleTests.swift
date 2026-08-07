import CoreGraphics
import Foundation
import Testing
@testable import PaneCueCore

@Suite("Apply transaction lifecycle")
struct ApplyTransactionLifecycleTests {
    @Test
    func persistsPendingBeforeMutationAndCompletedAfterVerification()
        throws {
        let fixture = LifecycleFixture()
        defer { fixture.remove() }
        let record = makeRecord(index: 1)
        var observedPending = false

        let execution = try fixture.lifecycle.execute(
            windows: [record]
        ) {
            let pending = try #require(
                fixture.store.transactions().last
            )
            #expect(!pending.isCompleted)
            #expect(pending.resultState == .pending)
            #expect(pending.windows.first?.resultState == .pending)
            observedPending = true

            return ApplyTransactionCompletion(
                value: 7,
                resultState: .succeeded,
                windowResults: [record.windowIdentifier: .moved]
            )
        }

        #expect(observedPending)
        #expect(execution.value == 7)
        #expect(execution.didPersistCompletion)
        let completed = try #require(
            fixture.store.transactions().last
        )
        #expect(completed.isCompleted)
        #expect(completed.resultState == .succeeded)
        #expect(completed.windows.first?.resultState == .moved)
    }

    @Test
    func persistsPartialResultForEveryPreparedWindow() throws {
        let fixture = LifecycleFixture()
        defer { fixture.remove() }
        let first = makeRecord(index: 1)
        let second = makeRecord(index: 2)

        _ = try fixture.lifecycle.execute(windows: [first, second]) {
            ApplyTransactionCompletion(
                value: true,
                resultState: .partial,
                windowResults: [
                    first.windowIdentifier: .moved,
                    second.windowIdentifier: .failed
                ]
            )
        }

        let completed = try #require(
            fixture.store.transactions().last
        )
        #expect(completed.isCompleted)
        #expect(completed.resultState == .partial)
        #expect(completed.windows.map(\.resultState) == [.moved, .failed])
    }

    @Test
    func controlledFailureFinalizesThePendingTransaction() throws {
        let fixture = LifecycleFixture()
        defer { fixture.remove() }
        let record = makeRecord(index: 3)

        #expect(throws: LifecycleProbeError.self) {
            try fixture.lifecycle.execute(windows: [record]) {
                throw LifecycleProbeError.operationFailed
            } as ApplyTransactionExecution<Bool>
        }

        let completed = try #require(
            fixture.store.transactions().last
        )
        #expect(completed.isCompleted)
        #expect(completed.resultState == .failed)
        #expect(completed.windows.first?.resultState == .failed)
    }

    @Test
    func missingPendingRecordDoesNotClaimCompletionWasPersisted() throws {
        let fixture = LifecycleFixture()
        defer { fixture.remove() }
        let record = makeRecord(index: 4)

        let execution = try fixture.lifecycle.execute(
            windows: [record]
        ) {
            #expect(try fixture.store.transactions().count == 1)
            try FileManager.default.removeItem(at: fixture.fileURL)
            return ApplyTransactionCompletion(
                value: true,
                resultState: .succeeded,
                windowResults: [record.windowIdentifier: .moved]
            )
        }

        #expect(execution.value)
        #expect(!execution.didPersistCompletion)
    }

    @Test
    func pendingWriteFailurePreventsTheOperationFromStarting() throws {
        let fixture = LifecycleFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let unsupported = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 99,
                "transactions": []
            ]
        )
        try unsupported.write(to: fixture.fileURL)
        var operationStarted = false

        #expect(throws: ApplyJournalError.unsupportedSchema(99)) {
            try fixture.lifecycle.execute(
                windows: [makeRecord(index: 5)]
            ) {
                operationStarted = true
                return ApplyTransactionCompletion(
                    value: true,
                    resultState: .succeeded,
                    windowResults: [:]
                )
            }
        }
        #expect(!operationStarted)
    }

    @Test
    func displaySignatureUsesOnlyDeterministicGeometry() {
        let signature = ScreenGeometry.displaySignature(
            index: 1,
            frame: CGRect(x: -1_440, y: 0, width: 1_440, height: 900),
            scale: 2
        )

        #expect(signature == "display-1--1440,0-1440x900-200")
    }

    private func makeRecord(index: Int) -> ApplyJournalWindowRecord {
        ApplyJournalWindowRecord(
            applicationBundleIdentifier: "com.example.lifecycle\(index)",
            processIdentifier: Int32(200 + index),
            windowIdentifier: "window-\(index)",
            originalFrame: ApplyJournalFrame(
                x: Double(index * 10),
                y: 20,
                width: 600,
                height: 480
            ),
            originalDisplaySignature: "display-0-0,0-1440x900-200",
            wasVisible: true,
            wasMinimized: false
        )
    }
}

private enum LifecycleProbeError: Error {
    case operationFailed
}

private struct LifecycleFixture {
    let rootURL: URL
    let fileURL: URL
    let store: ApplyJournalStore
    let lifecycle: ApplyTransactionLifecycle

    init() {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileURL = rootURL
            .appendingPathComponent("PaneCue", isDirectory: true)
            .appendingPathComponent("apply-journal-v1.json")
        store = ApplyJournalStore(fileURL: fileURL)
        lifecycle = ApplyTransactionLifecycle(journal: store)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
