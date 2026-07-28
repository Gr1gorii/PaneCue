@preconcurrency import AVFoundation
import Foundation
import PaneCueCore

enum CommandLabError: LocalizedError {
    case unavailable
    case microphonePermissionRequired
    case recordingTooShort

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Arrange is temporarily unavailable."
        case .microphonePermissionRequired:
            return "Enable PaneCue in System Settings → Privacy & Security → Microphone."
        case .recordingTooShort:
            return "The recording was too short. Speak for a moment and try again."
        }
    }
}

enum CommandLabAnalysis: Equatable, Sendable {
    case plan(WorkspacePlan, summary: String)
    case action(VoiceCommandIntent)
    case undo
    case savePlan(name: String)
    case noAction
}

@MainActor
final class CommandLabService {
    private let recorder = MicrophoneRecorder()
    private let speechRecognizer = OnDeviceSpeechRecognizer()
    private let corrections = CommandLabCorrectionStore()

    private(set) var isListening = false

    var correctionCount: Int {
        corrections.count
    }

    func analyze(
        transcript: String,
        currentPlan: WorkspacePlan?,
        scenarios: [VoiceScenarioReference],
        savedScenarios: [CustomScenario],
        offlinePack: OfflinePackManager
    ) async throws -> CommandLabAnalysis {
        let trimmed = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return .noAction
        }

        switch corrections.lookup(trimmed) {
        case let .intent(intent):
            return .action(intent)
        case let .plan(plan):
            return .plan(plan, summary: "Loaded your local correction")
        case .noAction:
            return .noAction
        case .missing:
            break
        }

        let mentionedTargets =
            DynamicWorkspaceCommandParser.mentionedTargets(
                in: trimmed
            )
        if mentionedTargets.count >= 2,
           let plan =
               WorkspacePlanCommandInterpreter.initialPlan(
                   from: trimmed
               ) {
            return .plan(
                plan,
                summary: "Created a \(plan.windows.count)-window plan"
            )
        }

        if let currentPlan,
           let result = WorkspacePlanCommandInterpreter.interpret(
               trimmed,
               currentPlan: currentPlan
           ) {
            switch result {
            case let .updated(plan, summary):
                return .plan(plan, summary: summary)
            case .undo:
                return .undo
            case let .save(name):
                return .savePlan(name: name)
            }
        }

        if currentPlan == nil,
           let plan =
               WorkspacePlanCommandInterpreter.initialPlan(
                   from: trimmed
               ) {
            return .plan(
                plan,
                summary: "Created a \(plan.windows.count)-window plan"
            )
        }

        if OfflineVoiceCommandParser.explicitlyDeclinesAction(
            from: trimmed
        ) {
            return .noAction
        }
        if let deterministic = OfflineVoiceCommandParser.intent(
            from: trimmed,
            scenarios: scenarios
        ) {
            if let plan = WorkspacePlan.from(
                intent: deterministic,
                scenarios: savedScenarios
            ) {
                return .plan(plan, summary: "Created a workspace plan")
            }
            return .action(deterministic)
        }

        do {
            let intent = try await offlinePack.commandIntent(
                transcript: trimmed,
                scenarios: scenarios,
                model: .smart
            )
            if let plan = WorkspacePlan.from(
                intent: intent,
                scenarios: savedScenarios
            ) {
                return .plan(plan, summary: "Created a workspace plan")
            }
            return .action(intent)
        } catch PaneCueMiniCommandError.modelReturnedNoAction {
            return .noAction
        }
    }

    func saveCorrection(
        transcript: String,
        intent: VoiceCommandIntent?
    ) {
        corrections.save(
            transcript: transcript,
            intent: intent
        )
    }

    func saveCorrection(
        transcript: String,
        plan: WorkspacePlan
    ) {
        corrections.save(
            transcript: transcript,
            plan: plan
        )
    }

    func startListening() async throws {
        guard !isListening else {
            return
        }
        guard await requestMicrophoneAccessIfNeeded() else {
            throw CommandLabError.microphonePermissionRequired
        }
        try await speechRecognizer.prepare()
        try recorder.start()
        isListening = true
    }

    func stopAndTranscribe() async throws -> String {
        guard isListening else {
            throw CommandLabError.unavailable
        }
        let audio = recorder.stop()
        isListening = false
        guard audio.count >= 4_800 else {
            throw CommandLabError.recordingTooShort
        }
        return try await speechRecognizer.transcriptions(
            audioPCM16: audio
        ).first ?? ""
    }

    func cancelListening() {
        _ = recorder.stop()
        isListening = false
    }

    @discardableResult
    func resetPersonalization() -> Int {
        corrections.clear()
    }

    private func requestMicrophoneAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

@MainActor
private final class CommandLabCorrectionStore {
    enum Lookup {
        case missing
        case intent(VoiceCommandIntent)
        case plan(WorkspacePlan)
        case noAction
    }

    private struct StoredCorrection: Codable {
        var normalizedTranscript: String
        var action: String?
        var arguments: [String: String]
        var plan: WorkspacePlan?
        var updatedAt: Date

        private enum CodingKeys: String, CodingKey {
            case normalizedTranscript
            case action
            case arguments
            case plan
            case updatedAt
        }

        init(
            normalizedTranscript: String,
            action: String?,
            arguments: [String: String],
            plan: WorkspacePlan?,
            updatedAt: Date
        ) {
            self.normalizedTranscript = normalizedTranscript
            self.action = action
            self.arguments = arguments
            self.plan = plan
            self.updatedAt = updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )
            normalizedTranscript = try container.decode(
                String.self,
                forKey: .normalizedTranscript
            )
            action = try container.decodeIfPresent(
                String.self,
                forKey: .action
            )
            arguments = try container.decodeIfPresent(
                [String: String].self,
                forKey: .arguments
            ) ?? [:]
            plan = try container.decodeIfPresent(
                WorkspacePlan.self,
                forKey: .plan
            )
            updatedAt = try container.decodeIfPresent(
                Date.self,
                forKey: .updatedAt
            ) ?? .distantPast
        }
    }

    private let defaults: UserDefaults
    private let key = PaneCuePersistenceKey.commandCorrections
    private var corrections: [StoredCorrection]

    var count: Int {
        corrections.count
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(
                [StoredCorrection].self,
                from: data
           ) {
            corrections = decoded
        } else {
            corrections = []
        }
    }

    func lookup(_ transcript: String) -> Lookup {
        let key = normalize(transcript)
        guard let correction = corrections.first(where: {
            $0.normalizedTranscript == key
        }) else {
            return .missing
        }
        if let plan = correction.plan {
            return .plan(plan)
        }
        guard let actionName = correction.action,
              let action = VoiceCommandAction(
                rawValue: actionName
              ) else {
            return .noAction
        }
        return .intent(
            VoiceCommandIntent(
                action: action,
                arguments: correction.arguments
            )
        )
    }

    func save(
        transcript: String,
        intent: VoiceCommandIntent?
    ) {
        let key = normalize(transcript)
        guard !key.isEmpty else {
            return
        }
        corrections.removeAll {
            $0.normalizedTranscript == key
        }
        corrections.insert(
            StoredCorrection(
                normalizedTranscript: key,
                action: intent?.action.rawValue,
                arguments: intent?.arguments ?? [:],
                plan: nil,
                updatedAt: Date()
            ),
            at: 0
        )
        persist()
    }

    func save(
        transcript: String,
        plan: WorkspacePlan
    ) {
        let key = normalize(transcript)
        guard !key.isEmpty else {
            return
        }
        corrections.removeAll {
            $0.normalizedTranscript == key
        }
        corrections.insert(
            StoredCorrection(
                normalizedTranscript: key,
                action: nil,
                arguments: [:],
                plan: plan,
                updatedAt: Date()
            ),
            at: 0
        )
        persist()
    }

    private func persist() {
        if corrections.count > 200 {
            corrections.removeLast(
                corrections.count - 200
            )
        }
        if let data = try? JSONEncoder().encode(corrections) {
            defaults.set(data, forKey: self.key)
        }
    }

    @discardableResult
    func clear() -> Int {
        let removedCount = corrections.count
        corrections.removeAll()
        defaults.removeObject(forKey: key)
        return removedCount
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-zа-яё0-9]+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
