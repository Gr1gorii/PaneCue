@preconcurrency import AVFoundation
import Foundation
import PaneCueApp
import PaneCueCore

enum RealtimeVoiceCommandError: LocalizedError {
    case apiKeyMissing
    case internetUnavailable
    case offlinePackMissing
    case microphonePermissionRequired
    case recordingTooShort
    case invalidServerMessage
    case modelReturnedNoAction
    case api(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Add your OpenAI API key to PaneCue before using Cloud voice commands."
        case .internetUnavailable:
            return "Cloud Only mode needs an internet connection. Choose Automatic or Offline Only to keep working without it."
        case .offlinePackMissing:
            return "Prepare the Offline Pack in PaneCue Settings before using local voice commands."
        case .microphonePermissionRequired:
            return "Microphone access is off. PaneCue will not ask again automatically; enable it in System Settings → Privacy & Security → Microphone."
        case .recordingTooShort:
            return "The voice command was too short. Hold for a moment and try again."
        case .invalidServerMessage:
            return "PaneCue received an unreadable response from the voice model."
        case .modelReturnedNoAction:
            return "PaneCue understood the audio, but no window scenario was selected."
        case let .api(message):
            return "OpenAI could not process the voice command: \(message)"
        }
    }
}

@MainActor
final class RealtimeVoiceCommandController {
    enum State: Equatable {
        case idle
        case listening
        case processing
    }

    private let keyStore: OpenAIAPIKeyStore
    private let settings: AIEngineSettingsStore
    private let connectivity: ConnectivityMonitor
    private let offlinePack: ExperimentalOfflinePackManager
    private let recorder = MicrophoneRecorder()
    private let speechRecognizer = OnDeviceSpeechRecognizer()
    private let service = RealtimeCommandService()
    private var activeAPIKey: String?
    private var activeRoute: VoiceExecutionRoute?

    private(set) var state: State = .idle

    init(
        keyStore: OpenAIAPIKeyStore,
        settings: AIEngineSettingsStore,
        connectivity: ConnectivityMonitor,
        offlinePack: ExperimentalOfflinePackManager
    ) {
        self.keyStore = keyStore
        self.settings = settings
        self.connectivity = connectivity
        self.offlinePack = offlinePack
    }

    func startListening() async throws {
        guard state == .idle else {
            return
        }

        let decision = VoiceRoutingPolicy.decision(
            mode: settings.processingMode,
            internetAvailable: connectivity.isOnline,
            apiKeyAvailable: keyStore.hasKey,
            offlinePackAvailable: offlinePack.isReady
        )
        let route: VoiceExecutionRoute
        switch decision {
        case let .route(selectedRoute):
            route = selectedRoute
        case let .unavailable(failure):
            throw Self.error(for: failure)
        }

        guard await requestMicrophoneAccessIfNeeded() else {
            throw RealtimeVoiceCommandError.microphonePermissionRequired
        }

        let apiKey: String?
        switch route {
        case .cloud:
            guard let storedKey = try keyStore.load() else {
                throw RealtimeVoiceCommandError.apiKeyMissing
            }
            apiKey = storedKey
        case .offline:
            try await speechRecognizer.prepare()
            apiKey = nil
        }

        do {
            try recorder.start()
            activeAPIKey = apiKey
            activeRoute = route
            state = .listening
        } catch {
            activeAPIKey = nil
            activeRoute = nil
            state = .idle
            throw error
        }
    }

    func stopAndRun(
        scenarios: [VoiceScenarioReference],
        processingDidBegin: @MainActor () -> Void,
        executor: @escaping @MainActor @Sendable (RealtimeToolCall) async throws -> String
    ) async throws -> String {
        guard state == .listening, let activeRoute else {
            return ""
        }

        let audio = recorder.stop()
        state = .processing
        processingDidBegin()

        defer {
            self.activeAPIKey = nil
            self.activeRoute = nil
            state = .idle
        }

        guard audio.count >= 4_800 else {
            throw RealtimeVoiceCommandError.recordingTooShort
        }

        switch activeRoute {
        case .offline:
            return try await performOffline(
                audioPCM16: audio,
                scenarios: scenarios,
                executor: executor
            )

        case .cloud:
            guard let activeAPIKey else {
                throw RealtimeVoiceCommandError.apiKeyMissing
            }
            do {
                return try await service.perform(
                    audioPCM16: audio,
                    apiKey: activeAPIKey,
                    scenarios: scenarios,
                    executor: executor
                )
            } catch {
                guard settings.processingMode == .automatic,
                      offlinePack.isReady
                else {
                    throw error
                }
                try await speechRecognizer.prepare()
                return try await performOffline(
                    audioPCM16: audio,
                    scenarios: scenarios,
                    executor: executor
                )
            }
        }
    }

    func cancel() {
        _ = recorder.stop()
        activeAPIKey = nil
        activeRoute = nil
        state = .idle
    }

    private func performOffline(
        audioPCM16: Data,
        scenarios: [VoiceScenarioReference],
        executor: @escaping @MainActor @Sendable (RealtimeToolCall) async throws -> String
    ) async throws -> String {
        let transcriptions = try await speechRecognizer.transcriptions(
            audioPCM16: audioPCM16
        )

        for transcript in transcriptions {
            if let intent = OfflineVoiceCommandParser.intent(
                from: transcript,
                scenarios: scenarios
            ) {
                return try await executor(
                    Self.toolCall(from: intent)
                )
            }
        }

        for transcript in transcriptions {
            do {
                let intent = try await offlinePack.commandIntent(
                    transcript: transcript,
                    scenarios: scenarios,
                    model: settings.localCommandModel
                )
                return try await executor(
                    Self.toolCall(from: intent)
                )
            } catch OllamaLocalCommandError.modelReturnedNoAction {
                continue
            } catch PaneCueMiniCommandError.modelReturnedNoAction {
                continue
            }
        }

        throw RealtimeVoiceCommandError.modelReturnedNoAction
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

    private static func error(
        for failure: VoiceRoutingFailure
    ) -> RealtimeVoiceCommandError {
        switch failure {
        case .apiKeyMissing:
            return .apiKeyMissing
        case .internetUnavailable:
            return .internetUnavailable
        case .offlinePackMissing:
            return .offlinePackMissing
        }
    }

    private static func toolCall(
        from intent: VoiceCommandIntent
    ) -> RealtimeToolCall {
        RealtimeToolCall(
            action: intent.action,
            callID: "local-\(UUID().uuidString)",
            arguments: intent.arguments
        )
    }
}

private actor RealtimeCommandService {
    private let model = "gpt-realtime-2.1-mini"

    func perform(
        audioPCM16: Data,
        apiKey: String,
        scenarios: [VoiceScenarioReference],
        executor: @escaping @MainActor @Sendable (RealtimeToolCall) async throws -> String
    ) async throws -> String {
        guard let url = URL(
            string: "wss://api.openai.com/v1/realtime?model=\(model)"
        ) else {
            throw RealtimeVoiceCommandError.invalidServerMessage
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.resume()

        defer {
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        try await send(
            sessionUpdateEvent(
                scenarios: scenarios
            ),
            over: socket
        )

        for chunk in audioPCM16.chunks(ofMaximumSize: 24_000) {
            try await send(
                [
                    "type": "input_audio_buffer.append",
                    "audio": chunk.base64EncodedString()
                ],
                over: socket
            )
        }

        try await send(["type": "input_audio_buffer.commit"], over: socket)
        try await send(["type": "response.create"], over: socket)

        while true {
            let data = try await receiveData(from: socket)

            if let apiMessage = Self.apiErrorMessage(from: data) {
                throw RealtimeVoiceCommandError.api(apiMessage)
            }

            if let call = try RealtimeResponseParser.toolCall(from: data) {
                do {
                    let result = try await executor(call)
                    try await sendToolOutput(
                        callID: call.callID,
                        output: [
                            "success": true,
                            "result": result
                        ],
                        over: socket
                    )
                    return result
                } catch {
                    try? await sendToolOutput(
                        callID: call.callID,
                        output: [
                            "success": false,
                            "error": error.localizedDescription
                        ],
                        over: socket
                    )
                    throw error
                }
            }

            if Self.isCompletedResponse(data) {
                throw RealtimeVoiceCommandError.modelReturnedNoAction
            }
        }
    }

    private func sessionUpdateEvent(
        scenarios: [VoiceScenarioReference]
    ) -> [String: Any] {
        let scenarioPhraseMap = scenarios.map { scenario in
            let phrases = scenario.activationPhrases
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return phrases.isEmpty
                ? scenario.name
                : "\(scenario.name): \(phrases)"
        }.joined(separator: "; ")

        return [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": model,
                "output_modalities": ["text"],
                "instructions": """
                You are PaneCue, a macOS window scenario router. Understand short Russian or English voice commands. Always call exactly one available function. Never answer with prose and never invent actions.

                Use apply_code_and_call for coding during a call or any request to show a small call camera beside the editor.
                Use apply_documentation_and_code only when the user wants a code editor and documentation or a browser arranged together.
                Use apply_notes_and_browser only when the user wants notes and a normal browser window arranged together.
                Use arrange_dynamic_workspace when the user names two applications or app roles and asks for a custom relative layout, size, or position. Prefer 0.5 for equal windows, 0.65 when one should be a little smaller, 0.67 for two thirds, 0.7 for 70/30, 0.75 for a narrow column, and 0.8 for almost full screen. Use leading for left or top and trailing for right or bottom. Known bundle identifiers: VS Code com.microsoft.VSCode, Xcode com.apple.dt.Xcode, Cursor com.todesktop.230313mzl4w4u92, Terminal com.apple.Terminal, Chrome com.google.Chrome, Safari com.apple.Safari, Notes com.apple.Notes, Notion notion.id, Obsidian md.obsidian, Figma com.figma.Desktop.
                Use show_browser_video when the user asks to extract, detach, float, or show a video from a browser separately. Do not use it for a meeting or camera request.
                Use apply_custom_scenario when the user says a saved scenario name or one of its custom activation phrases exposed by that function.
                Use restore_previous_layout when the user asks to restore, undo, return, or put windows back.
                Saved scenario phrase map: \(scenarioPhraseMap.isEmpty ? "none" : scenarioPhraseMap)
                """,
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000
                        ],
                        "turn_detection": NSNull()
                    ]
                ],
                "tools": Self.tools(
                    scenarios: scenarios
                ),
                "tool_choice": "required"
            ]
        ]
    }

    private static func tools(
        scenarios: [VoiceScenarioReference]
    ) -> [[String: Any]] {
        var tools: [[String: Any]] = [[
            "type": "function",
            "name": VoiceCommandAction.applyCodeAndCall.rawValue,
            "description": "Apply the Code + Call layout and show the call camera in a small floating panel.",
            "parameters": emptyObjectSchema
        ], [
            "type": "function",
            "name": VoiceCommandAction.applyDocumentationAndCode.rawValue,
            "description": "Arrange a code editor as the 65% primary window and documentation or a normal browser window as the 35% reference window.",
            "parameters": emptyObjectSchema
        ], [
            "type": "function",
            "name": VoiceCommandAction.applyNotesAndBrowser.rawValue,
            "description": "Arrange a normal browser as the 65% primary window and a notes app as the 35% reference window.",
            "parameters": emptyObjectSchema
        ], [
            "type": "function",
            "name": VoiceCommandAction.arrangeDynamicWorkspace.rawValue,
            "description": "Arrange two user-named applications or app roles with a requested relative size and position.",
            "parameters": [
                "type": "object",
                "properties": [
                    DynamicWorkspaceArgument.primaryKind: [
                        "type": "string",
                        "enum": ["application", "role"]
                    ],
                    DynamicWorkspaceArgument.primaryValue: [
                        "type": "string",
                        "description": "Bundle identifier for an application, or one of ide, meeting, browser, notes, documentation."
                    ],
                    DynamicWorkspaceArgument.primaryName: [
                        "type": "string"
                    ],
                    DynamicWorkspaceArgument.secondaryKind: [
                        "type": "string",
                        "enum": ["application", "role"]
                    ],
                    DynamicWorkspaceArgument.secondaryValue: [
                        "type": "string",
                        "description": "Bundle identifier for an application, or one of ide, meeting, browser, notes, documentation."
                    ],
                    DynamicWorkspaceArgument.secondaryName: [
                        "type": "string"
                    ],
                    DynamicWorkspaceArgument.primaryRatio: [
                        "type": "string",
                        "enum": [
                            "0.5",
                            "0.6",
                            "0.65",
                            "0.67",
                            "0.7",
                            "0.75",
                            "0.8"
                        ]
                    ],
                    DynamicWorkspaceArgument.axis: [
                        "type": "string",
                        "enum": ["horizontal", "vertical"]
                    ],
                    DynamicWorkspaceArgument.primaryPosition: [
                        "type": "string",
                        "enum": ["leading", "trailing"]
                    ]
                ],
                "required": [
                    DynamicWorkspaceArgument.primaryKind,
                    DynamicWorkspaceArgument.primaryValue,
                    DynamicWorkspaceArgument.primaryName,
                    DynamicWorkspaceArgument.secondaryKind,
                    DynamicWorkspaceArgument.secondaryValue,
                    DynamicWorkspaceArgument.secondaryName,
                    DynamicWorkspaceArgument.primaryRatio,
                    DynamicWorkspaceArgument.axis,
                    DynamicWorkspaceArgument.primaryPosition
                ],
                "additionalProperties": false
            ]
        ], [
            "type": "function",
            "name": VoiceCommandAction.showBrowserVideo.rawValue,
            "description": "Extract the most relevant browser video into a floating 16:9 PaneCue panel and move the original Chrome source tab into the background.",
            "parameters": emptyObjectSchema
        ], [
            "type": "function",
            "name": VoiceCommandAction.restorePreviousLayout.rawValue,
            "description": "Restore all windows changed by the current PaneCue scenario.",
            "parameters": emptyObjectSchema
        ]]

        let normalizedNames = scenarios
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !normalizedNames.isEmpty {
            tools.append([
                "type": "function",
                "name": VoiceCommandAction.applyCustomScenario.rawValue,
                "description": "Apply one of the user's saved PaneCue scenarios. Resolve custom activation phrases to the corresponding saved scenario name.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "scenario_name": [
                            "type": "string",
                            "description": "The exact saved scenario name.",
                            "enum": normalizedNames
                        ]
                    ],
                    "required": ["scenario_name"],
                    "additionalProperties": false
                ]
            ])
        }

        return tools
    }

    private static let emptyObjectSchema: [String: Any] = [
        "type": "object",
        "properties": [String: Any](),
        "additionalProperties": false
    ]

    private func send(
        _ event: [String: Any],
        over socket: URLSessionWebSocketTask
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: event)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeVoiceCommandError.invalidServerMessage
        }
        try await socket.send(.string(text))
    }

    private func sendToolOutput(
        callID: String,
        output: [String: Any],
        over socket: URLSessionWebSocketTask
    ) async throws {
        let outputData = try JSONSerialization.data(withJSONObject: output)
        guard let outputText = String(data: outputData, encoding: .utf8) else {
            throw RealtimeVoiceCommandError.invalidServerMessage
        }

        try await send(
            [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": callID,
                    "output": outputText
                ]
            ],
            over: socket
        )
    }

    private func receiveData(
        from socket: URLSessionWebSocketTask
    ) async throws -> Data {
        switch try await socket.receive() {
        case let .data(data):
            return data
        case let .string(text):
            return Data(text.utf8)
        @unknown default:
            throw RealtimeVoiceCommandError.invalidServerMessage
        }
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["type"] as? String == "error",
              let error = event["error"] as? [String: Any]
        else {
            return nil
        }

        return error["message"] as? String ?? "Unknown API error"
    }

    private static func isCompletedResponse(_ data: Data) -> Bool {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return event["type"] as? String == "response.done"
    }
}

private extension Data {
    func chunks(ofMaximumSize size: Int) -> [Data] {
        guard !isEmpty, size > 0 else {
            return []
        }

        return stride(from: startIndex, to: endIndex, by: size).map { start in
            let end = Swift.min(start + size, endIndex)
            return self[start..<end]
        }
    }
}
