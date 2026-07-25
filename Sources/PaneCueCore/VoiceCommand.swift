import Foundation

public enum VoiceCommandAction: String, CaseIterable, Sendable {
    case applyCodeAndCall = "apply_code_and_call"
    case applyDocumentationAndCode = "apply_documentation_and_code"
    case applyNotesAndBrowser = "apply_notes_and_browser"
    case arrangeDynamicWorkspace = "arrange_dynamic_workspace"
    case showBrowserVideo = "show_browser_video"
    case applyCustomScenario = "apply_custom_scenario"
    case restorePreviousLayout = "restore_previous_layout"
}

public struct RealtimeToolCall: Equatable, Sendable {
    public let action: VoiceCommandAction
    public let callID: String
    public let arguments: [String: String]

    public init(
        action: VoiceCommandAction,
        callID: String,
        arguments: [String: String] = [:]
    ) {
        self.action = action
        self.callID = callID
        self.arguments = arguments
    }
}

public enum RealtimeResponseParserError: LocalizedError, Equatable {
    case unsupportedTool(String)
    case missingCallID

    public var errorDescription: String? {
        switch self {
        case let .unsupportedTool(name):
            return "The voice model requested an unsupported action: \(name)."
        case .missingCallID:
            return "The voice model returned an action without a call identifier."
        }
    }
}

public enum RealtimeResponseParser {
    public static func toolCall(from data: Data) throws -> RealtimeToolCall? {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["type"] as? String == "response.done",
              let response = event["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]],
              let item = output.first(where: {
                  $0["type"] as? String == "function_call"
              }),
              let name = item["name"] as? String
        else {
            return nil
        }

        guard let action = VoiceCommandAction(rawValue: name) else {
            throw RealtimeResponseParserError.unsupportedTool(name)
        }

        guard let callID = item["call_id"] as? String, !callID.isEmpty else {
            throw RealtimeResponseParserError.missingCallID
        }

        var arguments: [String: String] = [:]
        if let encodedArguments = item["arguments"] as? String,
           let argumentsData = encodedArguments.data(using: .utf8),
           let decodedArguments = try? JSONSerialization.jsonObject(
               with: argumentsData
           ) as? [String: Any] {
            arguments = decodedArguments.reduce(into: [:]) {
                result,
                entry in
                if let value = entry.value as? String {
                    result[entry.key] = value
                }
            }
        }

        return RealtimeToolCall(
            action: action,
            callID: callID,
            arguments: arguments
        )
    }
}
