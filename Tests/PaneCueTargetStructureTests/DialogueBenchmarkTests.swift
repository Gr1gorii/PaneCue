import Foundation
import PaneCueCore
import Testing
@testable import PaneCueBenchmarkKit

@Suite("Dialogue benchmark contract")
struct DialogueBenchmarkTests {
    @Test
    func acceptsTheFrozenFiveAuthorMinimums() throws {
        let profile = try DialogueBenchmarkCorpusValidator.validate(
            makeCorpus()
        )

        #expect(profile.authorCount == 5)
        #expect(profile.russianCommandCount == 200)
        #expect(profile.englishCommandCount == 200)
        #expect(profile.followUpCount == 100)
        #expect(profile.referentCaseCount == 100)
        #expect(profile.noActionCount == 100)
        #expect(profile.ambiguousCount == 100)
        #expect(profile.safetyCount == 200)
        #expect(profile.totalCount == 700)
    }

    @Test
    func rejectsFewerThanFiveContributingAuthors() {
        let corpus = makeCorpus(contributingAuthorCount: 4)

        #expect(throws: DialogueBenchmarkCorpusError.self) {
            try DialogueBenchmarkCorpusValidator.validate(corpus)
        }
    }

    @Test
    func rejectsAnInputSeenByTraining() throws {
        let corpus = makeCorpus()
        let overlappingInput = try #require(
            corpus.records.first?.utterance
        )

        #expect(throws: DialogueBenchmarkCorpusError.self) {
            try DialogueBenchmarkCorpusValidator.validate(
                corpus,
                trainingTexts: [overlappingInput]
            )
        }
    }

    @Test
    func ambiguityRequiresAnOpaqueResolvableSelection() {
        let corpus = makeCorpus(omitAmbiguitySelection: true)

        #expect(throws: DialogueBenchmarkCorpusError.self) {
            try DialogueBenchmarkCorpusValidator.validate(corpus)
        }
    }

    @Test
    func rejectsUnknownFieldsBeforeDecoding() throws {
        let data = try #require(
            """
            {
              "schema_version": 1,
              "id": "opaque-id",
              "author_id": "author-1",
              "locale": "en",
              "category": "no_action",
              "utterance": "fixture",
              "expected": {"operation": "no_action"},
              "window_title": "forbidden"
            }
            """.data(using: .utf8)
        )

        #expect(
            !DialogueBenchmarkCorpusLoader
                .hasOnlyAllowedRecordKeys(data)
        )
    }

    @Test
    func enforcesEveryFrozenMetric() {
        let passing = report(
            commandAccuracy: 0.95,
            deltaAccuracy: 0.95,
            referentAccuracy: 0.90,
            ambiguitySafety: 1,
            followUpIsolation: 1,
            dangerousActions: 0
        )

        #expect(passing.passesFrozenGates)
        #expect(
            !report(
                commandAccuracy: 0.949,
                deltaAccuracy: 0.95,
                referentAccuracy: 0.90,
                ambiguitySafety: 1,
                followUpIsolation: 1,
                dangerousActions: 0
            ).passesFrozenGates
        )
        #expect(
            !report(
                commandAccuracy: 0.95,
                deltaAccuracy: 0.949,
                referentAccuracy: 0.90,
                ambiguitySafety: 1,
                followUpIsolation: 1,
                dangerousActions: 0
            ).passesFrozenGates
        )
        #expect(
            !report(
                commandAccuracy: 0.95,
                deltaAccuracy: 0.95,
                referentAccuracy: 0.899,
                ambiguitySafety: 1,
                followUpIsolation: 1,
                dangerousActions: 0
            ).passesFrozenGates
        )
        #expect(
            !report(
                commandAccuracy: 0.95,
                deltaAccuracy: 0.95,
                referentAccuracy: 0.90,
                ambiguitySafety: 0.99,
                followUpIsolation: 1,
                dangerousActions: 0
            ).passesFrozenGates
        )
        #expect(
            !report(
                commandAccuracy: 0.95,
                deltaAccuracy: 0.95,
                referentAccuracy: 0.90,
                ambiguitySafety: 1,
                followUpIsolation: 0.99,
                dangerousActions: 0
            ).passesFrozenGates
        )
        #expect(
            !report(
                commandAccuracy: 0.95,
                deltaAccuracy: 0.95,
                referentAccuracy: 0.90,
                ambiguitySafety: 1,
                followUpIsolation: 1,
                dangerousActions: 1
            ).passesFrozenGates
        )
    }

    @Test
    func distinguishesMoveResizeAndSwapWithoutReadingCommandText()
        throws {
        let evaluator = try DialogueBenchmarkEvaluator(
            modelData: Data(contentsOf: modelURL)
        )
        let browserID = UUID()
        let notesID = UUID()
        let browser = slot(
            id: browserID,
            target: ScenarioWindowTarget(role: .browser),
            rect: ScenarioGridRect(
                x: 0,
                y: 0,
                width: 0.65,
                height: 1
            )
        )
        let notes = slot(
            id: notesID,
            target: ScenarioWindowTarget(role: .notes),
            rect: ScenarioGridRect(
                x: 0.65,
                y: 0,
                width: 0.35,
                height: 1
            )
        )
        let before = WorkspacePlan(
            windows: [browser, notes],
            selectedWindowID: browserID
        )

        let moved = WorkspacePlan(
            windows: [notes, browser],
            selectedWindowID: browserID
        )
        #expect(
            evaluator.classifyUpdate(
                before: before,
                after: moved
            ).operation == .moveWindow
        )

        let resized = WorkspacePlan(
            windows: [
                slot(
                    id: browserID,
                    target: browser.target,
                    rect: ScenarioGridRect(
                        x: 0,
                        y: 0,
                        width: 0.55,
                        height: 1
                    )
                ),
                slot(
                    id: notesID,
                    target: notes.target,
                    rect: ScenarioGridRect(
                        x: 0.55,
                        y: 0,
                        width: 0.45,
                        height: 1
                    )
                )
            ],
            selectedWindowID: browserID
        )
        let resizeResult = evaluator.classifyUpdate(
            before: before,
            after: resized
        )
        #expect(resizeResult.operation == .resizeWindow)
        #expect(resizeResult.isIsolated)

        var changedDisplay = resized
        changedDisplay.windows[1].display = .external
        #expect(
            !evaluator.classifyUpdate(
                before: before,
                after: changedDisplay
            ).isIsolated
        )

        let swapped = WorkspacePlan(
            windows: [
                slot(
                    id: browserID,
                    target: notes.target,
                    rect: browser.gridRect
                ),
                slot(
                    id: notesID,
                    target: browser.target,
                    rect: notes.gridRect
                )
            ],
            selectedWindowID: notesID
        )
        let swapResult = evaluator.classifyUpdate(
            before: before,
            after: swapped
        )
        #expect(swapResult.operation == .swapWindows)
        #expect(swapResult.isIsolated)
    }

    private func makeCorpus(
        contributingAuthorCount: Int = 5,
        omitAmbiguitySelection: Bool = false
    ) -> DialogueBenchmarkCorpus {
        let authors = (0..<5).map {
            DialogueBenchmarkAuthor(
                id: "author-\($0)",
                humanAuthored: true,
                consentToEvaluation: true
            )
        }
        var records: [DialogueBenchmarkRecord] = []
        for index in 0..<200 {
            records.append(
                record(
                    id: "ru-\(index)",
                    authorIndex: index % contributingAuthorCount,
                    locale: .russian,
                    category: .command,
                    utterance: "пример-\(index)",
                    expected: DialogueBenchmarkExpectation(
                        operation: .createPlan,
                        targets: ["role:browser"]
                    )
                )
            )
            records.append(
                record(
                    id: "en-\(index)",
                    authorIndex: index % contributingAuthorCount,
                    locale: .english,
                    category: .command,
                    utterance: "fixture-command-\(index)",
                    expected: DialogueBenchmarkExpectation(
                        operation: .createPlan,
                        targets: ["role:browser"]
                    )
                )
            )
        }
        for index in 0..<100 {
            records.append(
                record(
                    id: "follow-up-\(index)",
                    authorIndex: index % contributingAuthorCount,
                    locale: .english,
                    category: .followUp,
                    utterance: "fixture-follow-up-\(index)",
                    contextUtterance: "fixture-context-\(index)",
                    expected: DialogueBenchmarkExpectation(
                        operation: .resizeWindow,
                        referent: "role:browser"
                    )
                )
            )
        }
        for index in 0..<100 {
            records.append(
                record(
                    id: "no-action-\(index)",
                    authorIndex: index % contributingAuthorCount,
                    locale: .english,
                    category: .noAction,
                    utterance: "fixture-no-action-\(index)",
                    expected: DialogueBenchmarkExpectation(
                        operation: .noAction
                    )
                )
            )
            records.append(
                record(
                    id: "ambiguous-\(index)",
                    authorIndex: index % contributingAuthorCount,
                    locale: .english,
                    category: .ambiguous,
                    utterance: "fixture-ambiguous-\(index)",
                    expected: DialogueBenchmarkExpectation(
                        operation: .needsSelection,
                        selectionID: omitAmbiguitySelection
                            ? nil
                            : "candidate-a-\(index)"
                    ),
                    inventory: [
                        inventoryItem("candidate-a-\(index)"),
                        inventoryItem("candidate-b-\(index)")
                    ]
                )
            )
        }
        return DialogueBenchmarkCorpus(
            manifest: DialogueBenchmarkManifest(
                corpusID: "frozen-corpus",
                frozen: true,
                trainingUseProhibited: true,
                authors: authors
            ),
            records: records
        )
    }

    private func record(
        id: String,
        authorIndex: Int,
        locale: DialogueBenchmarkLocale,
        category: DialogueBenchmarkCategory,
        utterance: String,
        contextUtterance: String? = nil,
        expected: DialogueBenchmarkExpectation,
        inventory: [DialogueBenchmarkInventoryItem]? = nil
    ) -> DialogueBenchmarkRecord {
        DialogueBenchmarkRecord(
            id: id,
            authorID: "author-\(authorIndex)",
            locale: locale,
            category: category,
            utterance: utterance,
            contextUtterance: contextUtterance,
            expected: expected,
            inventory: inventory
        )
    }

    private func inventoryItem(
        _ id: String
    ) -> DialogueBenchmarkInventoryItem {
        DialogueBenchmarkInventoryItem(
            id: id,
            bundleIdentifier: "com.example.Browser",
            applicationName: "Browser",
            role: .browser
        )
    }

    private func slot(
        id: UUID,
        target: ScenarioWindowTarget,
        rect: ScenarioGridRect
    ) -> ScenarioWindowSlot {
        ScenarioWindowSlot(
            id: id,
            target: target,
            gridRect: rect
        )
    }

    private var modelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "training/panecue-mini/panecue-mini-v2.bin"
            )
    }

    private func report(
        commandAccuracy: Double,
        deltaAccuracy: Double,
        referentAccuracy: Double,
        ambiguitySafety: Double,
        followUpIsolation: Double,
        dangerousActions: Int
    ) -> DialogueBenchmarkReport {
        DialogueBenchmarkReport(
            profile: DialogueBenchmarkProfile(
                authorCount: 5,
                russianCommandCount: 200,
                englishCommandCount: 200,
                followUpCount: 100,
                referentCaseCount: 100,
                noActionCount: 100,
                ambiguousCount: 100,
                safetyCount: 200,
                totalCount: 700
            ),
            commandAccuracy: commandAccuracy,
            deltaOperationAccuracy: deltaAccuracy,
            referentAccuracy: referentAccuracy,
            ambiguitySafety: ambiguitySafety,
            followUpIsolation: followUpIsolation,
            dangerousActionCount: dangerousActions,
            failures: []
        )
    }
}
