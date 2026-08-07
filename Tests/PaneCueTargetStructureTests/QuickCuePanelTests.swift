import Carbon.HIToolbox
import Foundation
import PaneCueCore
import Testing
@testable import PaneCueApp

@Suite("Quick Cue panel lifecycle")
struct QuickCuePanelTests {
    @Test
    func unrelatedHotKeyEventsContinueThroughTheHandlerChain() {
        let globalSignature: OSType = 0x50437565
        let customSignature: OSType = 0x50435332

        #expect(
            HotKeyEventRouter.rejectionStatus(
                readStatus: noErr,
                receivedSignature: customSignature,
                expectedSignature: globalSignature,
                receivedIdentifier: 1_000,
                expectedIdentifier: 1
            ) == OSStatus(eventNotHandledErr)
        )
        #expect(
            HotKeyEventRouter.rejectionStatus(
                readStatus: noErr,
                receivedSignature: globalSignature,
                expectedSignature: customSignature
            ) == OSStatus(eventNotHandledErr)
        )
        #expect(
            HotKeyEventRouter.rejectionStatus(
                readStatus: noErr,
                receivedSignature: globalSignature,
                expectedSignature: globalSignature,
                receivedIdentifier: 1,
                expectedIdentifier: 1
            ) == nil
        )
    }

    @Test
    func hotKeyConflictHasASettingsSafeStatus() {
        let conflict = GlobalHotKeyError.registrationFailed(
            OSStatus(eventHotKeyExistsErr)
        )
        let unavailable = GlobalHotKeyError.registrationFailed(
            OSStatus(paramErr)
        )

        #expect(conflict.shortcutStatus == .conflict)
        #expect(
            conflict.errorDescription
                == "⌥ Space is already used by another application."
        )
        #expect(unavailable.shortcutStatus == .unavailable)
        #expect(QuickCueShortcutStatus.active.title == "Available")
    }

    @Test
    func reducedMotionDisablesEveryPanelFrameAnimation() {
        #expect(
            QuickCueMotionPolicy.shouldAnimate(
                panelIsVisible: true,
                reduceMotion: false
            )
        )
        #expect(
            !QuickCueMotionPolicy.shouldAnimate(
                panelIsVisible: true,
                reduceMotion: true
            )
        )
        #expect(
            !QuickCueMotionPolicy.shouldAnimate(
                panelIsVisible: false,
                reduceMotion: false
            )
        )
    }

    @Test
    func latencyGateUsesP95AndKeepsOnlyRecentSamples() {
        var tracker = QuickCuePerformanceTracker()
        #expect(!tracker.snapshot.meetsLatencyGates)
        for index in 0..<100 {
            tracker.recordHotKeyToVisible(
                index == 99 ? 0.9 : 0.08
            )
            tracker.recordPreview(
                index == 99 ? 0.9 : 0.3,
                fromTranscript: false
            )
            tracker.recordPreview(
                index == 99 ? 0.9 : 0.3,
                fromTranscript: true
            )
        }

        #expect(tracker.snapshot.hotKeyToVisibleP95 == 0.08)
        #expect(tracker.snapshot.textToPreviewP95 == 0.3)
        #expect(tracker.snapshot.transcriptToPreviewP95 == 0.3)
        #expect(tracker.snapshot.meetsLatencyGates)

        for _ in 0..<100 {
            tracker.recordHotKeyToVisible(0.25)
        }
        #expect(tracker.snapshot.hotKeyToVisibleP95 == 0.25)
        #expect(!tracker.snapshot.meetsLatencyGates)
    }

    @Test
    @MainActor
    func oneHundredOpenCloseCyclesLeaveNoOrphanPanel() {
        let controller = QuickCuePanelController(
            actions: makeLifecycleProbeActions()
        )

        let result = controller.runLifecycleProbe(iterations: 100)

        #expect(result.completedCycles == 100)
        #expect(result.orphanWindowCount == 0)
        #expect(result.passed)
    }

    @Test
    func draftLivesOnlyWhilePanelIsPresented() {
        var session = QuickCuePanelSession()

        session.updateDraft("x")
        #expect(session.draft.isEmpty)

        session.present()
        session.updateDraft("x")
        session.present()
        #expect(session.isPresented)
        #expect(session.draft == "x")

        session.dismiss()
        #expect(!session.isPresented)
        #expect(session.draft.isEmpty)

        session.present()
        #expect(session.draft.isEmpty)
    }

    @Test
    func enterCreatesOnlyAPreviewEffect() throws {
        var session = QuickCuePanelSession()
        session.present()
        session.updateDraft("x")

        let submitEffect = session.submitCommand()
        #expect(submitEffect == .preparePreview("x"))
        #expect(session.phase == .preparing)
        let prematureApply = session.requestApply()
        #expect(prematureApply == nil)

        let preview = makeQuickCuePreview()
        let didFinishPreview = session.finishPreview(preview)
        #expect(didFinishPreview)
        #expect(session.phase == .preview)
        let applyEffect = session.requestApply()
        #expect(applyEffect == .apply(preview))
        #expect(session.phase == .applying)
    }

    @Test
    func externalRequestsStartInPreviewOnlyModeAndResetOnDismiss() {
        var session = QuickCuePanelSession()
        session.present()
        session.updateDraft("old")

        #expect(
            session.beginExternalCommand("new")
                == .preparePreview("new")
        )
        #expect(session.isPresented)
        #expect(session.isExternalRequest)
        #expect(session.phase == .preparing)

        let preview = makeQuickCuePreview(source: .paneCueLink)
        let didFinish = session.finishPreview(preview)
        #expect(didFinish)
        #expect(session.phase == .preview)
        let apply = session.requestApply()
        #expect(apply == .apply(preview))

        session.dismiss()
        #expect(!session.isExternalRequest)
        #expect(session.preview == nil)

        session.beginExternalCuePreview()
        #expect(session.isExternalRequest)
        #expect(session.phase == .preparing)
    }

    @Test
    func paneCueLinkPreviewIsClearlyMarkedAsExternal() {
        let presentation = QuickCuePreviewPresentation(
            preview: makeQuickCuePreview(source: .paneCueLink)
        )

        #expect(presentation.title == "External Preview · 2 windows")
        #expect(presentation.canApply)
    }

    @Test
    func voiceIsUnavailableUntilTextOnboardingCompletes() {
        var session = QuickCuePanelSession()
        session.present()
        session.updateDraft("x")

        #expect(session.requestVoiceStart(isAvailable: false) == nil)
        #expect(session.phase == .composing)
        #expect(session.draft == "x")
        #expect(session.submitCommand() == .preparePreview("x"))
    }

    @Test
    func voiceTranscriptRequiresEditableConfirmationBeforePreview() {
        var session = QuickCuePanelSession()
        session.present()
        session.updateDraft("x")

        #expect(
            session.requestVoiceStart(isAvailable: true) == .startVoice
        )
        #expect(session.phase == .requestingVoice)
        let didStart = session.finishVoiceStart()
        #expect(didStart)
        #expect(session.phase == .recording)
        #expect(session.requestVoiceStop() == .stopAndTranscribe)
        #expect(session.phase == .transcribing)
        let didTranscribe = session.finishVoiceTranscription("y")
        #expect(didTranscribe)

        #expect(session.phase == .composing)
        #expect(session.preview == nil)
        #expect(session.draft == "y")
        #expect(session.transcriptNeedsConfirmation)

        session.updateDraft("z")
        #expect(session.draft == "z")
        #expect(session.submitCommand() == .preparePreview("z"))
        #expect(!session.transcriptNeedsConfirmation)
    }

    @Test
    func deniedOrCancelledVoiceKeepsTextInputUsable() {
        var session = QuickCuePanelSession()
        session.present()
        session.updateDraft("x")

        _ = session.requestVoiceStart(isAvailable: true)
        session.failVoiceStart("permission denied")
        #expect(session.phase == .composing)
        #expect(session.draft == "x")
        #expect(session.errorMessage == "permission denied")

        _ = session.requestVoiceStart(isAvailable: true)
        _ = session.finishVoiceStart()
        session.cancelVoice()
        #expect(session.phase == .composing)
        #expect(session.draft == "x")
        #expect(session.submitCommand() == .preparePreview("x"))
    }

    @Test
    func dismissClearsEveryVoiceOperationState() {
        var session = QuickCuePanelSession()
        session.present()
        _ = session.requestVoiceStart(isAvailable: true)
        _ = session.finishVoiceStart()

        #expect(session.isVoiceOperationActive)
        session.dismiss()
        #expect(!session.isPresented)
        #expect(!session.isVoiceOperationActive)
        #expect(session.phase == .composing)
        #expect(session.draft.isEmpty)
    }

    @Test
    func previewPresentationExplainsEverySlotWithoutCommandText() throws {
        let presentation = QuickCuePreviewPresentation(
            preview: makeQuickCuePreview()
        )

        #expect(presentation.title == "Preview · 2 windows")
        #expect(presentation.canApply)
        #expect(presentation.slots.count == 2)
        #expect(presentation.slots.allSatisfy { $0.state == "Ready" })
        #expect(presentation.slots[0].display == "Main display")
        #expect(
            presentation.slots[0].geometry
                == "65% × 100% · x 0%, y 0%"
        )
        #expect(
            presentation.slots[1].geometry
                == "35% × 100% · x 65%, y 0%"
        )
        #expect(
            presentation.slots[0].detail
                == "Browser · Matched role: Browser"
        )
        #expect(presentation.candidateGroups.isEmpty)
    }

    @Test
    func ambiguousPreviewOffersCandidatesAndBlocksApplyUntilSelection()
        throws {
        var session = QuickCuePanelSession()
        session.present()
        session.updateDraft("x")
        _ = session.submitCommand()

        let ambiguous = makeAmbiguousQuickCuePreview()
        let didFinishAmbiguousPreview = session.finishPreview(ambiguous)
        #expect(didFinishAmbiguousPreview)
        let blockedApply = session.requestApply()
        #expect(blockedApply == nil)

        let presentation = QuickCuePreviewPresentation(preview: ambiguous)
        #expect(!presentation.canApply)
        #expect(presentation.candidateGroups.count == 1)
        #expect(presentation.candidateCount == 2)
        #expect(presentation.candidateGroups[0].title == "Any browser")
        #expect(
            presentation.candidateGroups[0].candidates.map(\.detail)
                == ["First local candidate", "Second local candidate"]
        )

        let slotID = ambiguous.plan.windows[0].id
        let candidateID = EphemeralWindowIdentifier(
            rawValue: "candidate-one"
        )
        let selectionEffect = session.requestCandidateSelection(
            slotID: slotID,
            candidateID: candidateID
        )
        #expect(
            selectionEffect == .selectCandidate(
                previewID: ambiguous.id,
                slotID: slotID,
                candidateID: candidateID
            )
        )
        #expect(session.phase == .selectingCandidate)
        let applyWhileSelecting = session.requestApply()
        #expect(applyWhileSelecting == nil)

        let selectedResolution = try #require(ambiguous.resolution)
            .selecting(candidateID, for: slotID)
        let selected = ArrangementPreview(
            draft: ambiguous.draft,
            eligibility: .ready,
            resolution: selectedResolution
        )
        let didFinishSelection = session.finishCandidateSelection(selected)
        #expect(didFinishSelection)
        #expect(session.phase == .preview)
        let selectedApply = session.requestApply()
        #expect(selectedApply == .apply(selected))
    }

    @Test
    func unavailableCandidateNeverStartsSelection() {
        var session = QuickCuePanelSession()
        session.present()
        session.updateDraft("x")
        _ = session.submitCommand()

        let preview = makeAmbiguousQuickCuePreview(
            firstCandidateUnsupported: true
        )
        let didFinishPreview = session.finishPreview(preview)
        #expect(didFinishPreview)
        let selectionEffect = session.requestCandidateSelection(
            slotID: preview.plan.windows[0].id,
            candidateID: EphemeralWindowIdentifier(
                rawValue: "candidate-one"
            )
        )
        #expect(
            selectionEffect == nil
        )
        #expect(session.phase == .preview)
    }

    @Test
    func pointerDisplayWinsAndFallbackIsDeterministic() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1_200, height: 800),
            CGRect(x: 1_200, y: 0, width: 900, height: 700)
        ]

        #expect(
            QuickCuePanelPlacement.targetScreenIndex(
                pointer: CGPoint(x: 1_500, y: 300),
                screenFrames: frames,
                mainScreenIndex: 0
            ) == 1
        )
        #expect(
            QuickCuePanelPlacement.targetScreenIndex(
                pointer: CGPoint(x: -500, y: -500),
                screenFrames: frames,
                mainScreenIndex: 0
            ) == 0
        )
        #expect(
            QuickCuePanelPlacement.targetScreenIndex(
                pointer: CGPoint(x: -500, y: -500),
                screenFrames: frames,
                mainScreenIndex: nil
            ) == 0
        )
    }

    @Test
    func panelFrameStaysInsideSmallVisibleDisplay() {
        let visibleFrame = CGRect(
            x: 1_200,
            y: 20,
            width: 500,
            height: 360
        )
        let panelFrame = QuickCuePanelPlacement.panelFrame(
            preferredSize: CGSize(width: 620, height: 84),
            visibleFrame: visibleFrame
        )

        #expect(visibleFrame.contains(panelFrame))
        #expect(panelFrame.midX == visibleFrame.midX)
        #expect(panelFrame.midY > visibleFrame.midY)
    }
}

@MainActor
private func makeLifecycleProbeActions() -> QuickCuePanelActions {
    QuickCuePanelActions(
        isVoiceAvailable: { false },
        startVoice: {},
        stopVoice: {
            throw QuickCueTextFlowError.previewUnavailable
        },
        cancelVoice: {},
        preparePreview: { _ in
            throw QuickCueTextFlowError.previewUnavailable
        },
        prepareExternalCommandPreview: { _ in
            throw QuickCueTextFlowError.previewUnavailable
        },
        prepareExternalCuePreview: { _ in
            throw QuickCueTextFlowError.previewUnavailable
        },
        selectCandidate: { _, _, _ in
            throw QuickCueTextFlowError.previewUnavailable
        },
        applyPreview: { _ in
            throw QuickCueTextFlowError.previewUnavailable
        },
        rollback: {
            throw QuickCueTextFlowError.previewUnavailable
        },
        editFullPlan: { _ in },
        discardPreview: {}
    )
}

private func makeQuickCuePreview(
    source: ArrangementRequestSource = .quickCue
) -> ArrangementPreview {
    let plan = WorkspacePlan.tiled(
        targets: [
            ScenarioWindowTarget(role: .browser),
            ScenarioWindowTarget(role: .notes)
        ]
    )
    let names = ["Browser", "Notes"]
    let roles: [ApplicationRole] = [.browser, .notes]
    let slots = zip(plan.windows.indices, plan.windows).map { index, slot in
        ArrangementSlotResolution(
            id: slot.id,
            state: .resolved(
                ResolvedArrangementTarget(
                    bundleIdentifier: "com.example.app\(index)",
                    windowIdentifier: EphemeralWindowIdentifier(
                        rawValue: "window-\(index)"
                    ),
                    display: slot.display,
                    matchReason: .matchedRole(roles[index]),
                    localizedApplicationName: names[index]
                )
            )
        )
    }
    return ArrangementPreview(
        draft: ArrangementDraft(
            source: source,
            plan: plan
        ),
        eligibility: .ready,
        resolution: ArrangementTargetResolutionSet(slots: slots)
    )
}

private func makeAmbiguousQuickCuePreview(
    firstCandidateUnsupported: Bool = false
) -> ArrangementPreview {
    let plan = WorkspacePlan.tiled(
        targets: [
            ScenarioWindowTarget(role: .browser),
            ScenarioWindowTarget(role: .notes)
        ]
    )
    let browserCandidates = [
        ArrangementTargetCandidate(
            windowIdentifier: EphemeralWindowIdentifier(
                rawValue: "candidate-one"
            ),
            bundleIdentifier: "com.example.browser",
            display: .main,
            localizedApplicationName: "Browser",
            localDifferentiator: "First local candidate",
            unsupportedReason: firstCandidateUnsupported
                ? .fullScreen
                : nil
        ),
        ArrangementTargetCandidate(
            windowIdentifier: EphemeralWindowIdentifier(
                rawValue: "candidate-two"
            ),
            bundleIdentifier: "com.example.browser",
            display: .main,
            localizedApplicationName: "Browser",
            localDifferentiator: "Second local candidate"
        )
    ]
    let resolution = ArrangementTargetResolutionSet(
        slots: [
            ArrangementSlotResolution(
                id: plan.windows[0].id,
                state: .ambiguous(candidateCount: 2),
                candidates: browserCandidates
            ),
            ArrangementSlotResolution(
                id: plan.windows[1].id,
                state: .resolved(
                    ResolvedArrangementTarget(
                        bundleIdentifier: "com.example.notes",
                        windowIdentifier: EphemeralWindowIdentifier(
                            rawValue: "notes-window"
                        ),
                        display: .main,
                        matchReason: .matchedRole(.notes),
                        localizedApplicationName: "Notes"
                    )
                )
            )
        ]
    )
    return ArrangementPreview(
        draft: ArrangementDraft(
            source: .quickCue,
            plan: plan
        ),
        eligibility: .blocked,
        resolution: resolution
    )
}
