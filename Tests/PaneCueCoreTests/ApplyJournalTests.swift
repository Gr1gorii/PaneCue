import Foundation
import Testing
@testable import PaneCueCore

@Suite("Apply journal")
struct ApplyJournalTests {
    @Test
    func usesTheFrozenApplicationSupportLocation() {
        let path = ApplyJournalStore().fileURL.path

        #expect(
            path.hasSuffix(
                "/Library/Application Support/PaneCue/apply-journal-v1.json"
            )
        )
    }

    @Test
    func keepsFiveCompletedTransactionsWithOnlyFrozenFields() throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }

        var expectedIDs: [UUID] = []
        for index in 0..<6 {
            let id = try #require(
                UUID(
                    uuidString:
                        "00000000-0000-0000-0000-00000000000\(index)"
                )
            )
            expectedIDs.append(id)
            try fixture.store.begin(
                windows: [makeWindow(index: index)],
                id: id,
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
            try fixture.store.complete(
                id: id,
                resultState: .succeeded,
                windowResults: ["window-\(index)": .moved]
            )
        }

        let transactions = try fixture.store.transactions()
        #expect(transactions.count == 5)
        #expect(transactions.map(\.id) == Array(expectedIDs.suffix(5)))
        #expect(transactions.allSatisfy { $0.isCompleted })
        #expect(transactions.allSatisfy { $0.resultState == .succeeded })
        #expect(
            transactions.allSatisfy {
                $0.windows.allSatisfy { $0.resultState == .moved }
            }
        )

        let data = try Data(contentsOf: fixture.fileURL)
        let root = try #require(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        #expect(Set(root.keys) == ["schemaVersion", "transactions"])
        let encodedTransactions = try #require(
            root["transactions"] as? [[String: Any]]
        )
        #expect(
            encodedTransactions.allSatisfy {
                Set($0.keys) == [
                    "id",
                    "timestamp",
                    "windows",
                    "resultState",
                    "isCompleted"
                ]
            }
        )
        let encodedWindows = encodedTransactions.flatMap {
            $0["windows"] as? [[String: Any]] ?? []
        }
        #expect(
            encodedWindows.allSatisfy {
                Set($0.keys) == [
                    "applicationBundleIdentifier",
                    "processIdentifier",
                    "windowIdentifier",
                    "originalFrame",
                    "originalDisplaySignature",
                    "wasVisible",
                    "wasMinimized",
                    "resultState"
                ]
            }
        )
    }

    @Test
    func writesUserOnlyFileAndDirectoryPermissions() throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }

        try fixture.store.begin(windows: [makeWindow(index: 1)])

        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.path
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.deletingLastPathComponent().path
        )
        let fileMode = try #require(
            fileAttributes[.posixPermissions] as? NSNumber
        ).intValue
        let directoryMode = try #require(
            directoryAttributes[.posixPermissions] as? NSNumber
        ).intValue

        #expect(fileMode & 0o777 == 0o600)
        #expect(directoryMode & 0o777 == 0o700)
    }

    @Test
    func removesCorruptDataAndStartsFresh() throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0, 1, 2, 3]).write(to: fixture.fileURL)

        #expect(try fixture.store.transactions().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))

        try fixture.store.begin(windows: [makeWindow(index: 2)])
        #expect(try fixture.store.transactions().count == 1)
    }

    @Test
    func preservesUnsupportedFutureSchema() throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 99,
                "transactions": []
            ]
        )
        try data.write(to: fixture.fileURL)

        #expect(throws: ApplyJournalError.unsupportedSchema(99)) {
            try fixture.store.transactions()
        }
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test
    func rejectsAnOversizedRecordWithoutWritingIt() throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let oversized = ApplyJournalWindowRecord(
            applicationBundleIdentifier: String(
                repeating: "x",
                count: ApplyJournalStore.maximumFileByteCount
            ),
            processIdentifier: 42,
            windowIdentifier: "window-oversized",
            originalFrame: ApplyJournalFrame(
                x: 0,
                y: 0,
                width: 100,
                height: 100
            ),
            originalDisplaySignature: "display-1",
            wasVisible: true,
            wasMinimized: false
        )

        #expect(throws: ApplyJournalError.sizeLimitExceeded) {
            try fixture.store.begin(windows: [oversized])
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test
    func removesAnOversizedOnDiskJournalBeforeReading() throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(
            repeating: 0,
            count: ApplyJournalStore.maximumFileByteCount + 1
        ).write(to: fixture.fileURL)

        #expect(try fixture.store.transactions().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test
    func clearRemovesOnlyTheJournalFile() throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        try fixture.store.begin(windows: [makeWindow(index: 3)])
        let siblingURL = fixture.fileURL.deletingLastPathComponent()
            .appendingPathComponent("keep.txt")
        try Data([7]).write(to: siblingURL)

        #expect(try fixture.store.clear() == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    private func makeWindow(index: Int) -> ApplyJournalWindowRecord {
        ApplyJournalWindowRecord(
            applicationBundleIdentifier: "com.example.app\(index)",
            processIdentifier: Int32(100 + index),
            windowIdentifier: "window-\(index)",
            originalFrame: ApplyJournalFrame(
                x: Double(index * 10),
                y: 20,
                width: 600,
                height: 480
            ),
            originalDisplaySignature: "display-1-1440x900-200",
            wasVisible: true,
            wasMinimized: false
        )
    }
}

private struct JournalFixture {
    let rootURL: URL
    let fileURL: URL
    let store: ApplyJournalStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileURL = rootURL
            .appendingPathComponent("PaneCue", isDirectory: true)
            .appendingPathComponent("apply-journal-v1.json")
        store = ApplyJournalStore(fileURL: fileURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
