import Foundation
import PaneCueCore

enum OllamaLocalCommandError: LocalizedError {
    case runtimeUnavailable
    case serverUnavailable
    case invalidResponse
    case modelReturnedNoAction
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "PaneCue’s local AI runtime is not available."
        case .serverUnavailable:
            return "PaneCue could not start its local AI runtime."
        case .invalidResponse:
            return "The local command model returned an unreadable response."
        case .modelReturnedNoAction:
            return "The local model understood the words but did not select a PaneCue action."
        case let .requestFailed(message):
            return "Local AI could not complete the command: \(message)"
        }
    }
}

actor OllamaLocalCommandService {
    static let requiredModels = [
        "panecue-qwen3:1.0"
    ]

    private let baseURL = URL(string: "http://127.0.0.1:11434")!
    private var serverProcess: Process?

    var isRuntimeAvailable: Bool {
        executableURL != nil
    }

    func installedModelsOnDisk() -> Set<String> {
        let environment = ProcessInfo.processInfo.environment
        let modelsRoot: URL
        if let configuredPath = environment["OLLAMA_MODELS"],
           !configuredPath.isEmpty {
            modelsRoot = URL(fileURLWithPath: configuredPath)
        } else {
            modelsRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ollama/models")
        }

        let manifests = modelsRoot
            .appendingPathComponent("manifests")
            .appendingPathComponent("registry.ollama.ai")
            .appendingPathComponent("library")

        return Set(
            Self.requiredModels.filter { model in
                let parts = model.split(
                    separator: ":",
                    maxSplits: 1
                ).map(String.init)
                let name = parts.first ?? model
                let tag = parts.count > 1 ? parts[1] : "latest"
                let manifest = manifests
                    .appendingPathComponent(name)
                    .appendingPathComponent(tag)
                return FileManager.default.fileExists(
                    atPath: manifest.path
                )
            }
        )
    }

    func installedModels() async throws -> Set<String> {
        try await ensureServer()
        let data = try await request(path: "api/tags")
        guard let root = try JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let models = root["models"] as? [[String: Any]]
        else {
            throw OllamaLocalCommandError.invalidResponse
        }

        return Set(
            models.compactMap { model in
                model["name"] as? String
            }
        )
    }

    func pull(model: String) async throws {
        try await ensureServer()
        if model == "panecue-qwen3:1.0",
           let bundledModelURL {
            try importBundledModel(
                named: model,
                from: bundledModelURL
            )
            return
        }
        _ = try await request(
            path: "api/pull",
            method: "POST",
            body: [
                "model": model,
                "stream": false
            ],
            timeout: 1_800
        )
    }

    func intent(
        transcript: String,
        scenarios: [VoiceScenarioReference],
        selection: LocalCommandModel
    ) async throws -> VoiceCommandIntent {
        try await ensureServer()

        for model in selection.ollamaModelNames {
            let data = try await request(
                path: "api/chat",
                method: "POST",
                body: Self.chatBody(
                    model: model,
                    transcript: transcript,
                    scenarios: scenarios
                ),
                timeout: 90
            )
            if LocalModelResponseParser.explicitlyDeclinesAction(
                from: data
            ) {
                throw OllamaLocalCommandError.modelReturnedNoAction
            }
            if let intent = try LocalModelResponseParser.intent(from: data) {
                return intent
            }
        }

        throw OllamaLocalCommandError.modelReturnedNoAction
    }

    func unloadRunningModels() async {
        guard (try? await healthCheck()) == true,
              let data = try? await request(path: "api/ps"),
              let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let models = root["models"] as? [[String: Any]]
        else {
            return
        }

        for model in models {
            guard let name = model["name"] as? String else {
                continue
            }
            _ = try? await request(
                path: "api/generate",
                method: "POST",
                body: [
                    "model": name,
                    "keep_alive": 0
                ],
                timeout: 30
            )
        }
    }

    func shutdown() async {
        await unloadRunningModels()
        if let serverProcess, serverProcess.isRunning {
            serverProcess.terminate()
        }
        serverProcess = nil
    }

    private func ensureServer() async throws {
        if (try? await healthCheck()) == true {
            return
        }

        guard let executableURL else {
            throw OllamaLocalCommandError.runtimeUnavailable
        }

        if serverProcess?.isRunning != true {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            environment["OLLAMA_HOST"] = "127.0.0.1:11434"
            environment["OLLAMA_KEEP_ALIVE"] = "30s"
            process.environment = environment
            do {
                try process.run()
                serverProcess = process
            } catch {
                throw OllamaLocalCommandError.requestFailed(
                    error.localizedDescription
                )
            }
        }

        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if (try? await healthCheck()) == true {
                return
            }
        }

        throw OllamaLocalCommandError.serverUnavailable
    }

    private func healthCheck() async throws -> Bool {
        _ = try await request(path: "api/tags", timeout: 2)
        return true
    }

    private var executableURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("Runtime/ollama"),
            URL(
                fileURLWithPath:
                    "/Applications/Ollama.app/Contents/Resources/ollama"
            ),
            URL(fileURLWithPath: "/usr/local/bin/ollama"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
        ].compactMap { $0 }

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private var bundledModelURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent(
                    "Models/panecue-qwen3-1.7b-q4_k_m.gguf"
                ),
            URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath
            )
            .appendingPathComponent(
                "training/ollama/qwen/panecue-qwen3-1.7b-q4_k_m.gguf"
            )
        ].compactMap { $0 }

        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private func importBundledModel(
        named model: String,
        from modelURL: URL
    ) throws {
        guard let executableURL else {
            throw OllamaLocalCommandError.runtimeUnavailable
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PaneCueModel-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: temporaryDirectory
            )
        }

        let linkedModelURL = temporaryDirectory
            .appendingPathComponent("panecue-model.gguf")
        try FileManager.default.createSymbolicLink(
            at: linkedModelURL,
            withDestinationURL: modelURL
        )
        let modelfileURL = temporaryDirectory
            .appendingPathComponent("Modelfile")
        try """
        FROM ./panecue-model.gguf
        PARAMETER temperature 0
        PARAMETER num_ctx 4096
        """.write(
            to: modelfileURL,
            atomically: true,
            encoding: .utf8
        )

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "create",
            model,
            "-f",
            modelfileURL.path
        ]
        process.currentDirectoryURL = temporaryDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:11434"
        process.environment = environment
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw OllamaLocalCommandError.requestFailed(
                "The bundled PaneCue model could not be installed."
            )
        }
    }

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        timeout: TimeInterval = 10
    ) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body {
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try JSONSerialization.data(
                withJSONObject: body
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                let message = String(data: data, encoding: .utf8)
                    ?? "Unknown local runtime error"
                throw OllamaLocalCommandError.requestFailed(message)
            }
            return data
        } catch let error as OllamaLocalCommandError {
            throw error
        } catch {
            throw OllamaLocalCommandError.requestFailed(
                error.localizedDescription
            )
        }
    }

    private static func chatBody(
        model: String,
        transcript: String,
        scenarios: [VoiceScenarioReference]
    ) -> [String: Any] {
        let scenarioInstructions = scenarios.map { scenario in
            let phrases = scenario.activationPhrases
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return phrases.isEmpty
                ? scenario.name
                : "\(scenario.name) (phrases: \(phrases))"
        }.joined(separator: "; ")

        return [
            "model": model,
            "stream": false,
            "think": false,
            "keep_alive": "30s",
            "messages": [[
                "role": "user",
                "content": """
                Route this Russian or English request to exactly one PaneCue tool. Never answer with prose. Use only the supplied tools.
                Saved scenarios: \(scenarioInstructions.isEmpty ? "none" : scenarioInstructions)
                Request: \(transcript)
                """
            ]],
            "tools": tools(scenarios: scenarios),
            "options": [
                "temperature": 0,
                "num_predict": 64
            ]
        ]
    }

    private static func tools(
        scenarios: [VoiceScenarioReference]
    ) -> [[String: Any]] {
        var result = [
            tool(
                action: .applyCodeAndCall,
                description: "Code editor together with a call or camera."
            ),
            tool(
                action: .applyDocumentationAndCode,
                description: "Code editor together with documentation."
            ),
            tool(
                action: .applyNotesAndBrowser,
                description: "Notes together with a normal browser window."
            ),
            tool(
                action: .showBrowserVideo,
                description: "Extract a browser video into a floating player."
            ),
            tool(
                action: .restorePreviousLayout,
                description: "Restore the previous window layout."
            ),
            [
                "type": "function",
                "function": [
                    "name": "no_action",
                    "description": "Choose this when the request is unrelated, negated, ambiguous, or cannot be performed safely by PaneCue.",
                    "parameters": [
                        "type": "object",
                        "properties": [:],
                        "additionalProperties": false
                    ]
                ]
            ]
        ]

        if !scenarios.isEmpty {
            result.append([
                "type": "function",
                "function": [
                    "name": VoiceCommandAction.applyCustomScenario.rawValue,
                    "description": "Apply a saved custom PaneCue scenario.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "scenario_name": [
                                "type": "string",
                                "enum": scenarios.map(\.name)
                            ]
                        ],
                        "required": ["scenario_name"],
                        "additionalProperties": false
                    ]
                ]
            ])
        }

        return result
    }

    private static func tool(
        action: VoiceCommandAction,
        description: String
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": action.rawValue,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": [String: Any](),
                    "additionalProperties": false
                ]
            ]
        ]
    }
}
