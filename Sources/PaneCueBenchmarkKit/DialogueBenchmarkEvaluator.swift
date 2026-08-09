import Foundation
import PaneCueCore

public struct DialogueBenchmarkFailure: Codable, Equatable, Sendable {
    public let recordID: String
    public let reasons: [String]

    public init(recordID: String, reasons: [String]) {
        self.recordID = recordID
        self.reasons = reasons
    }
}

public struct DialogueBenchmarkReport: Codable, Equatable, Sendable {
    public let profile: DialogueBenchmarkProfile
    public let commandAccuracy: Double
    public let deltaOperationAccuracy: Double
    public let referentAccuracy: Double
    public let ambiguitySafety: Double
    public let followUpIsolation: Double
    public let dangerousActionCount: Int
    public let failures: [DialogueBenchmarkFailure]

    public var passesFrozenGates: Bool {
        commandAccuracy >= 0.95
            && deltaOperationAccuracy >= 0.95
            && referentAccuracy >= 0.90
            && ambiguitySafety == 1
            && followUpIsolation == 1
            && dangerousActionCount == 0
    }

    init(
        profile: DialogueBenchmarkProfile,
        commandAccuracy: Double,
        deltaOperationAccuracy: Double,
        referentAccuracy: Double,
        ambiguitySafety: Double,
        followUpIsolation: Double,
        dangerousActionCount: Int,
        failures: [DialogueBenchmarkFailure]
    ) {
        self.profile = profile
        self.commandAccuracy = commandAccuracy
        self.deltaOperationAccuracy = deltaOperationAccuracy
        self.referentAccuracy = referentAccuracy
        self.ambiguitySafety = ambiguitySafety
        self.followUpIsolation = followUpIsolation
        self.dangerousActionCount = dangerousActionCount
        self.failures = failures
    }
}

public enum DialogueBenchmarkEvaluationError: LocalizedError, Equatable,
    Sendable {
    case invalidModel
    case gateFailed

    public var errorDescription: String? {
        switch self {
        case .invalidModel:
            return "The benchmark model is unavailable or invalid."
        case .gateFailed:
            return "One or more frozen dialogue benchmark gates failed."
        }
    }
}

public struct DialogueBenchmarkEvaluator {
    private let model: PaneCueMiniModel

    public init(modelData: Data) throws {
        do {
            model = try PaneCueMiniModel(data: modelData)
        } catch {
            throw DialogueBenchmarkEvaluationError.invalidModel
        }
    }

    public func evaluate(
        _ corpus: DialogueBenchmarkCorpus,
        trainingTexts: [String]
    ) throws -> DialogueBenchmarkReport {
        let profile = try DialogueBenchmarkCorpusValidator.validate(
            corpus,
            trainingTexts: trainingTexts
        )
        var commandTotal = 0
        var commandCorrect = 0
        var deltaTotal = 0
        var deltaCorrect = 0
        var referentTotal = 0
        var referentCorrect = 0
        var ambiguityTotal = 0
        var ambiguityCorrect = 0
        var followUpTotal = 0
        var isolatedFollowUps = 0
        var dangerousActions = 0
        var failures: [DialogueBenchmarkFailure] = []

        for record in corpus.records {
            var reasons: [String] = []
            switch record.category {
            case .command:
                commandTotal += 1
                let actual = freshResult(for: record.utterance)
                if commandMatches(record.expected, actual: actual) {
                    commandCorrect += 1
                } else {
                    reasons.append("command_mismatch")
                }
            case .followUp:
                followUpTotal += 1
                deltaTotal += 1
                let actual = followUpResult(for: record)
                if actual.operation == record.expected.operation {
                    deltaCorrect += 1
                } else {
                    reasons.append("delta_operation_mismatch")
                }
                if let expectedReferent = record.expected.referent {
                    referentTotal += 1
                    if actual.referent == expectedReferent {
                        referentCorrect += 1
                    } else {
                        reasons.append("referent_mismatch")
                    }
                }
                if actual.isIsolated {
                    isolatedFollowUps += 1
                } else {
                    reasons.append("follow_up_not_isolated")
                }
            case .noAction:
                let actual = freshResult(for: record.utterance)
                if actual.operation != .noAction {
                    dangerousActions += 1
                    reasons.append("dangerous_action")
                }
            case .ambiguous:
                ambiguityTotal += 1
                if ambiguityIsExposedAndResolved(for: record) {
                    ambiguityCorrect += 1
                } else {
                    reasons.append("ambiguity_not_exposed_or_resolved")
                }
            }

            if !reasons.isEmpty {
                failures.append(
                    DialogueBenchmarkFailure(
                        recordID: record.id,
                        reasons: reasons
                    )
                )
            }
        }

        return DialogueBenchmarkReport(
            profile: profile,
            commandAccuracy: ratio(commandCorrect, commandTotal),
            deltaOperationAccuracy: ratio(deltaCorrect, deltaTotal),
            referentAccuracy: ratio(referentCorrect, referentTotal),
            ambiguitySafety: ratio(ambiguityCorrect, ambiguityTotal),
            followUpIsolation: ratio(
                isolatedFollowUps,
                followUpTotal
            ),
            dangerousActionCount: dangerousActions,
            failures: failures
        )
    }

    private func commandMatches(
        _ expected: DialogueBenchmarkExpectation,
        actual: ActualDialogueResult
    ) -> Bool {
        guard expected.operation == actual.operation else {
            return false
        }
        if let expectedAction = expected.action,
           expectedAction != actual.action {
            return false
        }
        if let expectedTargets = expected.targets,
           expectedTargets != actual.plan.map(targetKeys) {
            return false
        }
        return true
    }

    private func freshResult(
        for utterance: String
    ) -> ActualDialogueResult {
        let mentionedTargets = DynamicWorkspaceCommandParser
            .mentionedTargets(in: utterance)
        if mentionedTargets.count >= 2,
           let plan = WorkspacePlanCommandInterpreter.initialPlan(
               from: utterance
           ) {
            return ActualDialogueResult(
                operation: .createPlan,
                plan: plan
            )
        }
        if let plan = WorkspacePlanCommandInterpreter.initialPlan(
            from: utterance
        ) {
            return ActualDialogueResult(
                operation: .createPlan,
                plan: plan
            )
        }
        if OfflineVoiceCommandParser.explicitlyDeclinesAction(
            from: utterance
        ) {
            return ActualDialogueResult(operation: .noAction)
        }
        if let deterministic = OfflineVoiceCommandParser.intent(
            from: utterance,
            scenarios: []
        ) {
            return result(for: deterministic)
        }

        let prediction = model.prediction(for: utterance)
        guard let intent = prediction.intent else {
            return ActualDialogueResult(operation: .noAction)
        }
        return result(for: intent)
    }

    private func result(
        for intent: VoiceCommandIntent
    ) -> ActualDialogueResult {
        if let plan = WorkspacePlan.from(intent: intent) {
            return ActualDialogueResult(
                operation: .createPlan,
                plan: plan,
                action: intent.action.rawValue
            )
        }
        return ActualDialogueResult(
            operation: .directAction,
            action: intent.action.rawValue
        )
    }

    private func ambiguityIsExposedAndResolved(
        for record: DialogueBenchmarkRecord
    ) -> Bool {
        let initial = freshResult(for: record.utterance)
        guard let plan = initial.plan,
              let scenario = plan.scenario(named: "Benchmark"),
              let selectionID = record.expected.selectionID else {
            return false
        }
        let inventory = (record.inventory ?? []).map(\.workspaceItem)
        let resolution = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: inventory,
            hasExternalDisplay: inventory.contains {
                $0.display == .external
            },
            hasActiveCall: inventory.contains { $0.role == .meeting }
        )
        guard resolution.requiresCandidateSelection,
              let slot = resolution.slots.first(where: {
                  guard case .ambiguous = $0.state else {
                      return false
                  }
                  return $0.candidates.contains(where: {
                      $0.id.rawValue == selectionID
                  })
              }),
              let selected = try? resolution.selecting(
                  EphemeralWindowIdentifier(rawValue: selectionID),
                  for: slot.id
              ),
              selected.selectedCandidateIDsBySlot[slot.id]
                == selectionID else {
            return false
        }
        return !selected.requiresCandidateSelection
    }

    private func followUpResult(
        for record: DialogueBenchmarkRecord
    ) -> ActualDialogueResult {
        guard let context = record.contextUtterance,
              let before = freshResult(for: context).plan,
              let result = WorkspacePlanCommandInterpreter.interpret(
                  record.utterance,
                  currentPlan: before
              ) else {
            return ActualDialogueResult(
                operation: .noAction,
                isIsolated: false
            )
        }

        switch result {
        case .undo:
            return ActualDialogueResult(
                operation: .undo,
                isIsolated: true
            )
        case .save:
            return ActualDialogueResult(
                operation: .save,
                isIsolated: true
            )
        case let .updated(after, _):
            return classifyUpdate(before: before, after: after)
        }
    }

    func classifyUpdate(
        before: WorkspacePlan,
        after: WorkspacePlan
    ) -> ActualDialogueResult {
        let beforeIDs = Set(before.windows.map(\.id))
        let afterIDs = Set(after.windows.map(\.id))
        let addedIDs = afterIDs.subtracting(beforeIDs)
        let removedIDs = beforeIDs.subtracting(afterIDs)
        let beforeTargets = Dictionary(
            uniqueKeysWithValues: before.windows.map {
                ($0.id, targetKey($0.target))
            }
        )
        let afterTargets = Dictionary(
            uniqueKeysWithValues: after.windows.map {
                ($0.id, targetKey($0.target))
            }
        )

        if after.windows.count == before.windows.count + 1,
           addedIDs.count == 1,
           let addedID = addedIDs.first,
           let addedSlot = after.windows.first(where: {
               $0.id == addedID
           }) {
            return ActualDialogueResult(
                operation: .addWindow,
                plan: after,
                referent: targetKey(addedSlot.target),
                isIsolated: stableSlotMetadataMatches(
                    ids: beforeIDs,
                    before: before,
                    after: after,
                    includeTarget: true
                )
            )
        }
        if before.windows.count == after.windows.count + 1,
           removedIDs.count == 1,
           let removedID = removedIDs.first,
           let removedSlot = before.windows.first(where: {
               $0.id == removedID
           }) {
            return ActualDialogueResult(
                operation: .removeWindow,
                plan: after,
                referent: targetKey(removedSlot.target),
                isIsolated: stableSlotMetadataMatches(
                    ids: afterIDs,
                    before: before,
                    after: after,
                    includeTarget: true
                )
            )
        }
        let assignmentsChanged = beforeIDs == afterIDs
            && beforeIDs.contains {
                beforeTargets[$0] != afterTargets[$0]
            }
        if assignmentsChanged {
            let beforeRectangles = Dictionary(
                uniqueKeysWithValues: before.windows.map {
                    ($0.id, $0.gridRect)
                }
            )
            let rectanglesUnchanged = after.windows.allSatisfy {
                beforeRectangles[$0.id] == $0.gridRect
            }
            let changedAssignments = beforeIDs.filter {
                beforeTargets[$0] != afterTargets[$0]
            }
            let targetSetPreserved = beforeTargets.values.sorted()
                == afterTargets.values.sorted()
            return ActualDialogueResult(
                operation: .swapWindows,
                plan: after,
                referent: selectedTargetKey(in: after),
                isIsolated: rectanglesUnchanged
                    && changedAssignments.count == 2
                    && targetSetPreserved
                    && stableSlotMetadataMatches(
                        ids: beforeIDs,
                        before: before,
                        after: after,
                        includeTarget: false
                    )
            )
        }

        guard beforeIDs == afterIDs,
              stableSlotMetadataMatches(
                  ids: beforeIDs,
                  before: before,
                  after: after,
                  includeTarget: true
              ),
              let selectedID = after.selectedWindowID,
              let beforeSlot = before.windows.first(where: {
                  $0.id == selectedID
              }),
              let afterSlot = after.windows.first(where: {
                  $0.id == selectedID
              }) else {
            return ActualDialogueResult(
                operation: .noAction,
                plan: after,
                isIsolated: false
            )
        }
        let sizeChanged = beforeSlot.gridRect.width
                != afterSlot.gridRect.width
            || beforeSlot.gridRect.height != afterSlot.gridRect.height
        let positionChanged = beforeSlot.gridRect.x
                != afterSlot.gridRect.x
            || beforeSlot.gridRect.y != afterSlot.gridRect.y
        let operation: DialogueBenchmarkOperation
        let windowOrderChanged = before.windows.map(\.id)
            != after.windows.map(\.id)
        if windowOrderChanged {
            operation = .moveWindow
        } else if sizeChanged {
            operation = .resizeWindow
        } else if positionChanged {
            operation = .moveWindow
        } else {
            operation = .noAction
        }
        return ActualDialogueResult(
            operation: operation,
            plan: after,
            referent: targetKey(afterSlot.target),
            isIsolated: operation != .noAction
        )
    }

    private func stableSlotMetadataMatches(
        ids: Set<UUID>,
        before: WorkspacePlan,
        after: WorkspacePlan,
        includeTarget: Bool
    ) -> Bool {
        let beforeSlots = Dictionary(
            uniqueKeysWithValues: before.windows.map { ($0.id, $0) }
        )
        let afterSlots = Dictionary(
            uniqueKeysWithValues: after.windows.map { ($0.id, $0) }
        )
        return ids.allSatisfy { id in
            guard let beforeSlot = beforeSlots[id],
                  let afterSlot = afterSlots[id] else {
                return false
            }
            return (!includeTarget
                    || beforeSlot.target == afterSlot.target)
                && beforeSlot.display == afterSlot.display
                && beforeSlot.launchIfNeeded == afterSlot.launchIfNeeded
                && beforeSlot.urlString == afterSlot.urlString
        }
    }

    private func selectedTargetKey(
        in plan: WorkspacePlan
    ) -> String? {
        guard let selectedID = plan.selectedWindowID,
              let slot = plan.windows.first(where: {
                  $0.id == selectedID
              }) else {
            return nil
        }
        return targetKey(slot.target)
    }

    private func targetKeys(_ plan: WorkspacePlan) -> [String] {
        plan.windows.map { targetKey($0.target) }
    }

    private func targetKey(_ target: ScenarioWindowTarget) -> String {
        switch target.kind {
        case .application:
            return "application:\(target.application?.bundleIdentifier ?? "")"
        case .role:
            return "role:\(target.role?.rawValue ?? "other")"
        }
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else {
            return 0
        }
        return Double(numerator) / Double(denominator)
    }
}

struct ActualDialogueResult {
    let operation: DialogueBenchmarkOperation
    let plan: WorkspacePlan?
    let referent: String?
    let action: String?
    let isIsolated: Bool

    init(
        operation: DialogueBenchmarkOperation,
        plan: WorkspacePlan? = nil,
        referent: String? = nil,
        action: String? = nil,
        isIsolated: Bool = true
    ) {
        self.operation = operation
        self.plan = plan
        self.referent = referent
        self.action = action
        self.isIsolated = isIsolated
    }
}

public enum DialogueTrainingTextReader {
    public static func read(from repositoryRoot: URL) -> [String] {
        let paths = [
            "training/data/train.jsonl",
            "training/data/valid.jsonl",
            "training/data/test.jsonl",
            "training/hard-data/train.jsonl",
            "training/hard-data/valid.jsonl",
            "training/hard-data/test.jsonl",
            "training/panecue-mini/challenge-v2.jsonl"
        ]
        return paths.flatMap {
            readJSONL(at: repositoryRoot.appendingPathComponent($0))
        }
    }

    private static func readJSONL(at url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(
                      with: data
                  ) as? [String: Any] else {
                return nil
            }
            if let direct = root["text"] as? String {
                return direct
            }
            guard let messages = root["messages"] as? [[String: Any]],
                  let content = messages.first?["content"] as? String else {
                return nil
            }
            return content.components(
                separatedBy: "Request: "
            ).last ?? content
        }
    }
}
