import Foundation

/// The complete public URL surface for PaneCue v0.2.
///
/// Apply is deliberately not representable here. External callers may only
/// reveal PaneCue or create a Preview that still requires a visible, direct
/// action inside the app.
public enum PaneCueLinkRequest: Equatable, Sendable {
    case show
    case preview(command: String)
    case cue(id: UUID)
}

public enum PaneCueLinkRejection: Equatable, Sendable {
    case malformed
    case unsupported
    case oversized
    case repeated
    case rateLimited
}

public enum PaneCueLinkAdmission: Equatable, Sendable {
    case accepted(PaneCueLinkRequest)
    case rejected(PaneCueLinkRejection)
}

public enum PaneCueLinkParser {
    public static let scheme = "panecue"
    public static let maximumURLByteCount = 4_096
    public static let maximumCommandByteCount = 2_048

    public static func parse(_ url: URL) -> PaneCueLinkAdmission {
        parse(url.absoluteString)
    }

    public static func parse(_ rawValue: String) -> PaneCueLinkAdmission {
        guard !rawValue.isEmpty,
              rawValue.utf8.count <= maximumURLByteCount else {
            return .rejected(.oversized)
        }
        guard hasValidPercentEncoding(rawValue),
              let components = URLComponents(string: rawValue),
              components.scheme?.lowercased() == scheme,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              components.path.isEmpty,
              let route = components.host?.lowercased(),
              !route.isEmpty else {
            return .rejected(.malformed)
        }

        switch route {
        case "show":
            guard components.query == nil else {
                return .rejected(.malformed)
            }
            return .accepted(.show)

        case "preview":
            guard let items = components.queryItems,
                  items.count == 1,
                  items[0].name == "text",
                  let value = items[0].value else {
                return .rejected(.malformed)
            }
            let command = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !command.isEmpty,
                  !command.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }) else {
                return .rejected(.malformed)
            }
            guard command.utf8.count <= maximumCommandByteCount else {
                return .rejected(.oversized)
            }
            return .accepted(.preview(command: command))

        case "cue":
            guard let items = components.queryItems,
                  items.count == 1,
                  items[0].name == "id",
                  let value = items[0].value,
                  let id = UUID(uuidString: value) else {
                return .rejected(.malformed)
            }
            return .accepted(.cue(id: id))

        default:
            return .rejected(.unsupported)
        }
    }

    private static func hasValidPercentEncoding(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x25 {
                guard index + 2 < bytes.count,
                      isHexadecimal(bytes[index + 1]),
                      isHexadecimal(bytes[index + 2]) else {
                    return false
                }
                index += 3
            } else {
                index += 1
            }
        }
        return true
    }

    private static func isHexadecimal(_ value: UInt8) -> Bool {
        (0x30...0x39).contains(value)
            || (0x41...0x46).contains(value)
            || (0x61...0x66).contains(value)
    }
}

/// A small process-local admission gate. It never persists the incoming URL or
/// command. Only randomized `Hasher` fingerprints remain in memory for the
/// short duplicate-suppression interval.
public struct PaneCueLinkAdmissionGate: Sendable {
    public static let duplicateInterval: TimeInterval = 2
    public static let rateInterval: TimeInterval = 10
    public static let maximumRequestsPerRateInterval = 5

    private var acceptedAt: [TimeInterval] = []
    private var recentFingerprints: [Int: TimeInterval] = [:]

    public init() {}

    public mutating func admit(
        _ url: URL,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> PaneCueLinkAdmission {
        admit(url.absoluteString, at: time)
    }

    public mutating func admit(
        _ rawValue: String,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> PaneCueLinkAdmission {
        let parsed = PaneCueLinkParser.parse(rawValue)
        guard case let .accepted(request) = parsed else {
            return parsed
        }

        acceptedAt.removeAll {
            time - $0 >= Self.rateInterval || time < $0
        }
        recentFingerprints = recentFingerprints.filter {
            time - $0.value < Self.duplicateInterval && time >= $0.value
        }

        let fingerprint = Self.fingerprint(for: request)
        if recentFingerprints[fingerprint] != nil {
            return .rejected(.repeated)
        }
        guard acceptedAt.count < Self.maximumRequestsPerRateInterval else {
            return .rejected(.rateLimited)
        }

        acceptedAt.append(time)
        recentFingerprints[fingerprint] = time
        return .accepted(request)
    }

    private static func fingerprint(for request: PaneCueLinkRequest) -> Int {
        var hasher = Hasher()
        switch request {
        case .show:
            hasher.combine(0)
        case let .preview(command):
            hasher.combine(1)
            hasher.combine(command)
        case let .cue(id):
            hasher.combine(2)
            hasher.combine(id)
        }
        return hasher.finalize()
    }
}
