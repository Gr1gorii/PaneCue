import Carbon.HIToolbox
import Foundation
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
