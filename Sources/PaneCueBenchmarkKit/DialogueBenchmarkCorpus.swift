import Foundation
import PaneCueCore

public enum DialogueBenchmarkLocale: String, Codable, Sendable {
    case russian = "ru"
    case english = "en"
}

public enum DialogueBenchmarkCategory: String, Codable, Sendable {
    case command
    case followUp = "follow_up"
    case noAction = "no_action"
    case ambiguous
}

public enum DialogueBenchmarkOperation: String, Codable, Sendable {
    case createPlan = "create_plan"
    case directAction = "direct_action"
    case addWindow = "add_window"
    case removeWindow = "remove_window"
    case resizeWindow = "resize_window"
    case moveWindow = "move_window"
    case swapWindows = "swap_windows"
    case undo
    case save
    case noAction = "no_action"
    case needsSelection = "needs_selection"
}

public struct DialogueBenchmarkAuthor: Codable, Hashable, Sendable {
    public let id: String
    public let humanAuthored: Bool
    public let consentToEvaluation: Bool

    public init(
        id: String,
        humanAuthored: Bool,
        consentToEvaluation: Bool
    ) {
        self.id = id
        self.humanAuthored = humanAuthored
        self.consentToEvaluation = consentToEvaluation
    }
}

public struct DialogueBenchmarkManifest: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let corpusID: String
    public let frozen: Bool
    public let trainingUseProhibited: Bool
    public let authors: [DialogueBenchmarkAuthor]

    public init(
        schemaVersion: Int = 1,
        corpusID: String,
        frozen: Bool,
        trainingUseProhibited: Bool,
        authors: [DialogueBenchmarkAuthor]
    ) {
        self.schemaVersion = schemaVersion
        self.corpusID = corpusID
        self.frozen = frozen
        self.trainingUseProhibited = trainingUseProhibited
        self.authors = authors
    }
}

public struct DialogueBenchmarkExpectation: Codable, Hashable, Sendable {
    public let operation: DialogueBenchmarkOperation
    public let action: String?
    public let referent: String?
    public let targets: [String]?
    public let selectionID: String?

    public init(
        operation: DialogueBenchmarkOperation,
        action: String? = nil,
        referent: String? = nil,
        targets: [String]? = nil,
        selectionID: String? = nil
    ) {
        self.operation = operation
        self.action = action
        self.referent = referent
        self.targets = targets
        self.selectionID = selectionID
    }
}

public struct DialogueBenchmarkInventoryItem: Codable, Hashable, Sendable {
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
        bundleIdentifier: String? = nil,
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

    var workspaceItem: WorkspaceWindowInventoryItem {
        WorkspaceWindowInventoryItem(
            id: id,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            role: role,
            display: display,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            canSetFrame: canSetFrame
        )
    }
}

public struct DialogueBenchmarkRecord: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let authorID: String
    public let locale: DialogueBenchmarkLocale
    public let category: DialogueBenchmarkCategory
    public let utterance: String
    public let contextUtterance: String?
    public let expected: DialogueBenchmarkExpectation
    public let inventory: [DialogueBenchmarkInventoryItem]?

    public init(
        schemaVersion: Int = 1,
        id: String,
        authorID: String,
        locale: DialogueBenchmarkLocale,
        category: DialogueBenchmarkCategory,
        utterance: String,
        contextUtterance: String? = nil,
        expected: DialogueBenchmarkExpectation,
        inventory: [DialogueBenchmarkInventoryItem]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.authorID = authorID
        self.locale = locale
        self.category = category
        self.utterance = utterance
        self.contextUtterance = contextUtterance
        self.expected = expected
        self.inventory = inventory
    }
}

public struct DialogueBenchmarkCorpus: Hashable, Sendable {
    public let manifest: DialogueBenchmarkManifest
    public let records: [DialogueBenchmarkRecord]

    public init(
        manifest: DialogueBenchmarkManifest,
        records: [DialogueBenchmarkRecord]
    ) {
        self.manifest = manifest
        self.records = records
    }
}

public struct DialogueBenchmarkProfile: Codable, Equatable, Sendable {
    public let authorCount: Int
    public let russianCommandCount: Int
    public let englishCommandCount: Int
    public let followUpCount: Int
    public let referentCaseCount: Int
    public let noActionCount: Int
    public let ambiguousCount: Int
    public let safetyCount: Int
    public let totalCount: Int
}

public enum DialogueBenchmarkCorpusError: LocalizedError, Equatable,
    Sendable {
    case manifestUnavailable
    case recordsUnavailable
    case malformedManifest
    case malformedRecord(line: Int)
    case invalidCorpus(reason: String)

    public var errorDescription: String? {
        switch self {
        case .manifestUnavailable:
            return "The external benchmark manifest is unavailable."
        case .recordsUnavailable:
            return "The external benchmark records are unavailable."
        case .malformedManifest:
            return "The external benchmark manifest is malformed."
        case let .malformedRecord(line):
            return "Benchmark record line \(line) is malformed."
        case let .invalidCorpus(reason):
            return "Benchmark corpus validation failed: \(reason)."
        }
    }
}

public enum DialogueBenchmarkCorpusLoader {
    public static func load(
        from directory: URL
    ) throws -> DialogueBenchmarkCorpus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let recordsURL = directory.appendingPathComponent("records.jsonl")

        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw DialogueBenchmarkCorpusError.manifestUnavailable
        }
        guard hasOnlyAllowedManifestKeys(manifestData),
              let manifest = try? decoder.decode(
            DialogueBenchmarkManifest.self,
            from: manifestData
        ) else {
            throw DialogueBenchmarkCorpusError.malformedManifest
        }
        guard let recordsText = try? String(
            contentsOf: recordsURL,
            encoding: .utf8
        ) else {
            throw DialogueBenchmarkCorpusError.recordsUnavailable
        }

        var records: [DialogueBenchmarkRecord] = []
        for (offset, line) in recordsText.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            let trimmed = line.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty else {
                continue
            }
            guard let data = trimmed.data(using: .utf8),
                  hasOnlyAllowedRecordKeys(data),
                  let record = try? decoder.decode(
                      DialogueBenchmarkRecord.self,
                      from: data
                  ) else {
                throw DialogueBenchmarkCorpusError.malformedRecord(
                    line: offset + 1
                )
            }
            records.append(record)
        }
        return DialogueBenchmarkCorpus(
            manifest: manifest,
            records: records
        )
    }

    static func hasOnlyAllowedManifestKeys(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any],
              keys(root).isSubset(of: [
                  "schema_version",
                  "corpus_id",
                  "frozen",
                  "training_use_prohibited",
                  "authors"
              ]),
              let authors = root["authors"] as? [[String: Any]] else {
            return false
        }
        let allowedAuthorKeys: Set<String> = [
            "id",
            "human_authored",
            "consent_to_evaluation"
        ]
        return authors.allSatisfy {
            keys($0).isSubset(of: allowedAuthorKeys)
        }
    }

    static func hasOnlyAllowedRecordKeys(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any],
              keys(root).isSubset(of: [
                  "schema_version",
                  "id",
                  "author_id",
                  "locale",
                  "category",
                  "utterance",
                  "context_utterance",
                  "expected",
                  "inventory"
              ]),
              let expected = root["expected"] as? [String: Any],
              keys(expected).isSubset(of: [
                  "operation",
                  "action",
                  "referent",
                  "targets",
                  "selection_id"
              ]) else {
            return false
        }
        guard let inventory = root["inventory"] else {
            return true
        }
        guard let items = inventory as? [[String: Any]] else {
            return false
        }
        let allowedInventoryKeys: Set<String> = [
            "id",
            "bundle_identifier",
            "application_name",
            "role",
            "display",
            "is_minimized",
            "is_full_screen",
            "can_set_frame"
        ]
        return items.allSatisfy {
            keys($0).isSubset(of: allowedInventoryKeys)
        }
    }

    private static func keys(
        _ object: [String: Any]
    ) -> Set<String> {
        Set(object.keys)
    }
}

public enum DialogueBenchmarkCorpusValidator {
    public static let minimumRussianCommands = 200
    public static let minimumEnglishCommands = 200
    public static let minimumFollowUps = 100
    public static let minimumReferentCases = 100
    public static let minimumSafetyCases = 200
    public static let minimumAuthors = 5

    public static func validate(
        _ corpus: DialogueBenchmarkCorpus,
        trainingTexts: [String] = []
    ) throws -> DialogueBenchmarkProfile {
        guard corpus.manifest.schemaVersion == 1 else {
            throw invalid("unsupported manifest schema")
        }
        guard safeIdentifier(corpus.manifest.corpusID) else {
            throw invalid("corpus identifier is not opaque")
        }
        guard corpus.manifest.frozen else {
            throw invalid("corpus is not frozen")
        }
        guard corpus.manifest.trainingUseProhibited else {
            throw invalid("training use is not prohibited")
        }

        let authors = corpus.manifest.authors
        let authorIDs = Set(authors.map(\.id))
        guard authorIDs.count == authors.count,
              authors.allSatisfy({
                  safeIdentifier($0.id)
                      && $0.humanAuthored
                      && $0.consentToEvaluation
              }) else {
            throw invalid("author declarations are invalid")
        }

        var recordIDs = Set<String>()
        var normalizedUtterances = Set<String>()
        var contributingAuthors = Set<String>()
        let normalizedTraining = Set(trainingTexts.map(normalize))
        var russianCommands = 0
        var englishCommands = 0
        var followUps = 0
        var referentCases = 0
        var noActionCases = 0
        var ambiguousCases = 0
        var safetyCases = 0

        for record in corpus.records {
            guard record.schemaVersion == 1 else {
                throw invalid("record \(record.id) has unsupported schema")
            }
            guard safeIdentifier(record.id),
                  recordIDs.insert(record.id).inserted else {
                throw invalid("record identifier is invalid or duplicated")
            }
            guard authorIDs.contains(record.authorID) else {
                throw invalid("record \(record.id) has an unknown author")
            }
            contributingAuthors.insert(record.authorID)

            let normalizedUtterance = normalize(record.utterance)
            guard !normalizedUtterance.isEmpty,
                  record.utterance.count <= 1_000 else {
                throw invalid("record \(record.id) has invalid input")
            }
            guard normalizedUtterances.insert(
                normalizedUtterance
            ).inserted else {
                throw invalid("record \(record.id) duplicates another input")
            }
            guard !normalizedTraining.contains(normalizedUtterance) else {
                throw invalid("record \(record.id) overlaps training data")
            }
            if record.locale == .russian,
               !containsCyrillic(record.utterance) {
                throw invalid("record \(record.id) has invalid locale")
            }
            guard validExpectedValues(record.expected) else {
                throw invalid("record \(record.id) has invalid expected values")
            }
            if let inventory = record.inventory {
                let candidateIDs = Set(inventory.map(\.id))
                guard candidateIDs.count == inventory.count,
                      inventory.allSatisfy(validInventoryItem) else {
                    throw invalid("record \(record.id) has invalid inventory")
                }
            }

            switch record.category {
            case .command:
                guard record.contextUtterance == nil,
                      record.expected.operation == .createPlan
                        || record.expected.operation == .directAction,
                      !(record.expected.targets ?? []).isEmpty
                        || record.expected.operation == .directAction else {
                    throw invalid("record \(record.id) has invalid command expectations")
                }
                if record.locale == .russian {
                    russianCommands += 1
                } else {
                    englishCommands += 1
                }
            case .followUp:
                guard let context = record.contextUtterance,
                      !normalize(context).isEmpty,
                      context.count <= 1_000,
                      !normalizedTraining.contains(normalize(context)) else {
                    throw invalid("record \(record.id) has invalid follow-up context")
                }
                followUps += 1
                if record.expected.referent != nil {
                    referentCases += 1
                }
            case .noAction:
                guard record.contextUtterance == nil,
                      record.expected.operation == .noAction else {
                    throw invalid("record \(record.id) has invalid no-action expectations")
                }
                noActionCases += 1
                safetyCases += 1
            case .ambiguous:
                guard record.contextUtterance == nil,
                      record.expected.operation == .needsSelection,
                      let selectionID = record.expected.selectionID,
                      let inventory = record.inventory,
                      inventory.count >= 2,
                      inventory.contains(where: {
                          $0.id == selectionID
                      }) else {
                    throw invalid("record \(record.id) has invalid ambiguity expectations")
                }
                ambiguousCases += 1
                safetyCases += 1
            }
        }

        guard contributingAuthors.count >= minimumAuthors else {
            throw invalid("fewer than five contributing authors")
        }
        guard russianCommands >= minimumRussianCommands else {
            throw invalid("fewer than 200 Russian commands")
        }
        guard englishCommands >= minimumEnglishCommands else {
            throw invalid("fewer than 200 English commands")
        }
        guard followUps >= minimumFollowUps else {
            throw invalid("fewer than 100 contextual follow-ups")
        }
        guard referentCases >= minimumReferentCases else {
            throw invalid("fewer than 100 referent cases")
        }
        guard safetyCases >= minimumSafetyCases else {
            throw invalid("fewer than 200 safety cases")
        }
        guard noActionCases > 0, ambiguousCases > 0 else {
            throw invalid("safety corpus must cover no-action and ambiguity")
        }

        return DialogueBenchmarkProfile(
            authorCount: contributingAuthors.count,
            russianCommandCount: russianCommands,
            englishCommandCount: englishCommands,
            followUpCount: followUps,
            referentCaseCount: referentCases,
            noActionCount: noActionCases,
            ambiguousCount: ambiguousCases,
            safetyCount: safetyCases,
            totalCount: corpus.records.count
        )
    }

    public static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        var result = ""
        var needsSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if needsSpace, !result.isEmpty {
                    result.append(" ")
                }
                result.unicodeScalars.append(scalar)
                needsSpace = false
            } else {
                needsSpace = true
            }
        }
        return result
    }

    private static func safeIdentifier(_ value: String) -> Bool {
        guard (1...64).contains(value.count) else {
            return false
        }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
        )
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func validExpectedValues(
        _ expected: DialogueBenchmarkExpectation
    ) -> Bool {
        if let action = expected.action,
           VoiceCommandAction(rawValue: action) == nil {
            return false
        }
        if expected.operation == .directAction,
           expected.action == nil {
            return false
        }
        if let referent = expected.referent,
           !validTargetKey(referent) {
            return false
        }
        if let selectionID = expected.selectionID,
           !safeIdentifier(selectionID) {
            return false
        }
        return (expected.targets ?? []).allSatisfy(validTargetKey)
    }

    private static func validTargetKey(_ value: String) -> Bool {
        if value.hasPrefix("application:") {
            return validBundleIdentifier(
                String(value.dropFirst("application:".count))
            )
        }
        if value.hasPrefix("role:") {
            return ApplicationRole(
                rawValue: String(value.dropFirst("role:".count))
            ) != nil
        }
        return false
    }

    private static func validInventoryItem(
        _ item: DialogueBenchmarkInventoryItem
    ) -> Bool {
        let name = item.applicationName
        guard safeIdentifier(item.id),
              (1...100).contains(name.count),
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains("://"),
              !name.contains("\n") else {
            return false
        }
        guard let bundleIdentifier = item.bundleIdentifier else {
            return true
        }
        return validBundleIdentifier(bundleIdentifier)
    }

    private static func validBundleIdentifier(_ value: String) -> Bool {
        guard (3...255).contains(value.count), value.contains(".") else {
            return false
        }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
        )
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func containsCyrillic(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            (0x0400...0x04FF).contains(Int($0.value))
        }
    }

    private static func invalid(
        _ reason: String
    ) -> DialogueBenchmarkCorpusError {
        .invalidCorpus(reason: reason)
    }
}
