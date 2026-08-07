import AppKit
import ApplicationServices
import OSLog

@MainActor
public final class WindowManager {
    private struct ResolvedWindowSelection {
        let slot: ScenarioWindowSlot
        let window: ManagedWindow
        let targetFrame: CGRect
    }

    private let logger = Logger(
        subsystem: PaneCueIdentity.bundleIdentifier,
        category: "WindowManager"
    )

    private var activeSnapshot: [WindowSnapshot]?
    private var activeScenarioName: String?
    private let transactionLifecycle: ApplyTransactionLifecycle

    public init(applyJournal: ApplyJournalStore = ApplyJournalStore()) {
        transactionLifecycle = ApplyTransactionLifecycle(
            journal: applyJournal
        )
    }

    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public var canRestore: Bool {
        activeSnapshot != nil
    }

    public var currentScenarioName: String? {
        activeScenarioName
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        // The imported global constant is mutable in the legacy C header and
        // therefore rejected by Swift 6 strict concurrency checking.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func eligibleWindows() throws -> [ManagedWindow] {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let runningApplications = NSWorkspace.shared.runningApplications.filter { application in
            !application.isTerminated
                && application.processIdentifier != ownPID
                && application.activationPolicy == .regular
        }

        return runningApplications.flatMap { application in
            windows(for: application)
        }
    }

    public func applyCodeAndCallLayout() throws -> String {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        restoreActiveLayoutBeforeApplying()

        guard let visibleFrame = ScreenGeometry.primaryVisibleFrameInAccessibilityCoordinates() else {
            throw PaneCueWindowError.noUsableScreen
        }

        let windows = try eligibleWindows()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let ideWindows = windows.filter {
            role(of: $0) == .ide
        }
        guard let ide = preferredWindow(
            among: ideWindows,
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "code editor",
                examples: "Xcode, VS Code, Cursor, or a JetBrains IDE"
            )
        }

        let meetingWindows = windows.filter {
            $0.processIdentifier != ide.processIdentifier
                && role(of: $0) == .meeting
        }
        guard let meeting = preferredMeetingWindow(
            among: meetingWindows,
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "call",
                examples: "Zoom, Teams, FaceTime, Webex, or a supported browser meeting"
            )
        }

        let snapshot = [ide].map { window in
            WindowSnapshot(
                element: window.element,
                applicationName: window.applicationName,
                title: window.title,
                frame: window.frame,
                isMinimized: window.isMinimized,
                isFullScreen: window.isFullScreen
            )
        }

        do {
            AXHelpers.setMinimized(false, on: ide.element)
            if !ide.isFullScreen {
                try leaveFullScreenIfNeeded(ide)
                try AXHelpers.setFrame(visibleFrame, on: ide.element)
            }
            AXHelpers.raise(ide.element)

            activeSnapshot = snapshot
            activeScenarioName = "Code + Call"

            logger.info("Applied the Code + Call layout")

            return "Code + Call · \(ide.applicationName) + \(meeting.applicationName)"
        } catch {
            restore(snapshot, clearingOnCompletion: false)
            throw error
        }
    }

    public func applyDocumentationAndCodeLayout() throws -> String {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        restoreActiveLayoutBeforeApplying()

        guard let visibleFrame = ScreenGeometry.primaryVisibleFrameInAccessibilityCoordinates() else {
            throw PaneCueWindowError.noUsableScreen
        }

        let windows = try eligibleWindows()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        guard let ide = preferredWindow(
            among: windows.filter { role(of: $0) == .ide },
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "code editor",
                examples: "Xcode, VS Code, Cursor, or a JetBrains IDE"
            )
        }

        let documentationWindows = windows.filter { window in
            guard window.processIdentifier != ide.processIdentifier else {
                return false
            }
            let windowRole = role(of: window)
            return windowRole == .browser || windowRole == .documentation
        }

        guard let documentation = preferredWindow(
            among: documentationWindows,
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "documentation",
                examples: "Safari, Chrome, Firefox, Preview, or Dash"
            )
        }

        return try applyPairLayout(
            primary: ide,
            secondary: documentation,
            visibleFrame: visibleFrame,
            scenarioName: "Documentation + Code",
            summary: "Documentation + Code · \(ide.applicationName) 65% + \(documentation.applicationName) 35%"
        )
    }

    public func applyNotesAndBrowserLayout() throws -> String {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        restoreActiveLayoutBeforeApplying()

        guard let visibleFrame = ScreenGeometry.primaryVisibleFrameInAccessibilityCoordinates() else {
            throw PaneCueWindowError.noUsableScreen
        }

        let windows = try eligibleWindows()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        guard let browser = preferredWindow(
            among: windows.filter { role(of: $0) == .browser },
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "browser",
                examples: "Safari, Chrome, Firefox, Edge, or Brave"
            )
        }

        guard let notes = preferredWindow(
            among: windows.filter {
                $0.processIdentifier != browser.processIdentifier
                    && role(of: $0) == .notes
            },
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "notes",
                examples: "Apple Notes, Notion, Obsidian, Bear, or Craft"
            )
        }

        return try applyPairLayout(
            primary: browser,
            secondary: notes,
            visibleFrame: visibleFrame,
            scenarioName: "Notes + Browser",
            summary: "Notes + Browser · \(browser.applicationName) 65% + \(notes.applicationName) 35%"
        )
    }

    public func applyCustomLayout(
        _ scenario: CustomScenario
    ) throws -> String {
        try applyCustomLayoutDetailed(scenario).summary
    }

    /// Resolves the current local AX inventory for an Arrange Preview.
    /// Window titles are passed only as in-memory chooser differentiators and
    /// are never logged or persisted by PaneCue Core.
    public func previewResolution(
        for plan: WorkspacePlan,
        requestSource: ArrangementRequestSource = .arrange
    ) throws -> ArrangementTargetResolutionSet {
        let windows = try eligibleWindows()
        let inventoryPairs = workspaceInventory(from: windows)
        let differentiators = inventoryPairs.reduce(
            into: [EphemeralWindowIdentifier: String]()
        ) { result, pair in
            let value = pair.window.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !value.isEmpty {
                result[
                    EphemeralWindowIdentifier(rawValue: pair.item.id)
                ] = value
            }
        }
        return WorkspaceTargetResolver.resolve(
            scenario: CustomScenario(
                name: plan.name,
                windows: plan.windows
            ),
            inventory: inventoryPairs.map(\.item),
            hasExternalDisplay: ScreenGeometry.hasExternalDisplay,
            hasActiveCall: windows.contains {
                role(of: $0) == .meeting
            },
            requestSource: requestSource,
            localDifferentiators: differentiators
        )
    }

    public func applyCustomLayoutDetailed(
        _ scenario: CustomScenario,
        resolution: ArrangementTargetResolutionSet? = nil
    ) throws -> WorkspaceApplyResult {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        guard scenario.windows.count >= 2 else {
            throw PaneCueWindowError.notEnoughEligibleWindows(
                found: scenario.windows.count
            )
        }

        let windows = try eligibleWindows()

        guard let mainFrame = ScreenGeometry
            .visibleFrameInAccessibilityCoordinates(for: .main) else {
            throw PaneCueWindowError.noUsableScreen
        }
        let externalFrame = ScreenGeometry
            .visibleFrameInAccessibilityCoordinates(for: .external)

        var resolved: [ResolvedWindowSelection] = []
        var outcomesBySlot: [UUID: WorkspaceApplyOutcome] = [:]
        let inventoryPairs = workspaceInventory(from: windows)
        let windowsByCandidateID = Dictionary(
            uniqueKeysWithValues: inventoryPairs.map {
                ($0.item.id, $0.window)
            }
        )
        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: inventoryPairs.map(\.item),
            hasExternalDisplay: ScreenGeometry.hasExternalDisplay,
            hasActiveCall: windows.contains {
                role(of: $0) == .meeting
            },
            selectedCandidateIDsBySlot:
                resolution?.selectedCandidateIDsBySlot ?? [:]
        )

        // Resolve from a fresh AX inventory at Apply time. The preview names
        // targets, while this pass verifies that each target still maps to one
        // unambiguous, movable window before any mutation begins.
        for decision in decisions {
            guard let slot = scenario.windows.first(where: {
                $0.id == decision.id
            }) else {
                continue
            }

            switch decision.status {
            case let .ready(candidateID):
                guard let window = windowsByCandidateID[candidateID] else {
                    outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                        id: slot.id,
                        targetName: slot.target.displayName,
                        status: .failed,
                        reason: "The selected window is no longer available."
                    )
                    continue
                }
                let screenFrame = slot.display == .external
                    ? (externalFrame ?? mainFrame)
                    : mainFrame
                let targetFrame = LayoutPlanner.frame(
                    for: slot.gridRect,
                    in: screenFrame
                )

                if framesApproximatelyEqual(window.frame, targetFrame) {
                    outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                        id: slot.id,
                        targetName: slot.target.displayName,
                        applicationName: window.applicationName,
                        status: .unchanged,
                        reason: "Already in the previewed position.",
                        matchesPreview: true
                    )
                } else {
                    resolved.append(
                        ResolvedWindowSelection(
                            slot: slot,
                            window: window,
                            targetFrame: targetFrame
                        )
                    )
                }

            case .missing:
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    status: .skipped,
                    reason: "The matching window was closed or is no longer available."
                )

            case let .ambiguous(candidateCount):
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    status: .skipped,
                    reason: "\(candidateCount) matching windows are open. Narrow the Cue and preview it again."
                )

            case let .fullScreen(candidateID):
                outcomesBySlot[slot.id] = blockedWindowOutcome(
                    slot: slot,
                    window: windowsByCandidateID[candidateID],
                    status: .skipped,
                    reason: "The window entered full screen after the preview. Exit full screen and apply again."
                )

            case let .minimized(candidateID):
                outcomesBySlot[slot.id] = blockedWindowOutcome(
                    slot: slot,
                    window: windowsByCandidateID[candidateID],
                    status: .skipped,
                    reason: "The window is minimized. Restore it and apply again."
                )

            case let .unchangeable(candidateID):
                outcomesBySlot[slot.id] = blockedWindowOutcome(
                    slot: slot,
                    window: windowsByCandidateID[candidateID],
                    status: .unchanged,
                    reason: "This window does not allow its size or position to be changed."
                )

            case .externalDisplayUnavailable:
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    status: .skipped,
                    reason: "The external display is no longer connected."
                )

            case .conditionNotMet:
                let reason = scenario.conditions.requiresExternalDisplay
                    && !ScreenGeometry.hasExternalDisplay
                    ? "The required external display is not connected."
                    : "No active call window was found."
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    status: .skipped,
                    reason: reason
                )
            }
        }

        var prepared: [(
            selection: ResolvedWindowSelection,
            snapshot: WindowSnapshot
        )] = []
        var movedSelections: [ResolvedWindowSelection] = []

        for selection in resolved {
            let slot = selection.slot
            let window = selection.window

            guard let currentFrame = AXHelpers.frame(of: window.element) else {
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    applicationName: window.applicationName,
                    status: .failed,
                    reason: "The window closed after the preview."
                )
                continue
            }

            let isFullScreen = AXHelpers.copyBool(
                from: window.element,
                attribute: AXHelpers.fullScreenAttribute
            ) ?? false
            guard !isFullScreen else {
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    applicationName: window.applicationName,
                    status: .skipped,
                    reason: "The window entered full screen after the preview. Exit full screen and apply again."
                )
                continue
            }

            let isMinimized = AXHelpers.copyBool(
                from: window.element,
                attribute: kAXMinimizedAttribute as CFString
            ) ?? false
            guard !isMinimized else {
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    applicationName: window.applicationName,
                    status: .skipped,
                    reason: "The window was minimized after the preview. Restore it and apply again."
                )
                continue
            }

            guard AXHelpers.canSetFrame(on: window.element) else {
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    applicationName: window.applicationName,
                    status: .unchanged,
                    reason: "This window no longer allows its size or position to be changed."
                )
                continue
            }

            if framesApproximatelyEqual(currentFrame, selection.targetFrame) {
                outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                    id: slot.id,
                    targetName: slot.target.displayName,
                    applicationName: window.applicationName,
                    status: .unchanged,
                    reason: "Already in the previewed position.",
                    matchesPreview: true
                )
                continue
            }

            prepared.append(
                (
                    selection: selection,
                    snapshot: WindowSnapshot(
                        element: window.element,
                        applicationName: window.applicationName,
                        title: window.title,
                        frame: currentFrame,
                        isMinimized: isMinimized,
                        isFullScreen: isFullScreen
                    )
                )
            )
        }

        // Snapshot every changeable target before the first window moves.
        // A failed write can still partially resize a window, so every actual
        // write attempt enables Rollback even when verification later fails.
        guard !prepared.isEmpty else {
            let result = workspaceApplyResult(
                scenario: scenario,
                outcomesBySlot: outcomesBySlot,
                canRollback: false
            )
            logger.info("Completed a workspace Apply transaction")
            return result
        }

        let execution = try transactionLifecycle.execute(
            windows: prepared.map { preparedSelection in
                applyJournalRecord(
                    window: preparedSelection.selection.window,
                    snapshot: preparedSelection.snapshot
                )
            }
        ) {
            var didAttemptMutation = false
            for preparedSelection in prepared {
                let selection = preparedSelection.selection
                let slot = selection.slot
                let window = selection.window

                guard AXHelpers.frame(of: window.element) != nil else {
                    outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                        id: slot.id,
                        targetName: slot.target.displayName,
                        applicationName: window.applicationName,
                        status: .failed,
                        reason: "The window closed while the layout was being applied."
                    )
                    continue
                }

                let isFullScreen = AXHelpers.copyBool(
                    from: window.element,
                    attribute: AXHelpers.fullScreenAttribute
                ) ?? false
                let isMinimized = AXHelpers.copyBool(
                    from: window.element,
                    attribute: kAXMinimizedAttribute as CFString
                ) ?? false
                guard !isFullScreen, !isMinimized,
                      AXHelpers.canSetFrame(on: window.element) else {
                    outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                        id: slot.id,
                        targetName: slot.target.displayName,
                        applicationName: window.applicationName,
                        status: .skipped,
                        reason: "The window changed state while the layout was being applied. Preview it again."
                    )
                    continue
                }

                didAttemptMutation = true
                do {
                    try AXHelpers.setFrame(
                        selection.targetFrame,
                        on: window.element
                    )
                    var appliedFrame = AXHelpers.frame(of: window.element)
                    if appliedFrame.map({
                        !framesApproximatelyEqual(
                            $0,
                            selection.targetFrame,
                            tolerance: 8
                        )
                    }) ?? true {
                        // Notes and some AppKit windows settle their new size
                        // before accepting the final requested edge.
                        Thread.sleep(forTimeInterval: 0.12)
                        try AXHelpers.setFrame(
                            selection.targetFrame,
                            on: window.element
                        )
                        appliedFrame = AXHelpers.frame(of: window.element)
                    }
                    guard let appliedFrame,
                          framesApproximatelyEqual(
                              appliedFrame,
                              selection.targetFrame,
                              tolerance: 8
                          ) else {
                        outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                            id: slot.id,
                            targetName: slot.target.displayName,
                            applicationName: window.applicationName,
                            status: .failed,
                            reason: "The application constrained the requested size or position."
                        )
                        continue
                    }
                    movedSelections.append(selection)
                    outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                        id: slot.id,
                        targetName: slot.target.displayName,
                        applicationName: window.applicationName,
                        status: .moved
                    )
                } catch {
                    outcomesBySlot[slot.id] = WorkspaceApplyOutcome(
                        id: slot.id,
                        targetName: slot.target.displayName,
                        applicationName: window.applicationName,
                        status: .failed,
                        reason: error.localizedDescription
                    )
                }
            }

            for selection in movedSelections.reversed() {
                AXHelpers.raise(selection.window.element)
            }

            if didAttemptMutation {
                activeSnapshot = prepared.map(\.snapshot)
                activeScenarioName = movedSelections.isEmpty
                    ? nil
                    : scenario.name
            }

            let result = workspaceApplyResult(
                scenario: scenario,
                outcomesBySlot: outcomesBySlot,
                canRollback: didAttemptMutation
            )
            return ApplyTransactionCompletion(
                value: result,
                resultState: applyJournalResultState(for: result),
                windowResults: applyJournalWindowResults(
                    prepared: prepared,
                    outcomesBySlot: outcomesBySlot
                )
            )
        }
        if !execution.didPersistCompletion {
            logger.error("Could not complete the local Apply journal record")
        }
        logger.info("Completed a workspace Apply transaction")
        return execution.value
    }

    public func restorePreviousLayout() throws -> String {
        guard let snapshot = activeSnapshot else {
            throw PaneCueWindowError.noSnapshot
        }

        let failures = restore(snapshot, clearingOnCompletion: true)
        activeScenarioName = nil
        if failures.isEmpty {
            return "Previous layout restored"
        }

        return "Previous layout partially restored · \(failures.count) window\(failures.count == 1 ? "" : "s") unavailable"
    }

    private func windows(for application: NSRunningApplication) -> [ManagedWindow] {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let elements = AXHelpers.copyElements(
            from: applicationElement,
            attribute: kAXWindowsAttribute as CFString
        )

        return elements.compactMap { windowElement in
            guard let frame = AXHelpers.frame(of: windowElement) else {
                return nil
            }

            guard frame.width >= 200, frame.height >= 140 else {
                return nil
            }

            let role = AXHelpers.copyString(
                from: windowElement,
                attribute: kAXRoleAttribute as CFString
            )
            guard role == (kAXWindowRole as String) else {
                return nil
            }

            let title = AXHelpers.copyString(
                from: windowElement,
                attribute: kAXTitleAttribute as CFString
            ) ?? "Untitled Window"

            let minimized = AXHelpers.copyBool(
                from: windowElement,
                attribute: kAXMinimizedAttribute as CFString
            ) ?? false

            let fullScreen = AXHelpers.copyBool(
                from: windowElement,
                attribute: AXHelpers.fullScreenAttribute
            ) ?? false

            return ManagedWindow(
                element: windowElement,
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.localizedName ?? application.bundleIdentifier ?? "Application",
                title: title,
                frame: frame,
                isMinimized: minimized,
                isFullScreen: fullScreen
            )
        }
    }

    private func role(of window: ManagedWindow) -> ApplicationRole {
        ApplicationRoleClassifier.role(
            bundleIdentifier: window.bundleIdentifier,
            applicationName: window.applicationName,
            windowTitle: window.title
        )
    }

    private func workspaceInventory(
        from windows: [ManagedWindow]
    ) -> [(item: WorkspaceWindowInventoryItem, window: ManagedWindow)] {
        windows.map { window in
            (
                item: WorkspaceWindowInventoryItem(
                    id: ephemeralIdentifier(for: window),
                    bundleIdentifier: window.bundleIdentifier,
                    applicationName: window.applicationName,
                    role: role(of: window),
                    display: displayTarget(for: window.frame),
                    isMinimized: window.isMinimized,
                    isFullScreen: window.isFullScreen,
                    canSetFrame: AXHelpers.canSetFrame(on: window.element)
                ),
                window: window
            )
        }
    }

    private func ephemeralIdentifier(for window: ManagedWindow) -> String {
        "window-\(window.processIdentifier)-\(CFHash(window.element))"
    }

    private func applyJournalRecord(
        window: ManagedWindow,
        snapshot: WindowSnapshot
    ) -> ApplyJournalWindowRecord {
        ApplyJournalWindowRecord(
            applicationBundleIdentifier: window.bundleIdentifier,
            processIdentifier: Int32(window.processIdentifier),
            windowIdentifier: ephemeralIdentifier(for: window),
            originalFrame: ApplyJournalFrame(
                x: snapshot.frame.origin.x,
                y: snapshot.frame.origin.y,
                width: snapshot.frame.size.width,
                height: snapshot.frame.size.height
            ),
            originalDisplaySignature: ScreenGeometry.displaySignature(
                containing: snapshot.frame
            ),
            wasVisible: !snapshot.isMinimized,
            wasMinimized: snapshot.isMinimized
        )
    }

    private func workspaceApplyResult(
        scenario: CustomScenario,
        outcomesBySlot: [UUID: WorkspaceApplyOutcome],
        canRollback: Bool
    ) -> WorkspaceApplyResult {
        WorkspaceApplyResult(
            scenarioName: scenario.name,
            outcomes: scenario.windows.compactMap {
                outcomesBySlot[$0.id]
            },
            canRollback: canRollback
        )
    }

    private func applyJournalResultState(
        for result: WorkspaceApplyResult
    ) -> ApplyJournalResultState {
        if result.failedCount > 0 {
            return result.didChangeAnyWindow ? .partial : .failed
        }
        if result.isPartial || result.skippedCount > 0 {
            return result.didChangeAnyWindow ? .partial : .noChange
        }
        return result.didChangeAnyWindow ? .succeeded : .noChange
    }

    private func applyJournalWindowResults(
        prepared: [(
            selection: ResolvedWindowSelection,
            snapshot: WindowSnapshot
        )],
        outcomesBySlot: [UUID: WorkspaceApplyOutcome]
    ) -> [String: ApplyJournalWindowResultState] {
        prepared.reduce(into: [:]) { results, preparedSelection in
            let outcome = outcomesBySlot[
                preparedSelection.selection.slot.id
            ]
            results[
                ephemeralIdentifier(
                    for: preparedSelection.selection.window
                )
            ] = applyJournalWindowResultState(
                for: outcome?.status ?? .failed
            )
        }
    }

    private func applyJournalWindowResultState(
        for status: WorkspaceApplyOutcomeStatus
    ) -> ApplyJournalWindowResultState {
        switch status {
        case .moved:
            return .moved
        case .unchanged:
            return .unchanged
        case .skipped:
            return .skipped
        case .failed:
            return .failed
        }
    }

    private func displayTarget(for frame: CGRect) -> ScenarioDisplayTarget {
        guard let external = ScreenGeometry
            .visibleFrameInAccessibilityCoordinates(for: .external),
              let main = ScreenGeometry
                .visibleFrameInAccessibilityCoordinates(for: .main) else {
            return .main
        }
        return ScreenGeometry.overlapArea(frame, external)
            > ScreenGeometry.overlapArea(frame, main)
            ? .external
            : .main
    }

    private func blockedWindowOutcome(
        slot: ScenarioWindowSlot,
        window: ManagedWindow?,
        status: WorkspaceApplyOutcomeStatus,
        reason: String
    ) -> WorkspaceApplyOutcome {
        WorkspaceApplyOutcome(
            id: slot.id,
            targetName: slot.target.displayName,
            applicationName: window?.applicationName,
            status: status,
            reason: reason
        )
    }

    private func framesApproximatelyEqual(
        _ first: CGRect,
        _ second: CGRect,
        tolerance: CGFloat = 3
    ) -> Bool {
        abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance
            && abs(first.height - second.height) <= tolerance
    }

    private func preferredWindow(
        among windows: [ManagedWindow],
        frontmostPID: pid_t?
    ) -> ManagedWindow? {
        windows.max { left, right in
            windowPriority(left, frontmostPID: frontmostPID)
                < windowPriority(right, frontmostPID: frontmostPID)
        }
    }

    private func preferredMeetingWindow(
        among windows: [ManagedWindow],
        frontmostPID: pid_t?
    ) -> ManagedWindow? {
        windows.max { left, right in
            meetingWindowPriority(left, frontmostPID: frontmostPID)
                < meetingWindowPriority(right, frontmostPID: frontmostPID)
        }
    }

    private func windowPriority(
        _ window: ManagedWindow,
        frontmostPID: pid_t?
    ) -> Double {
        let frontmostBonus = window.processIdentifier == frontmostPID ? 1_000_000_000.0 : 0
        let visibleBonus = window.isMinimized ? 0 : 100_000_000.0
        return frontmostBonus + visibleBonus + Double(window.area)
    }

    private func meetingWindowPriority(
        _ window: ManagedWindow,
        frontmostPID: pid_t?
    ) -> Double {
        let title = window.title.lowercased()
        let meetingTitleMarkers = [
            "meeting",
            "meet",
            "call",
            "facetime",
            "zoom"
        ]
        let titleBonus = meetingTitleMarkers.contains(where: title.contains)
            ? 10_000_000_000.0
            : 0
        return titleBonus + windowPriority(window, frontmostPID: frontmostPID)
    }

    private func applyPairLayout(
        primary: ManagedWindow,
        secondary: ManagedWindow,
        visibleFrame: CGRect,
        primaryRatio: CGFloat = 0.65,
        scenarioName: String,
        summary: String
    ) throws -> String {
        let snapshot = [primary, secondary].map { window in
            WindowSnapshot(
                element: window.element,
                applicationName: window.applicationName,
                title: window.title,
                frame: window.frame,
                isMinimized: window.isMinimized,
                isFullScreen: window.isFullScreen
            )
        }
        let layout = LayoutPlanner.sideBySide(
            in: visibleFrame,
            primaryRatio: primaryRatio
        )

        do {
            AXHelpers.setMinimized(false, on: primary.element)
            AXHelpers.setMinimized(false, on: secondary.element)
            try leaveFullScreenIfNeeded(primary)
            try leaveFullScreenIfNeeded(secondary)
            try AXHelpers.setFrame(layout.primary, on: primary.element)
            try AXHelpers.setFrame(layout.secondary, on: secondary.element)
            AXHelpers.raise(secondary.element)
            AXHelpers.raise(primary.element)

            activeSnapshot = snapshot
            activeScenarioName = scenarioName
            logger.info("Applied a two-window layout")
            return summary
        } catch {
            restore(snapshot, clearingOnCompletion: false)
            throw error
        }
    }

    private func restoreActiveLayoutBeforeApplying() {
        guard let snapshot = activeSnapshot else {
            return
        }

        let failures = restore(snapshot, clearingOnCompletion: true)
        activeScenarioName = nil

        if !failures.isEmpty {
            logger.warning("Discarded a stale layout snapshot")
        }
    }

    private func leaveFullScreenIfNeeded(_ window: ManagedWindow) throws {
        guard window.isFullScreen else {
            return
        }

        try AXHelpers.setFullScreen(false, on: window.element)
        try waitForFullScreenState(
            false,
            on: window.element,
            applicationName: window.applicationName
        )
    }

    private func waitForFullScreenState(
        _ expectedState: Bool,
        on element: AXUIElement,
        applicationName: String
    ) throws {
        let deadline = Date(timeIntervalSinceNow: 2)

        while Date() < deadline {
            let currentState = AXHelpers.copyBool(
                from: element,
                attribute: AXHelpers.fullScreenAttribute
            ) ?? false
            if currentState == expectedState {
                return
            }

            RunLoop.current.run(
                until: Date(timeIntervalSinceNow: 0.05)
            )
        }

        throw PaneCueWindowError.operationFailed(
            details: "\(applicationName) did not finish changing fullscreen mode."
        )
    }

    @discardableResult
    private func restore(
        _ snapshot: [WindowSnapshot],
        clearingOnCompletion: Bool
    ) -> [Error] {
        var failures: [Error] = []

        for window in snapshot {
            do {
                AXHelpers.setMinimized(false, on: window.element)

                let currentlyFullScreen = AXHelpers.copyBool(
                    from: window.element,
                    attribute: AXHelpers.fullScreenAttribute
                ) ?? false

                if window.isFullScreen {
                    if !currentlyFullScreen {
                        try AXHelpers.setFullScreen(true, on: window.element)
                        try waitForFullScreenState(
                            true,
                            on: window.element,
                            applicationName: window.applicationName
                        )
                    }
                } else {
                    if currentlyFullScreen {
                        try AXHelpers.setFullScreen(false, on: window.element)
                        try waitForFullScreenState(
                            false,
                            on: window.element,
                            applicationName: window.applicationName
                        )
                    }
                    try AXHelpers.setFrame(window.frame, on: window.element)
                }

                AXHelpers.setMinimized(window.isMinimized, on: window.element)
            } catch {
                failures.append(error)
                logger.error("Could not restore a window from the layout snapshot")
            }
        }

        if clearingOnCompletion {
            activeSnapshot = nil
        }

        return failures
    }
}
