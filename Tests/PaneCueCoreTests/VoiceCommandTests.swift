import Foundation
import Testing
@testable import PaneCueCore

struct VoiceCommandTests {
    @Test
    func parsesKnownFunctionCallFromCompletedResponse() throws {
        let data = Data(
            """
            {
              "type": "response.done",
              "response": {
                "output": [
                  {
                    "type": "function_call",
                    "name": "apply_code_and_call",
                    "call_id": "call_123",
                    "arguments": "{}"
                  }
                ]
              }
            }
            """.utf8
        )

        let call = try RealtimeResponseParser.toolCall(from: data)

        #expect(
            call == RealtimeToolCall(
                action: .applyCodeAndCall,
                callID: "call_123"
            )
        )
    }

    @Test
    func ignoresEventsThatAreNotCompletedResponses() throws {
        let data = Data(
            """
            {
              "type": "response.created",
              "response": {}
            }
            """.utf8
        )

        #expect(try RealtimeResponseParser.toolCall(from: data) == nil)
    }

    @Test
    func rejectsUnknownFunctions() throws {
        let data = Data(
            """
            {
              "type": "response.done",
              "response": {
                "output": [
                  {
                    "type": "function_call",
                    "name": "delete_everything",
                    "call_id": "call_456",
                    "arguments": "{}"
                  }
                ]
              }
            }
            """.utf8
        )

        #expect(throws: RealtimeResponseParserError.unsupportedTool("delete_everything")) {
            try RealtimeResponseParser.toolCall(from: data)
        }
    }

    @Test
    func parsesBrowserVideoFunctionCall() throws {
        let data = Data(
            """
            {
              "type": "response.done",
              "response": {
                "output": [
                  {
                    "type": "function_call",
                    "name": "show_browser_video",
                    "call_id": "call_video",
                    "arguments": "{}"
                  }
                ]
              }
            }
            """.utf8
        )

        #expect(
            try RealtimeResponseParser.toolCall(from: data)
                == RealtimeToolCall(
                    action: .showBrowserVideo,
                    callID: "call_video"
                )
        )
    }

    @Test
    func parsesCustomScenarioName() throws {
        let data = Data(
            """
            {
              "type": "response.done",
              "response": {
                "output": [
                  {
                    "type": "function_call",
                    "name": "apply_custom_scenario",
                    "call_id": "call_custom",
                    "arguments": "{\\"scenario_name\\":\\"Research\\"}"
                  }
                ]
              }
            }
            """.utf8
        )

        #expect(
            try RealtimeResponseParser.toolCall(from: data)
                == RealtimeToolCall(
                    action: .applyCustomScenario,
                    callID: "call_custom",
                    arguments: ["scenario_name": "Research"]
                )
        )
    }
}
