@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

enum OnDeviceSpeechRecognizerError: LocalizedError {
    case permissionRequired
    case unavailable
    case invalidAudio
    case noTranscription
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Speech Recognition access is off. Enable PaneCue in System Settings → Privacy & Security → Speech Recognition."
        case .unavailable:
            return "On-device speech recognition is not available for Russian or English on this Mac."
        case .invalidAudio:
            return "PaneCue could not prepare the recorded audio for offline recognition."
        case .noTranscription:
            return "PaneCue could not recognize the offline voice command."
        case let .recognitionFailed(message):
            return "Offline speech recognition failed: \(message)"
        }
    }
}

@MainActor
public final class OnDeviceSpeechRecognizer {
    public init() {}

    public func prepare() async throws {
        let authorized: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            authorized = false
        @unknown default:
            authorized = false
        }

        guard authorized else {
            throw OnDeviceSpeechRecognizerError.permissionRequired
        }
        guard !availableRecognizers.isEmpty else {
            throw OnDeviceSpeechRecognizerError.unavailable
        }
    }

    public func transcriptions(
        audioPCM16: Data
    ) async throws -> [String] {
        guard !audioPCM16.isEmpty,
              audioPCM16.count.isMultiple(of: MemoryLayout<Int16>.size)
        else {
            throw OnDeviceSpeechRecognizerError.invalidAudio
        }

        var results: [SpeechCandidate] = []
        var lastError: Error?

        for recognizer in availableRecognizers {
            do {
                let candidate = try await recognize(
                    audioPCM16,
                    with: recognizer
                )
                if !candidate.text.isEmpty {
                    results.append(candidate)
                }
            } catch {
                lastError = error
            }
        }

        let unique = results
            .sorted { $0.confidence > $1.confidence }
            .reduce(into: [String]()) { values, candidate in
                if !values.contains(candidate.text) {
                    values.append(candidate.text)
                }
            }

        if unique.isEmpty {
            if let lastError {
                throw lastError
            }
            throw OnDeviceSpeechRecognizerError.noTranscription
        }

        return unique
    }

    private var availableRecognizers: [SFSpeechRecognizer] {
        var localeIdentifiers: [String] = []

        for preferredLanguage in Locale.preferredLanguages {
            if preferredLanguage.lowercased().hasPrefix("ru") {
                localeIdentifiers.append("ru-RU")
            } else if preferredLanguage.lowercased().hasPrefix("en") {
                localeIdentifiers.append("en-US")
            }
        }
        localeIdentifiers.append(contentsOf: ["ru-RU", "en-US"])

        var seen = Set<String>()
        return localeIdentifiers.compactMap { identifier in
            guard seen.insert(identifier).inserted,
                  let recognizer = SFSpeechRecognizer(
                    locale: Locale(identifier: identifier)
                  ),
                  recognizer.supportsOnDeviceRecognition
            else {
                return nil
            }
            return recognizer
        }
    }

    private func recognize(
        _ audioPCM16: Data,
        with recognizer: SFSpeechRecognizer
    ) async throws -> SpeechCandidate {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        ) else {
            throw OnDeviceSpeechRecognizerError.invalidAudio
        }

        let frameCount = AVAudioFrameCount(
            audioPCM16.count / MemoryLayout<Int16>.size
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ), let destination = buffer.int16ChannelData?[0]
        else {
            throw OnDeviceSpeechRecognizerError.invalidAudio
        }

        audioPCM16.withUnsafeBytes { bytes in
            guard let source = bytes.bindMemory(to: Int16.self).baseAddress
            else {
                return
            }
            destination.update(
                from: source,
                count: Int(frameCount)
            )
        }
        buffer.frameLength = frameCount

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .confirmation
        request.append(buffer)
        request.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            let completion = SpeechRecognitionCompletion(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let segments = result.bestTranscription.segments
                    let confidence = segments.isEmpty
                        ? 0
                        : segments.reduce(0) {
                            $0 + Double($1.confidence)
                        } / Double(segments.count)
                    completion.succeed(
                        SpeechCandidate(
                            text: result.bestTranscription
                                .formattedString
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ),
                            confidence: confidence
                        )
                    )
                } else if let error {
                    completion.fail(
                        OnDeviceSpeechRecognizerError.recognitionFailed(
                            error.localizedDescription
                        )
                    )
                }
            }
        }
    }
}

private struct SpeechCandidate: Sendable {
    let text: String
    let confidence: Double
}

private final class SpeechRecognitionCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation:
        CheckedContinuation<SpeechCandidate, Error>?

    init(
        _ continuation: CheckedContinuation<SpeechCandidate, Error>
    ) {
        self.continuation = continuation
    }

    func succeed(_ candidate: SpeechCandidate) {
        finish(with: .success(candidate))
    }

    func fail(_ error: Error) {
        finish(with: .failure(error))
    }

    private func finish(
        with result: Result<SpeechCandidate, Error>
    ) {
        let pendingContinuation = lock.withLock {
            let value = self.continuation
            self.continuation = nil
            return value
        }
        pendingContinuation?.resume(with: result)
    }
}
