import Foundation
import Testing
@testable import PaneCueCore

@Suite("Cue archive")
struct CueArchiveTests {
    @Test
    func roundTripsPortableCue() throws {
        let cue = CustomScenario(
            name: "Development",
            windows: [
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .ide),
                    gridRect: .left
                ),
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .browser),
                    gridRect: .right,
                    urlString: "https://example.com/docs"
                )
            ],
            voicePhrase: "start development"
        )
        let archive = CueArchive(
            cues: [cue],
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let decoded = try CueArchive.decode(archive.encodedData())

        #expect(decoded == archive)
    }

    @Test
    func rejectsUnsupportedSchemaVersion() throws {
        let cue = CustomScenario(
            name: "Two Windows",
            windows: [
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .ide),
                    gridRect: .left
                ),
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .browser),
                    gridRect: .right
                )
            ]
        )
        let data = try CueArchive(cues: [cue]).encodedData()
        var object = try #require(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        object["schemaVersion"] = 99
        let changed = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: CueArchiveError.unsupportedVersion(99)) {
            try CueArchive.decode(changed)
        }
    }

    @Test
    func rejectsUnsafeURLSchemes() {
        let cue = CustomScenario(
            name: "Unsafe",
            windows: [
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .ide),
                    gridRect: .left
                ),
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .browser),
                    gridRect: .right,
                    urlString: "file:///private/tmp/example"
                )
            ]
        )

        #expect(throws: CueArchiveError.self) {
            try CueArchive(cues: [cue]).encodedData()
        }
    }
}
