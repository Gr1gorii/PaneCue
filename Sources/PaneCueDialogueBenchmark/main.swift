import Darwin
import Foundation
import PaneCueBenchmarkKit

private enum BenchmarkCLIError: LocalizedError {
    case invalidArguments
    case corpusMustBeExternal
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Use --corpus, --repository, and --model with absolute paths."
        case .corpusMustBeExternal:
            return "The private benchmark corpus must live outside the repository."
        case .modelUnavailable:
            return "The benchmark model is unavailable."
        }
    }
}

private struct BenchmarkArguments {
    let corpus: URL
    let repository: URL
    let model: URL

    init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard ["--corpus", "--repository", "--model"].contains(key),
                  index + 1 < arguments.count else {
                throw BenchmarkCLIError.invalidArguments
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        guard let corpusPath = values["--corpus"],
              let repositoryPath = values["--repository"],
              let modelPath = values["--model"],
              corpusPath.hasPrefix("/"),
              repositoryPath.hasPrefix("/"),
              modelPath.hasPrefix("/") else {
            throw BenchmarkCLIError.invalidArguments
        }
        corpus = URL(fileURLWithPath: corpusPath)
            .resolvingSymlinksInPath()
        repository = URL(fileURLWithPath: repositoryPath)
            .resolvingSymlinksInPath()
        model = URL(fileURLWithPath: modelPath)
            .resolvingSymlinksInPath()
    }
}

private func run() throws {
    let arguments = try BenchmarkArguments(
        arguments: CommandLine.arguments
    )
    let repositoryPath = arguments.repository.standardizedFileURL.path
    let corpusPath = arguments.corpus.standardizedFileURL.path
    guard corpusPath != repositoryPath,
          !corpusPath.hasPrefix(repositoryPath + "/") else {
        throw BenchmarkCLIError.corpusMustBeExternal
    }
    guard let modelData = try? Data(contentsOf: arguments.model) else {
        throw BenchmarkCLIError.modelUnavailable
    }

    let corpus = try DialogueBenchmarkCorpusLoader.load(
        from: arguments.corpus
    )
    let trainingTexts = DialogueTrainingTextReader.read(
        from: arguments.repository
    )
    let evaluator = try DialogueBenchmarkEvaluator(modelData: modelData)
    let report = try evaluator.evaluate(
        corpus,
        trainingTexts: trainingTexts
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    guard report.passesFrozenGates else {
        throw DialogueBenchmarkEvaluationError.gateFailed
    }
}

do {
    try run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription
        ?? "Dialogue benchmark failed."
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(EXIT_FAILURE)
}
