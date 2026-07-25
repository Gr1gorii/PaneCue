import Foundation

public enum PaneCueMiniModelError: LocalizedError, Equatable {
    case invalidModel
    case unsupportedVersion(UInt32)

    public var errorDescription: String? {
        switch self {
        case .invalidModel:
            return "The built-in PaneCue Mini model is damaged or incomplete."
        case let .unsupportedVersion(version):
            return "PaneCue Mini model version \(version) is not supported."
        }
    }
}

public struct PaneCueMiniPrediction: Equatable, Sendable {
    public var intent: VoiceCommandIntent?
    public var label: String
    public var confidence: Float
    public var margin: Float

    public init(
        intent: VoiceCommandIntent?,
        label: String,
        confidence: Float,
        margin: Float
    ) {
        self.intent = intent
        self.label = label
        self.confidence = confidence
        self.margin = margin
    }
}

/// Quantized intent inference shared by the app and tests. PaneCue Mini uses a
/// 64-bit stable hash so the Swift runtime produces exactly the same features
/// as the Python trainer.
public struct PaneCueMiniModel: Sendable {
    private static let labels = [
        VoiceCommandAction.applyCodeAndCall.rawValue,
        VoiceCommandAction.applyDocumentationAndCode.rawValue,
        VoiceCommandAction.applyNotesAndBrowser.rawValue,
        VoiceCommandAction.arrangeDynamicWorkspace.rawValue,
        VoiceCommandAction.showBrowserVideo.rawValue,
        VoiceCommandAction.restorePreviousLayout.rawValue,
        "no_action"
    ]

    private let dimension: Int
    private let confidenceThreshold: Float
    private let marginThreshold: Float
    private let temperature: Float
    private let biases: [Float]
    private let scales: [Float]
    private let weights: [Int8]

    public var learnedParameterCount: Int {
        weights.count + biases.count
    }

    public init(data: Data) throws {
        var reader = BinaryReader(data: data)
        guard try reader.readBytes(count: 8)
            == Array("PCMINI1\0".utf8) else {
            throw PaneCueMiniModelError.invalidModel
        }

        let version = try reader.readUInt32()
        guard version == 1 else {
            throw PaneCueMiniModelError.unsupportedVersion(version)
        }

        let dimension = Int(try reader.readUInt32())
        let classCount = Int(try reader.readUInt32())
        guard dimension > 0,
              classCount == Self.labels.count,
              dimension <= 1_048_576 else {
            throw PaneCueMiniModelError.invalidModel
        }

        let confidenceThreshold = try reader.readFloat()
        let marginThreshold = try reader.readFloat()
        let temperature = try reader.readFloat()
        let biases = try (0..<classCount).map { _ in
            try reader.readFloat()
        }
        let scales = try (0..<classCount).map { _ in
            try reader.readFloat()
        }
        let weightCount = dimension * classCount
        let rawWeights = try reader.readBytes(count: weightCount)
        guard reader.isAtEnd,
              confidenceThreshold.isFinite,
              marginThreshold.isFinite,
              temperature.isFinite,
              temperature > 0,
              biases.allSatisfy(\.isFinite),
              scales.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw PaneCueMiniModelError.invalidModel
        }

        self.dimension = dimension
        self.confidenceThreshold = confidenceThreshold
        self.marginThreshold = marginThreshold
        self.temperature = temperature
        self.biases = biases
        self.scales = scales
        weights = rawWeights.map { Int8(bitPattern: $0) }
    }

    public func prediction(
        for transcript: String,
        scenarios: [VoiceScenarioReference] = []
    ) -> PaneCueMiniPrediction {
        if OfflineVoiceCommandParser.explicitlyDeclinesAction(
            from: transcript
        ) {
            return PaneCueMiniPrediction(
                intent: nil,
                label: "no_action",
                confidence: 1,
                margin: 1
            )
        }

        if let deterministic = OfflineVoiceCommandParser.intent(
            from: transcript,
            scenarios: scenarios
        ) {
            return PaneCueMiniPrediction(
                intent: deterministic,
                label: deterministic.action.rawValue,
                confidence: 1,
                margin: 1
            )
        }

        let indices = Self.featureIndices(
            transcript,
            dimension: dimension
        )
        guard !indices.isEmpty else {
            return PaneCueMiniPrediction(
                intent: nil,
                label: "no_action",
                confidence: 1,
                margin: 1
            )
        }

        var logits = biases
        for classIndex in logits.indices {
            let rowOffset = classIndex * dimension
            var score = logits[classIndex]
            for featureIndex in indices {
                score += Float(
                    weights[rowOffset + featureIndex]
                ) * scales[classIndex]
            }
            logits[classIndex] = score / temperature
        }

        let maximum = logits.max() ?? 0
        let exponentials = logits.map {
            Foundation.exp($0 - maximum)
        }
        let total = exponentials.reduce(0, +)
        let probabilities = exponentials.map {
            total > 0 ? $0 / total : 0
        }
        let ordered = probabilities.indices.sorted {
            probabilities[$0] > probabilities[$1]
        }
        guard let best = ordered.first else {
            return PaneCueMiniPrediction(
                intent: nil,
                label: "no_action",
                confidence: 1,
                margin: 1
            )
        }
        let confidence = probabilities[best]
        let runnerUp = ordered.dropFirst().first.map {
            probabilities[$0]
        } ?? 0
        let margin = confidence - runnerUp
        let label = Self.labels[best]

        guard label != "no_action",
              confidence >= confidenceThreshold,
              margin >= marginThreshold,
              let action = VoiceCommandAction(rawValue: label) else {
            return PaneCueMiniPrediction(
                intent: nil,
                label: "no_action",
                confidence: confidence,
                margin: margin
            )
        }

        if action == .arrangeDynamicWorkspace {
            let intent = DynamicWorkspaceCommandParser.intent(
                from: transcript
            )
            return PaneCueMiniPrediction(
                intent: intent,
                label: intent == nil ? "no_action" : label,
                confidence: confidence,
                margin: margin
            )
        }

        return PaneCueMiniPrediction(
            intent: VoiceCommandIntent(action: action),
            label: label,
            confidence: confidence,
            margin: margin
        )
    }

    public static func featureIndices(
        _ text: String,
        dimension: Int
    ) -> [Int] {
        guard dimension > 0 else {
            return []
        }
        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            return []
        }

        var features = Set<String>()
        let words = normalized.split(separator: " ").map(String.init)
        for word in words {
            features.insert("w:\(word)")
        }
        for index in 0..<max(0, words.count - 1) {
            features.insert(
                "b:\(words[index])_\(words[index + 1])"
            )
        }

        let compact = Array(
            "^\(normalized.replacingOccurrences(of: " ", with: "_"))$"
        )
        for width in 2...5 where compact.count >= width {
            for start in 0...(compact.count - width) {
                let gram = String(compact[start..<(start + width)])
                features.insert("c\(width):\(gram)")
            }
        }

        return Array(
            Set(features.map {
                Int(stableHash($0) % UInt64(dimension))
            })
        ).sorted()
    }

    private static func normalize(_ value: String) -> String {
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

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(0xcbf29ce484222325)) {
            ($0 ^ UInt64($1)) &* 0x100000001b3
        }
    }
}

private struct BinaryReader {
    private let data: Data
    private(set) var offset = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset <= data.count - count else {
            throw PaneCueMiniModelError.invalidModel
        }
        defer {
            offset += count
        }
        return Array(data[offset..<(offset + count)])
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return bytes.enumerated().reduce(UInt32(0)) { result, entry in
            result | (UInt32(entry.element) << UInt32(entry.offset * 8))
        }
    }

    mutating func readFloat() throws -> Float {
        Float(bitPattern: try readUInt32())
    }
}
