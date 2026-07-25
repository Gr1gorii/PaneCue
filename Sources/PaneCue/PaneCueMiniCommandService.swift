import Foundation
import PaneCueCore

enum PaneCueMiniCommandError: LocalizedError {
    case modelUnavailable
    case modelReturnedNoAction

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "PaneCue Mini is missing from this app build."
        case .modelReturnedNoAction:
            return "PaneCue understood the words but did not find a safe window action."
        }
    }
}

actor PaneCueMiniCommandService {
    private var loadedModel: PaneCueMiniModel?

    var isAvailable: Bool {
        modelURL != nil
    }

    func intent(
        transcript: String,
        scenarios: [VoiceScenarioReference]
    ) throws -> VoiceCommandIntent {
        let model: PaneCueMiniModel
        if let loadedModel {
            model = loadedModel
        } else {
            guard let modelURL else {
                throw PaneCueMiniCommandError.modelUnavailable
            }
            model = try PaneCueMiniModel(
                data: Data(contentsOf: modelURL)
            )
            loadedModel = model
        }

        let prediction = model.prediction(
            for: transcript,
            scenarios: scenarios
        )
        guard let intent = prediction.intent else {
            throw PaneCueMiniCommandError.modelReturnedNoAction
        }
        return intent
    }

    func unload() {
        loadedModel = nil
    }

    private var modelURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent(
                    "Models/panecue-mini-v2.bin"
                ),
            URL(
                fileURLWithPath:
                    FileManager.default.currentDirectoryPath
            )
            .appendingPathComponent(
                "training/panecue-mini/panecue-mini-v2.bin"
            ),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "training/panecue-mini/panecue-mini-v2.bin"
                )
        ].compactMap { $0 }

        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}
