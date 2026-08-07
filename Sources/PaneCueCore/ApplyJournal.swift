import Foundation

public struct ApplyJournalFrame: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum ApplyJournalWindowResultState: String, Codable, Hashable,
    Sendable {
    case pending
    case moved
    case unchanged
    case skipped
    case failed
}

public struct ApplyJournalWindowRecord: Codable, Hashable, Sendable {
    public let applicationBundleIdentifier: String?
    public let processIdentifier: Int32
    public let windowIdentifier: String
    public let originalFrame: ApplyJournalFrame
    public let originalDisplaySignature: String
    public let wasVisible: Bool?
    public let wasMinimized: Bool?
    public var resultState: ApplyJournalWindowResultState

    public init(
        applicationBundleIdentifier: String?,
        processIdentifier: Int32,
        windowIdentifier: String,
        originalFrame: ApplyJournalFrame,
        originalDisplaySignature: String,
        wasVisible: Bool?,
        wasMinimized: Bool?,
        resultState: ApplyJournalWindowResultState = .pending
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.processIdentifier = processIdentifier
        self.windowIdentifier = windowIdentifier
        self.originalFrame = originalFrame
        self.originalDisplaySignature = originalDisplaySignature
        self.wasVisible = wasVisible
        self.wasMinimized = wasMinimized
        self.resultState = resultState
    }
}

public enum ApplyJournalResultState: String, Codable, Hashable, Sendable {
    case pending
    case succeeded
    case partial
    case failed
    case noChange
}

public struct ApplyJournalTransaction: Identifiable, Codable, Hashable,
    Sendable {
    public let id: UUID
    public let timestamp: Date
    public var windows: [ApplyJournalWindowRecord]
    public var resultState: ApplyJournalResultState
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        windows: [ApplyJournalWindowRecord],
        resultState: ApplyJournalResultState = .pending,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.windows = windows
        self.resultState = resultState
        self.isCompleted = isCompleted
    }
}

public struct ApplyJournalSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var transactions: [ApplyJournalTransaction]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        transactions: [ApplyJournalTransaction] = []
    ) {
        self.schemaVersion = schemaVersion
        self.transactions = transactions
    }
}

public enum ApplyJournalError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case sizeLimitExceeded

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return "Apply history uses unsupported schema version \(version)."
        case .sizeLimitExceeded:
            return "Apply history exceeded its local storage limit."
        }
    }
}

public final class ApplyJournalStore {
    public static let maximumTransactionCount = 5
    public static let maximumWindowCount = 8
    public static let maximumFileByteCount = 64 * 1_024

    public let fileURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(
            fileManager: fileManager
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    public func transactions() throws -> [ApplyJournalTransaction] {
        try loadSnapshot().transactions
    }

    @discardableResult
    public func begin(
        windows: [ApplyJournalWindowRecord],
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) throws -> UUID {
        var snapshot = try loadSnapshot()
        snapshot.transactions.append(
            ApplyJournalTransaction(
                id: id,
                timestamp: timestamp,
                windows: Array(windows.prefix(Self.maximumWindowCount))
            )
        )
        snapshot.transactions = Array(
            snapshot.transactions.suffix(Self.maximumTransactionCount)
        )
        try write(snapshot)
        return id
    }

    @discardableResult
    public func complete(
        id: UUID,
        resultState: ApplyJournalResultState,
        windowResults: [String: ApplyJournalWindowResultState]
    ) throws -> Bool {
        var snapshot = try loadSnapshot()
        guard let transactionIndex = snapshot.transactions.firstIndex(
            where: { $0.id == id }
        ) else {
            return false
        }

        snapshot.transactions[transactionIndex].resultState = resultState
        snapshot.transactions[transactionIndex].isCompleted = true
        for windowIndex in snapshot.transactions[transactionIndex]
            .windows.indices {
            let windowIdentifier = snapshot.transactions[transactionIndex]
                .windows[windowIndex].windowIdentifier
            if let result = windowResults[windowIdentifier] {
                snapshot.transactions[transactionIndex]
                    .windows[windowIndex].resultState = result
            }
        }
        try write(snapshot)
        return true
    }

    @discardableResult
    public func clear() throws -> Int {
        let count = (try? loadSnapshot().transactions.count) ?? 0
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return count
        }
        try fileManager.removeItem(at: fileURL)
        return count
    }

    private static func defaultFileURL(
        fileManager: FileManager
    ) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("PaneCue", isDirectory: true)
            .appendingPathComponent("apply-journal-v1.json")
    }

    private func loadSnapshot() throws -> ApplyJournalSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ApplyJournalSnapshot()
        }

        do {
            let attributes = try fileManager.attributesOfItem(
                atPath: fileURL.path
            )
            if let fileSize = attributes[.size] as? NSNumber,
               fileSize.intValue > Self.maximumFileByteCount {
                try removeCorruptJournal()
                return ApplyJournalSnapshot()
            }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= Self.maximumFileByteCount else {
                try removeCorruptJournal()
                return ApplyJournalSnapshot()
            }
            let snapshot = try decoder.decode(
                ApplyJournalSnapshot.self,
                from: data
            )
            guard snapshot.schemaVersion
                    == ApplyJournalSnapshot.currentSchemaVersion else {
                throw ApplyJournalError.unsupportedSchema(
                    snapshot.schemaVersion
                )
            }
            return ApplyJournalSnapshot(
                transactions: Array(
                    snapshot.transactions.suffix(
                        Self.maximumTransactionCount
                    )
                )
            )
        } catch let error as ApplyJournalError {
            throw error
        } catch {
            try removeCorruptJournal()
            return ApplyJournalSnapshot()
        }
    }

    private func write(_ snapshot: ApplyJournalSnapshot) throws {
        let normalized = ApplyJournalSnapshot(
            transactions: Array(
                snapshot.transactions.suffix(Self.maximumTransactionCount)
            ).map { transaction in
                ApplyJournalTransaction(
                    id: transaction.id,
                    timestamp: transaction.timestamp,
                    windows: Array(
                        transaction.windows.prefix(Self.maximumWindowCount)
                    ),
                    resultState: transaction.resultState,
                    isCompleted: transaction.isCompleted
                )
            }
        )
        let data = try encoder.encode(normalized)
        guard data.count <= Self.maximumFileByteCount else {
            throw ApplyJournalError.sizeLimitExceeded
        }

        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func removeCorruptJournal() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }
}
