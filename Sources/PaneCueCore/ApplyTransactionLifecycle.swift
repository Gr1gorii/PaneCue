import Foundation

public struct ApplyTransactionCompletion<Value> {
    public let value: Value
    public let resultState: ApplyJournalResultState
    public let windowResults: [String: ApplyJournalWindowResultState]

    public init(
        value: Value,
        resultState: ApplyJournalResultState,
        windowResults: [String: ApplyJournalWindowResultState]
    ) {
        self.value = value
        self.resultState = resultState
        self.windowResults = windowResults
    }
}

public struct ApplyTransactionExecution<Value> {
    public let value: Value
    public let didPersistCompletion: Bool

    public init(value: Value, didPersistCompletion: Bool) {
        self.value = value
        self.didPersistCompletion = didPersistCompletion
    }
}

public struct ApplyTransactionLifecycle {
    private let journal: ApplyJournalStore

    public init(journal: ApplyJournalStore) {
        self.journal = journal
    }

    public func execute<Value>(
        windows: [ApplyJournalWindowRecord],
        operation: () throws -> ApplyTransactionCompletion<Value>
    ) throws -> ApplyTransactionExecution<Value> {
        let transactionID = try journal.begin(windows: windows)

        let completion: ApplyTransactionCompletion<Value>
        do {
            completion = try operation()
        } catch {
            let failedResults = windows.reduce(
                into: [String: ApplyJournalWindowResultState]()
            ) {
                results, window in
                results[window.windowIdentifier] = .failed
            }
            _ = try? journal.complete(
                id: transactionID,
                resultState: .failed,
                windowResults: failedResults
            )
            throw error
        }

        let didPersistCompletion: Bool
        do {
            didPersistCompletion = try journal.complete(
                id: transactionID,
                resultState: completion.resultState,
                windowResults: completion.windowResults
            )
        } catch {
            didPersistCompletion = false
        }
        return ApplyTransactionExecution(
            value: completion.value,
            didPersistCompletion: didPersistCompletion
        )
    }
}
