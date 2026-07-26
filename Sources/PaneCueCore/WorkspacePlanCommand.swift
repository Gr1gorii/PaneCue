import Foundation

public enum WorkspacePlanCommandResult: Equatable, Sendable {
    case updated(WorkspacePlan, summary: String)
    case undo
    case save(name: String)
}

/// Deterministic, fully local follow-up language for Command Lab. The tiny
/// classifier decides whether a fresh utterance is a window command; this
/// interpreter only edits an already visible plan and therefore never launches
/// or moves an application by itself.
public enum WorkspacePlanCommandInterpreter {
    private enum Zone {
        case left
        case right
        case top
        case bottom
    }

    public static func initialPlan(
        from transcript: String
    ) -> WorkspacePlan? {
        guard !OfflineVoiceCommandParser.explicitlyDeclinesAction(
            from: transcript
        ) else {
            return nil
        }
        let text = normalize(transcript)
        guard hasActionVerb(text)
            || DynamicWorkspaceCommandParser.hasExplicitLayoutRequest(
                in: transcript
            )
        else {
            return nil
        }
        let targets = DynamicWorkspaceCommandParser.mentionedTargets(
            in: transcript
        )
        guard !targets.isEmpty else {
            return nil
        }

        if targets.count == 2,
           let intent = DynamicWorkspaceCommandParser.intent(
               from: transcript
           ),
           let plan = WorkspacePlan.from(intent: intent) {
            return plan
        }
        if targets.count == 3,
           let hints = DynamicWorkspaceCommandParser
               .threeWindowLayoutHints(in: transcript) {
            return threeWindowPlan(
                targets: targets,
                hints: hints
            )
        }
        return WorkspacePlan.tiled(targets: targets)
    }

    private static func threeWindowPlan(
        targets: [ScenarioWindowTarget],
        hints: DynamicWorkspaceCommandParser.ThreeWindowLayoutHints
    ) -> WorkspacePlan {
        let supportingIndex = targets.indices.first {
            $0 != hints.dominantIndex && $0 != hints.compactIndex
        } ?? 1
        let orderedTargets = [
            targets[hints.dominantIndex],
            targets[supportingIndex],
            targets[hints.compactIndex]
        ]
        // Keep the secondary column wide enough for the macOS Notes window.
        // A 75/25 split looks plausible in Preview but Notes constrains it on
        // real hardware, so a three-window layout caps the dominant column at
        // two thirds and expresses "small" through the vertical split.
        let dominantRatio = min(
            max(hints.dominantRatio, 0.6),
            2.0 / 3.0
        )
        let secondaryWidth = 1 - dominantRatio
        let compactHeight = 0.25
        let supportingHeight = 1 - compactHeight
        let dominantX = hints.dominantLeads ? 0.0 : secondaryWidth
        let secondaryX = hints.dominantLeads ? dominantRatio : 0.0
        let compactY = hints.compactPlacement == .top
            ? 0.0
            : supportingHeight
        let supportingY = hints.compactPlacement == .top
            ? compactHeight
            : 0.0
        let rects = [
            ScenarioGridRect(
                x: dominantX,
                y: 0,
                width: dominantRatio,
                height: 1
            ),
            ScenarioGridRect(
                x: secondaryX,
                y: supportingY,
                width: secondaryWidth,
                height: supportingHeight
            ),
            ScenarioGridRect(
                x: secondaryX,
                y: compactY,
                width: secondaryWidth,
                height: compactHeight
            )
        ]
        let slots = zip(orderedTargets, rects).map { target, rect in
            ScenarioWindowSlot(target: target, gridRect: rect)
        }
        return WorkspacePlan(
            windows: slots,
            selectedWindowID: slots.last?.id
        )
    }

    public static func interpret(
        _ transcript: String,
        currentPlan: WorkspacePlan
    ) -> WorkspacePlanCommandResult? {
        guard !OfflineVoiceCommandParser.explicitlyDeclinesAction(
            from: transcript
        ) else {
            return nil
        }
        let text = normalize(transcript)

        if containsAny(
            text,
            [
                "отмени последнее",
                "шаг назад",
                "верни предыдущее",
                "верни как было",
                "undo last",
                "undo change",
                "step back"
            ]
        ) {
            return .undo
        }

        if containsAny(
            text,
            ["сохрани это как", "сохрани как", "save this as", "save as"]
        ), let name = savedName(from: transcript) {
            return .save(name: name)
        }

        if containsAny(
            text,
            [
                "поменяй окна местами",
                "поменяй местами",
                "переставь окна",
                "swap windows",
                "switch windows"
            ]
        ) {
            guard currentPlan.windows.count >= 2 else {
                return nil
            }
            var plan = currentPlan
            let mentioned = matchingIndices(
                in: transcript,
                plan: currentPlan
            )
            let first = mentioned.first ?? 0
            let second = mentioned.dropFirst().first
                ?? (first == 0 ? 1 : 0)
            let target = plan.windows[first].target
            plan.windows[first].target = plan.windows[second].target
            plan.windows[second].target = target
            plan.selectedWindowID = plan.windows[second].id
            plan.revision += 1
            return .updated(plan, summary: "Swapped two windows")
        }

        let mentionedTargets =
            DynamicWorkspaceCommandParser.mentionedTargets(
                in: transcript
            )
        let existingTargetKeys = Set(
            currentPlan.windows.map { key(for: $0.target) }
        )
        let newTargets = mentionedTargets.filter {
            !existingTargetKeys.contains(key(for: $0))
        }
        let asksToAdd = containsAny(
            text,
            [
                "добавь",
                "добавить",
                "еще окно",
                "ещё окно",
                "add ",
                "include "
            ]
        )

        if (asksToAdd || !newTargets.isEmpty),
           let target = newTargets.first,
           currentPlan.windows.count < 8 {
            var plan = currentPlan
            let slot = ScenarioWindowSlot(
                target: target,
                gridRect: ScenarioGridRect(
                    x: 0.65,
                    y: 0,
                    width: 0.35,
                    height: 1
                )
            )
            plan.windows.append(slot)
            if let zone = zone(in: text) {
                placeWindow(
                    at: plan.windows.count - 1,
                    in: zone,
                    plan: &plan
                )
            } else {
                retile(&plan)
            }
            plan.selectedWindowID = slot.id
            plan.revision += 1
            return .updated(
                plan,
                summary: "Added \(target.displayName)"
            )
        }

        if containsAny(
            text,
            [
                "убери",
                "удали",
                "закрой из плана",
                "remove ",
                "delete ",
                "drop "
            ]
        ) {
            guard currentPlan.windows.count > 1,
                  let index = targetIndex(
                      in: transcript,
                      plan: currentPlan
                  ) else {
                return nil
            }
            var plan = currentPlan
            let name = plan.windows[index].target.displayName
            plan.windows.remove(at: index)
            retile(&plan)
            plan.selectedWindowID = plan.windows.last?.id
            plan.revision += 1
            return .updated(plan, summary: "Removed \(name)")
        }

        let asksSmaller = containsAny(
            text,
            [
                "меньше",
                "поменьше",
                "уменьш",
                "уже",
                "smaller",
                "shrink",
                "narrower"
            ]
        )
        let asksLarger = containsAny(
            text,
            [
                "больше",
                "побольше",
                "увелич",
                "шире",
                "larger",
                "bigger",
                "grow",
                "wider"
            ]
        )
        if asksSmaller || asksLarger,
           let index = targetIndex(
               in: transcript,
               plan: currentPlan
           ) {
            var plan = currentPlan
            let delta = sizeStep(in: text) * (asksSmaller ? -1 : 1)
            resizeWindow(
                at: index,
                by: delta,
                plan: &plan
            )
            plan.selectedWindowID = plan.windows[index].id
            plan.revision += 1
            return .updated(
                plan,
                summary: "\(plan.windows[index].target.displayName) is \(asksSmaller ? "smaller" : "larger")"
            )
        }

        if containsAny(
            text,
            [
                "слева",
                "справа",
                "сверху",
                "снизу",
                "left",
                "right",
                "top",
                "bottom"
            ]
        ), let destination = zone(in: text),
           let index = targetIndex(
               in: transcript,
               plan: currentPlan
           ) {
            var plan = currentPlan
            let id = plan.windows[index].id
            let name = plan.windows[index].target.displayName
            placeWindow(at: index, in: destination, plan: &plan)
            plan.selectedWindowID = id
            plan.revision += 1
            return .updated(plan, summary: "Moved \(name)")
        }

        return nil
    }

    private static func resizeWindow(
        at index: Int,
        by delta: Double,
        plan: inout WorkspacePlan
    ) {
        guard plan.windows.indices.contains(index) else {
            return
        }
        if plan.windows.count == 2 {
            let other = index == 0 ? 1 : 0
            let selectedRect = plan.windows[index].gridRect
            let otherRect = plan.windows[other].gridRect
            let isHorizontal =
                abs(selectedRect.height - 1) < 0.01
                    && abs(otherRect.height - 1) < 0.01
            if isHorizontal {
                let width = min(
                    max(
                        selectedRect.width + delta,
                        ScenarioGridResolution.minimumWidth
                    ),
                    1 - ScenarioGridResolution.minimumWidth
                )
                let selectedLeads = selectedRect.x < otherRect.x
                plan.windows[index].gridRect = ScenarioGridRect(
                    x: selectedLeads ? 0 : 1 - width,
                    y: 0,
                    width: width,
                    height: 1
                )
                plan.windows[other].gridRect = ScenarioGridRect(
                    x: selectedLeads ? width : 0,
                    y: 0,
                    width: 1 - width,
                    height: 1
                )
                return
            }

            let height = min(
                max(
                    selectedRect.height + delta,
                    ScenarioGridResolution.minimumHeight
                ),
                1 - ScenarioGridResolution.minimumHeight
            )
            let selectedLeads = selectedRect.y < otherRect.y
            plan.windows[index].gridRect = ScenarioGridRect(
                x: 0,
                y: selectedLeads ? 0 : 1 - height,
                width: 1,
                height: height
            )
            plan.windows[other].gridRect = ScenarioGridRect(
                x: 0,
                y: selectedLeads ? height : 0,
                width: 1,
                height: 1 - height
            )
            return
        }

        let rect = plan.windows[index].gridRect
        let scale = delta > 0 ? 1.15 : 0.85
        let width = min(max(
            rect.width * scale,
            ScenarioGridResolution.minimumWidth
        ), 1)
        let height = min(max(
            rect.height * scale,
            ScenarioGridResolution.minimumHeight
        ), 1)
        plan.windows[index].gridRect = ScenarioGridRect(
            x: rect.x + (rect.width - width) / 2,
            y: rect.y + (rect.height - height) / 2,
            width: width,
            height: height
        )
    }

    private static func placeWindow(
        at index: Int,
        in zone: Zone,
        plan: inout WorkspacePlan
    ) {
        guard plan.windows.indices.contains(index) else {
            return
        }
        let selected = plan.windows.remove(at: index)
        let baseRects = WorkspacePlan.balancedRects(
            count: plan.windows.count
        )
        for slotIndex in plan.windows.indices {
            plan.windows[slotIndex].gridRect = baseRects[slotIndex]
        }

        let secondaryShare = 0.35
        for slotIndex in plan.windows.indices {
            var rect = plan.windows[slotIndex].gridRect
            switch zone {
            case .left:
                rect.x = secondaryShare + rect.x * (1 - secondaryShare)
                rect.width *= 1 - secondaryShare
            case .right:
                rect.x *= 1 - secondaryShare
                rect.width *= 1 - secondaryShare
            case .top:
                rect.y = secondaryShare + rect.y * (1 - secondaryShare)
                rect.height *= 1 - secondaryShare
            case .bottom:
                rect.y *= 1 - secondaryShare
                rect.height *= 1 - secondaryShare
            }
            plan.windows[slotIndex].gridRect = rect
        }

        var positioned = selected
        switch zone {
        case .left:
            positioned.gridRect = ScenarioGridRect(
                x: 0,
                y: 0,
                width: secondaryShare,
                height: 1
            )
        case .right:
            positioned.gridRect = ScenarioGridRect(
                x: 1 - secondaryShare,
                y: 0,
                width: secondaryShare,
                height: 1
            )
        case .top:
            positioned.gridRect = ScenarioGridRect(
                x: 0,
                y: 0,
                width: 1,
                height: secondaryShare
            )
        case .bottom:
            positioned.gridRect = ScenarioGridRect(
                x: 0,
                y: 1 - secondaryShare,
                width: 1,
                height: secondaryShare
            )
        }
        plan.windows.append(positioned)
    }

    private static func retile(_ plan: inout WorkspacePlan) {
        let rects = WorkspacePlan.balancedRects(
            count: plan.windows.count
        )
        for index in plan.windows.indices {
            plan.windows[index].gridRect = rects[index]
        }
    }

    private static func targetIndex(
        in transcript: String,
        plan: WorkspacePlan
    ) -> Int? {
        matchingIndices(in: transcript, plan: plan).first
            ?? plan.selectedWindowIndex
            ?? plan.windows.indices.last
    }

    private static func matchingIndices(
        in transcript: String,
        plan: WorkspacePlan
    ) -> [Int] {
        let targets = DynamicWorkspaceCommandParser.mentionedTargets(
            in: transcript
        )
        var indices: [Int] = []
        for target in targets {
            if let index = plan.windows.firstIndex(where: {
                key(for: $0.target) == key(for: target)
            }), !indices.contains(index) {
                indices.append(index)
            }
        }
        return indices
    }

    private static func zone(in text: String) -> Zone? {
        if containsAny(text, ["слева", "налево", "left"]) {
            return .left
        }
        if containsAny(text, ["справа", "направо", "right"]) {
            return .right
        }
        if containsAny(text, ["сверху", "наверх", "top", "above"]) {
            return .top
        }
        if containsAny(text, ["снизу", "вниз", "bottom", "below"]) {
            return .bottom
        }
        return nil
    }

    private static func sizeStep(in text: String) -> Double {
        containsAny(
            text,
            ["намного", "сильно", "much", "a lot"]
        ) ? 0.15 : (
            containsAny(text, ["чуть", "немного", "slightly"])
                ? 0.05
                : 0.1
        )
    }

    private static func savedName(
        from transcript: String
    ) -> String? {
        let pattern =
            #"(?:сохрани\s+(?:это\s+)?как|save\s+(?:this\s+)?as)\s+(.+)$"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(
            transcript.startIndex..<transcript.endIndex,
            in: transcript
        )
        guard let match = expression.firstMatch(
            in: transcript,
            range: range
        ),
        let captureRange = Range(match.range(at: 1), in: transcript)
        else {
            return nil
        }
        let name = transcript[captureRange]
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "\"'«».,!?")
                )
            )
        return name.isEmpty ? nil : name
    }

    private static func key(
        for target: ScenarioWindowTarget
    ) -> String {
        switch target.kind {
        case .application:
            return "app:\(target.application?.bundleIdentifier ?? "")"
        case .role:
            return "role:\(target.role?.rawValue ?? "")"
        }
    }

    private static func hasActionVerb(_ text: String) -> Bool {
        containsAny(
            text,
            [
                "открой",
                "постав",
                "располож",
                "размест",
                "покажи",
                "сделай",
                "вывед",
                "остав",
                "хочу",
                "open",
                "put",
                "arrange",
                "place",
                "show",
                "make",
                "keep"
            ]
        )
    }

    private static func containsAny(
        _ text: String,
        _ phrases: [String]
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
