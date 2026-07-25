import Foundation
import Testing
@testable import PaneCueCore

@Suite("AI processing")
struct AIProcessingTests {
    @Test
    func smartLocalDoesNotStartAnOllamaModel() {
        #expect(
            LocalCommandModel.smart.ollamaModelNames.isEmpty
        )
    }

    @Test
    func automaticUsesCloudOnlineWithoutLoadingLocalPack() {
        #expect(
            VoiceRoutingPolicy.decision(
                mode: .automatic,
                internetAvailable: true,
                apiKeyAvailable: true,
                offlinePackAvailable: false
            ) == .route(.cloud)
        )
    }

    @Test
    func automaticUsesOfflinePackWithoutInternet() {
        #expect(
            VoiceRoutingPolicy.decision(
                mode: .automatic,
                internetAvailable: false,
                apiKeyAvailable: true,
                offlinePackAvailable: true
            ) == .route(.offline)
        )
    }

    @Test
    func cloudModeNeverFallsBackToLocal() {
        #expect(
            VoiceRoutingPolicy.decision(
                mode: .cloud,
                internetAvailable: false,
                apiKeyAvailable: true,
                offlinePackAvailable: true
            ) == .unavailable(.internetUnavailable)
        )
    }

    @Test
    func offlineModeNeverRequiresAPIKey() {
        #expect(
            VoiceRoutingPolicy.decision(
                mode: .offline,
                internetAvailable: false,
                apiKeyAvailable: false,
                offlinePackAvailable: true
            ) == .route(.offline)
        )
    }

    @Test
    func parsesKnownRussianCommandWithoutModel() {
        #expect(
            OfflineVoiceCommandParser.intent(
                from: "Открой код и созвон",
                scenarios: []
            ) == VoiceCommandIntent(action: .applyCodeAndCall)
        )
    }

    @Test
    func mapsActivationPhraseBackToSavedScenarioName() {
        let scenario = VoiceScenarioReference(
            name: "Research",
            activationPhrases: ["начать исследование"]
        )

        #expect(
            OfflineVoiceCommandParser.intent(
                from: "Давай начать исследование",
                scenarios: [scenario]
            ) == VoiceCommandIntent(
                action: .applyCustomScenario,
                arguments: ["scenario_name": "Research"]
            )
        )
    }

    @Test
    func extractsApplicationsAndRelativeSizeFromNaturalCommand() {
        let intent = OfflineVoiceCommandParser.intent(
            from: "Открой вскод, а заментки сделай чуть поменьше",
            scenarios: []
        )

        #expect(intent?.action == .arrangeDynamicWorkspace)
        #expect(
            intent?.arguments[DynamicWorkspaceArgument.primaryValue]
                == "com.microsoft.VSCode"
        )
        #expect(
            intent?.arguments[DynamicWorkspaceArgument.secondaryValue]
                == ApplicationRole.notes.rawValue
        )
        #expect(
            intent?.arguments[DynamicWorkspaceArgument.primaryRatio]
                == "0.65"
        )
    }

    @Test
    func dynamicLayoutUnderstandsEqualAndVerticalPlacement() {
        let intent = DynamicWorkspaceCommandParser.intent(
            from: "Покажи Chrome сверху, а заметки снизу поровну"
        )

        #expect(intent?.action == .arrangeDynamicWorkspace)
        #expect(
            intent?.arguments[DynamicWorkspaceArgument.axis]
                == "vertical"
        )
        #expect(
            intent?.arguments[DynamicWorkspaceArgument.primaryRatio]
                == "0.5"
        )
    }

    @Test
    func positionAttachedToSecondaryPlacesPrimaryOpposite() {
        let intent = DynamicWorkspaceCommandParser.intent(
            from: "Открой VS Code и заметки справа"
        )

        #expect(
            intent?.arguments[
                DynamicWorkspaceArgument.primaryPosition
            ] == "leading"
        )
    }

    @Test
    func negatedLayoutNeverExecutes() {
        #expect(
            OfflineVoiceCommandParser.intent(
                from: "Не открывай VS Code и заметки",
                scenarios: []
            ) == nil
        )
    }

    @Test
    func paneCueMiniStaysTinyAndRoutesHeldOutCommands() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelURL = projectURL.appendingPathComponent(
            "training/panecue-mini/panecue-mini-v2.bin"
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: modelURL.path
        )
        let size = attributes[.size] as? NSNumber
        #expect((size?.intValue ?? .max) < 600_000)

        let model = try PaneCueMiniModel(
            data: Data(contentsOf: modelURL)
        )
        #expect(model.learnedParameterCount == 499_975)
        let dataset = try String(
            contentsOf: projectURL.appendingPathComponent(
                "training/data/test.jsonl"
            ),
            encoding: .utf8
        )
        let scenarios = [
            VoiceScenarioReference(
                name: "Deep Work",
                activationPhrases: [
                    "глубокая работа",
                    "focus workspace"
                ]
            ),
            VoiceScenarioReference(
                name: "Исследование",
                activationPhrases: [
                    "начать исследование",
                    "research workspace"
                ]
            ),
            VoiceScenarioReference(
                name: "Монтаж",
                activationPhrases: [
                    "монтажный режим",
                    "editing workspace"
                ]
            ),
            VoiceScenarioReference(
                name: "Writing",
                activationPhrases: [
                    "режим письма",
                    "writing workspace"
                ]
            )
        ]

        var correct = 0
        var total = 0
        for line in dataset.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let root = try JSONSerialization
                    .jsonObject(with: data) as? [String: Any],
                  let messages = root["messages"] as? [[String: Any]],
                  let user = messages.first?["content"] as? String,
                  let assistant = messages.last,
                  let calls = assistant["tool_calls"]
                    as? [[String: Any]],
                  let function = calls.first?["function"]
                    as? [String: Any],
                  let expected = function["name"] as? String else {
                continue
            }
            let transcript = user.components(
                separatedBy: "Request: "
            ).last ?? user
            let prediction = model.prediction(
                for: transcript,
                scenarios: scenarios
            )
            let actual = prediction.intent?.action.rawValue
                ?? "no_action"
            correct += expected == actual ? 1 : 0
            total += 1
        }

        #expect(total > 100)
        #expect(Double(correct) / Double(total) >= 0.98)
    }

    @Test
    func paneCueMiniV2UnderstandsExpandedLayoutLanguage() {
        let samples: [
            (
                transcript: String,
                ratio: String,
                axis: String,
                primary: String
            )
        ] = [
            (
                "Сделай PyCharm главным, а Telegram узкой колонкой справа",
                "0.75",
                "horizontal",
                "com.jetbrains.pycharm"
            ),
            (
                "Открой Arc и Bear поровну",
                "0.5",
                "horizontal",
                "company.thebrowser.Browser"
            ),
            (
                "Хочу VS Code 70 на 30 вместе с заметками",
                "0.7",
                "horizontal",
                "com.microsoft.VSCode"
            ),
            (
                "Размести Xcode на две трети экрана и Safari на оставшуюся треть",
                "0.67",
                "horizontal",
                "com.apple.dt.Xcode"
            ),
            (
                "Покажи Finder сверху, а Terminal снизу",
                "0.5",
                "vertical",
                "com.apple.finder"
            )
        ]

        for sample in samples {
            let intent = OfflineVoiceCommandParser.intent(
                from: sample.transcript,
                scenarios: []
            )
            #expect(intent?.action == .arrangeDynamicWorkspace)
            #expect(
                intent?.arguments[
                    DynamicWorkspaceArgument.primaryRatio
                ] == sample.ratio
            )
            #expect(
                intent?.arguments[DynamicWorkspaceArgument.axis]
                    == sample.axis
            )
            #expect(
                intent?.arguments[
                    DynamicWorkspaceArgument.primaryValue
                ] == sample.primary
            )
        }
    }

    @Test
    func paneCueMiniV2RejectsQuestionsAndDeferredCommands() {
        let nonCommands = [
            "Можно ли поставить Figma рядом со Slack?",
            "Может быть потом откроем Arc и Bear",
            "Как сделать VS Code большим, а Notes маленькими?",
            "Please don't arrange Chrome and Obsidian",
            "Maybe later put Xcode beside Safari"
        ]

        for transcript in nonCommands {
            #expect(
                OfflineVoiceCommandParser.explicitlyDeclinesAction(
                    from: transcript
                )
            )
        }
    }

    @Test
    func paneCueMiniV2PassesIndependentLanguageChallenge() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try PaneCueMiniModel(
            data: Data(
                contentsOf: projectURL.appendingPathComponent(
                    "training/panecue-mini/panecue-mini-v2.bin"
                )
            )
        )
        let challenge = try String(
            contentsOf: projectURL.appendingPathComponent(
                "training/panecue-mini/challenge-v2.jsonl"
            ),
            encoding: .utf8
        )

        var correct = 0
        var total = 0
        for line in challenge.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let row = try JSONSerialization
                    .jsonObject(with: data) as? [String: String],
                  let transcript = row["text"],
                  let expected = row["action"] else {
                continue
            }
            let actual = model.prediction(
                for: transcript
            ).intent?.action.rawValue ?? "no_action"
            correct += expected == actual ? 1 : 0
            total += 1
        }

        #expect(total >= 35)
        #expect(Double(correct) / Double(total) >= 0.97)
    }

    @Test
    func parsesOllamaToolCall() throws {
        let data = Data(
            """
            {
              "message": {
                "role": "assistant",
                "tool_calls": [
                  {
                    "function": {
                      "name": "apply_custom_scenario",
                      "arguments": {
                        "scenario_name": "Research"
                      }
                    }
                  }
                ]
              }
            }
            """.utf8
        )

        #expect(
            try LocalModelResponseParser.intent(from: data)
                == VoiceCommandIntent(
                    action: .applyCustomScenario,
                    arguments: ["scenario_name": "Research"]
                )
        )
    }

    @Test
    func parsesAllowListedActionFromLocalModelText() throws {
        let data = Data(
            """
            {
              "message": {
                "role": "assistant",
                "content": "apply_notes_and_browser"
              }
            }
            """.utf8
        )

        #expect(
            try LocalModelResponseParser.intent(from: data)
                == VoiceCommandIntent(action: .applyNotesAndBrowser)
        )
    }

    @Test
    func treatsExplicitNoActionAsNoIntent() throws {
        let toolData = Data(
            """
            {
              "message": {
                "role": "assistant",
                "tool_calls": [
                  {
                    "function": {
                      "name": "no_action",
                      "arguments": {}
                    }
                  }
                ]
              }
            }
            """.utf8
        )
        let contentData = Data(
            """
            {
              "message": {
                "role": "assistant",
                "content": "no_action"
              }
            }
            """.utf8
        )

        #expect(
            try LocalModelResponseParser.intent(from: toolData) == nil
        )
        #expect(
            LocalModelResponseParser.explicitlyDeclinesAction(
                from: toolData
            )
        )
        #expect(
            try LocalModelResponseParser.intent(from: contentData) == nil
        )
        #expect(
            LocalModelResponseParser.explicitlyDeclinesAction(
                from: contentData
            )
        )
    }
}
