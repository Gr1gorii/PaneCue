import Foundation

public enum CueArchiveError: LocalizedError, Equatable {
    case emptyArchive
    case unsupportedVersion(Int)
    case tooManyCues
    case invalidCue(String)

    public var errorDescription: String? {
        switch self {
        case .emptyArchive:
            return "The selected file does not contain any Cues."
        case let .unsupportedVersion(version):
            return "This Cue file uses unsupported format version \(version)."
        case .tooManyCues:
            return "A Cue file can contain at most 100 Cues."
        case let .invalidCue(reason):
            return "The Cue file is invalid: \(reason)"
        }
    }
}

public struct CueArchive: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var format: String
    public var schemaVersion: Int
    public var exportedAt: Date
    public var cues: [CustomScenario]

    public init(
        cues: [CustomScenario],
        exportedAt: Date = Date()
    ) {
        format = "PaneCue Cue"
        schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.cues = cues
    }

    public func encodedData() throws -> Data {
        try Self.validate(self)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> CueArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(CueArchive.self, from: data)
        try validate(archive)
        return archive
    }

    private static func validate(_ archive: CueArchive) throws {
        guard archive.format == "PaneCue Cue" else {
            throw CueArchiveError.invalidCue("unknown file type")
        }
        guard archive.schemaVersion == currentSchemaVersion else {
            throw CueArchiveError.unsupportedVersion(
                archive.schemaVersion
            )
        }
        guard !archive.cues.isEmpty else {
            throw CueArchiveError.emptyArchive
        }
        guard archive.cues.count <= 100 else {
            throw CueArchiveError.tooManyCues
        }

        var names: Set<String> = []
        for cue in archive.cues {
            let name = cue.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !name.isEmpty else {
                throw CueArchiveError.invalidCue("a Cue has no name")
            }
            guard (2...8).contains(cue.windows.count) else {
                throw CueArchiveError.invalidCue(
                    "“\(name)” must contain between 2 and 8 windows"
                )
            }
            guard names.insert(name.lowercased()).inserted else {
                throw CueArchiveError.invalidCue(
                    "duplicate Cue name “\(name)”"
                )
            }

            for window in cue.windows {
                if window.target.kind == .application {
                    let identifier = window.target.application?
                        .bundleIdentifier.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ) ?? ""
                    guard !identifier.isEmpty else {
                        throw CueArchiveError.invalidCue(
                            "“\(name)” contains an application without an identifier"
                        )
                    }
                }
                guard Self.isValidURL(window.urlString) else {
                    throw CueArchiveError.invalidCue(
                        "“\(name)” contains an invalid URL"
                    )
                }
            }
        }
    }

    private static func isValidURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return true
        }
        let candidate = trimmed.contains("://")
            ? trimmed
            : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else {
            return false
        }
        return true
    }
}
