import Foundation
import Testing

@Suite("Privacy logging")
struct PrivacyLoggingTests {
    @Test
    func runtimeLogsDoNotExposeInterpolatedUserContext() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = repositoryRoot.appendingPathComponent("Sources")
        let sourceFiles = try swiftFiles(in: sourcesRoot)

        let sensitiveTokens = [
            "applicationName",
            "window.title",
            "sourceWindow.windowID",
            "localizedDescription",
            "transcript",
            "urlString",
            "absoluteString"
        ]

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            #expect(
                !source.contains("privacy: .public"),
                "Public log interpolation is forbidden in \(sourceFile.lastPathComponent)"
            )

            let lines = source.components(separatedBy: .newlines)
            for index in lines.indices where isLoggerCall(lines[index]) {
                let callContext = lines[index]
                #expect(
                    callContext.contains("\")"),
                    "Logger calls must use a single-line static message in \(sourceFile.lastPathComponent):\(index + 1)"
                )
                #expect(
                    !callContext.contains("\\("),
                    "Log interpolation is forbidden in \(sourceFile.lastPathComponent):\(index + 1)"
                )
                for token in sensitiveTokens {
                    #expect(
                        !callContext.contains(token),
                        "Logger call contains \(token) in \(sourceFile.lastPathComponent):\(index + 1)"
                    )
                }
            }
        }
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw PrivacyLoggingTestError.couldNotReadSources
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            return url
        }
    }

    private func isLoggerCall(_ line: String) -> Bool {
        [
            ".trace(",
            ".debug(",
            ".info(",
            ".notice(",
            ".warning(",
            ".error(",
            ".critical("
        ].contains { line.contains("logger\($0)") }
    }
}

private enum PrivacyLoggingTestError: Error {
    case couldNotReadSources
}
