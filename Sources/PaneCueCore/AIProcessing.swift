import Foundation

public enum AIProcessingMode: String, CaseIterable, Codable, Sendable {
    case automatic
    case offline
    case cloud
}

public enum LocalCommandModel: String, CaseIterable, Codable, Sendable {
    case smart
    case functionGemma
    case qwen

    public var ollamaModelNames: [String] {
        switch self {
        case .smart:
            return []
        case .functionGemma:
            return ["functiongemma:270m"]
        case .qwen:
            return ["panecue-qwen3:1.0"]
        }
    }
}

public enum VoiceExecutionRoute: Equatable, Sendable {
    case offline
    case cloud
}

public enum VoiceRoutingFailure: Equatable, Sendable {
    case apiKeyMissing
    case internetUnavailable
    case offlinePackMissing
}

public enum VoiceRoutingDecision: Equatable, Sendable {
    case route(VoiceExecutionRoute)
    case unavailable(VoiceRoutingFailure)
}

public enum VoiceRoutingPolicy {
    public static func decision(
        mode: AIProcessingMode,
        internetAvailable: Bool,
        apiKeyAvailable: Bool,
        offlinePackAvailable: Bool
    ) -> VoiceRoutingDecision {
        switch mode {
        case .automatic:
            if internetAvailable, apiKeyAvailable {
                return .route(.cloud)
            }
            if offlinePackAvailable {
                return .route(.offline)
            }
            if !internetAvailable {
                return .unavailable(.offlinePackMissing)
            }
            return .unavailable(.apiKeyMissing)

        case .offline:
            return offlinePackAvailable
                ? .route(.offline)
                : .unavailable(.offlinePackMissing)

        case .cloud:
            guard internetAvailable else {
                return .unavailable(.internetUnavailable)
            }
            return apiKeyAvailable
                ? .route(.cloud)
                : .unavailable(.apiKeyMissing)
        }
    }
}

public struct VoiceScenarioReference: Equatable, Sendable {
    public var name: String
    public var activationPhrases: [String]

    public init(
        name: String,
        activationPhrases: [String] = []
    ) {
        self.name = name
        self.activationPhrases = activationPhrases
    }
}

public struct VoiceCommandIntent: Equatable, Sendable {
    public var action: VoiceCommandAction
    public var arguments: [String: String]

    public init(
        action: VoiceCommandAction,
        arguments: [String: String] = [:]
    ) {
        self.action = action
        self.arguments = arguments
    }
}

public enum OfflineVoiceCommandParser {
    public static func intent(
        from transcript: String,
        scenarios: [VoiceScenarioReference]
    ) -> VoiceCommandIntent? {
        let text = normalize(transcript)
        guard !text.isEmpty else {
            return nil
        }

        if explicitlyDeclinesAction(from: transcript) {
            return nil
        }

        if containsAny(
            text,
            phrases: [
                "верни все обратно",
                "вернуть все обратно",
                "восстанови окна",
                "восстановить окна",
                "отмени раскладку",
                "предыдущая раскладка",
                "restore windows",
                "restore layout",
                "undo layout",
                "put windows back"
            ]
        ) {
            return VoiceCommandIntent(action: .restorePreviousLayout)
        }

        if containsAny(
            text,
            phrases: [
                "видео из браузера",
                "вытащи видео",
                "вынеси видео",
                "открой видео отдельно",
                "плавающее видео",
                "текущее видео",
                "компактное окно с видео",
                "browser video",
                "extract video",
                "detach video",
                "float video"
            ]
        ) {
            return VoiceCommandIntent(action: .showBrowserVideo)
        }

        for scenario in scenarios {
            let phrases = [scenario.name] + scenario.activationPhrases
            if phrases
                .map(normalize)
                .filter({ !$0.isEmpty })
                .contains(where: { text.contains($0) }) {
                return VoiceCommandIntent(
                    action: .applyCustomScenario,
                    arguments: ["scenario_name": scenario.name]
                )
            }
        }

        if DynamicWorkspaceCommandParser.hasExplicitLayoutRequest(
            in: transcript
        ), let dynamicIntent = DynamicWorkspaceCommandParser.intent(
            from: transcript
        ) {
            return dynamicIntent
        }

        let mentionsCode = containsAny(
            text,
            phrases: [
                "код",
                "редактор",
                "ide",
                "code",
                "editor",
                "coding",
                "программир",
                "проект",
                "project",
                "terminal",
                "терминал",
                "xcode",
                "vscode",
                "vs code",
                "cursor",
                "windsurf",
                "zed",
                "pycharm",
                "intellij"
            ]
        )
        let mentionsCall = containsAny(
            text,
            phrases: [
                "созвон",
                "звонок",
                "видеозвонок",
                "камера",
                "встреча",
                "call",
                "meeting",
                "camera",
                "zoom",
                "facetime",
                "face time",
                "teams",
                "webex"
            ]
        )
        if mentionsCode, mentionsCall {
            return VoiceCommandIntent(action: .applyCodeAndCall)
        }

        let mentionsDocumentation = containsAny(
            text,
            phrases: [
                "документац",
                "справк",
                "референс",
                "reference",
                "documentation",
                "docs",
                "api",
                "инструкц",
                "руководств",
                "мануал",
                "manual",
                "guide"
            ]
        )
        if containsAny(
            text,
            phrases: [
                "работы по инструкции",
                "работать по инструкции",
                "work from instructions",
                "follow the instructions"
            ]
        ) {
            return VoiceCommandIntent(
                action: .applyDocumentationAndCode
            )
        }
        if mentionsCode, mentionsDocumentation {
            return VoiceCommandIntent(action: .applyDocumentationAndCode)
        }

        let mentionsNotes = containsAny(
            text,
            phrases: [
                "заметк",
                "запис",
                "notes",
                "note taking",
                "notion",
                "obsidian",
                "bear",
                "onenote",
                "блокнот",
                "конспект"
            ]
        )
        let mentionsBrowser = containsAny(
            text,
            phrases: [
                "браузер",
                "chrome",
                "safari",
                "firefox",
                "arc",
                "brave",
                "edge",
                "browser",
                "web"
            ]
        )
        if mentionsNotes, mentionsBrowser {
            return VoiceCommandIntent(action: .applyNotesAndBrowser)
        }

        return DynamicWorkspaceCommandParser.intent(from: transcript)
    }

    public static func explicitlyDeclinesAction(
        from transcript: String
    ) -> Bool {
        let text = normalize(transcript)
        return containsAny(
            text,
            phrases: [
                "не меняй окна",
                "не меняй расположение",
                "ничего не делай",
                "не применяй сценарий",
                "не открывай",
                "не выноси видео",
                "не став",
                "не располаг",
                "не размещ",
                "не показывай",
                "не делай",
                "не запускай",
                "пока не надо",
                "можно ли",
                "как сделать",
                "может быть потом",
                "давай потом",
                "позже можно",
                "я просто говорю",
                "я просто рассказываю",
                "я только говорю",
                "только обсуждаю",
                "просто обсуждаю",
                "do not change",
                "do not arrange",
                "do not open",
                "do not apply",
                "do not extract",
                "don t",
                "is it possible",
                "how can i",
                "maybe later",
                "do it later",
                "nothing",
                "only mentioning",
                "only discussing"
            ]
        )
    }

    private static func containsAny(
        _ text: String,
        phrases: [String]
    ) -> Bool {
        phrases.contains { text.contains(normalize($0)) }
    }

    private static func normalize(_ value: String) -> String {
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

public enum LocalModelResponseParser {
    public static func explicitlyDeclinesAction(
        from data: Data
    ) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let message = root["message"] as? [String: Any]
        else {
            return false
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]],
           let function = toolCalls.first?["function"]
                as? [String: Any],
           function["name"] as? String == "no_action" {
            return true
        }

        guard let content = message["content"] as? String else {
            return false
        }
        let trimmed = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed == "no_action" {
            return true
        }
        guard let encoded = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(
                with: encoded
              ) as? [String: Any]
        else {
            return false
        }
        return object["action"] as? String == "no_action"
    }

    public static func intent(from data: Data) throws -> VoiceCommandIntent? {
        guard let root = try JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let message = root["message"] as? [String: Any]
        else {
            return nil
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]],
           let function = toolCalls.first?["function"]
                as? [String: Any],
           let name = function["name"] as? String {
            if name == "no_action" {
                return nil
            }
            guard let action = VoiceCommandAction(rawValue: name) else {
                return nil
            }
            return VoiceCommandIntent(
                action: action,
                arguments: parseArguments(function["arguments"])
            )
        }

        guard let content = message["content"] as? String else {
            return nil
        }
        return intent(fromContent: content)
    }

    private static func intent(
        fromContent content: String
    ) -> VoiceCommandIntent? {
        let trimmed = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if trimmed == "no_action" {
            return nil
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
           let name = object["action"] as? String {
            if name == "no_action" {
                return nil
            }
            guard let action = VoiceCommandAction(rawValue: name) else {
                return nil
            }
            var arguments = stringValues(object)
            arguments.removeValue(forKey: "action")
            return VoiceCommandIntent(
                action: action,
                arguments: arguments
            )
        }

        let actions = VoiceCommandAction.allCases.filter {
            trimmed.contains($0.rawValue)
        }
        guard actions.count == 1, let action = actions.first else {
            return nil
        }
        return VoiceCommandIntent(action: action)
    }

    private static func parseArguments(
        _ rawArguments: Any?
    ) -> [String: String] {
        if let values = rawArguments as? [String: Any] {
            return stringValues(values)
        }

        if let encoded = rawArguments as? String,
           let data = encoded.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] {
            return stringValues(values)
        }

        return [:]
    }

    private static func stringValues(
        _ values: [String: Any]
    ) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            if let value = entry.value as? String {
                result[entry.key] = value
            }
        }
    }
}
