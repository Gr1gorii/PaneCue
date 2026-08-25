import CoreGraphics
import Testing
@testable import PaneCueCore

@Suite("System window placement")
struct SystemWindowPlacementTests {
    private let visibleFrame = CGRect(
        x: 0,
        y: 39,
        width: 1_710,
        height: 1_014
    )

    @Test(arguments: SystemWindowPlacement.allCases)
    func matchesEveryNativeHalfAndQuarter(
        placement: SystemWindowPlacement
    ) {
        let nativeFrame = placement.nativeFrame(in: visibleFrame)
        let paneCueFrame = nativeFrame.insetBy(dx: 4, dy: 4)

        #expect(
            SystemWindowPlacement.matching(
                targetFrame: paneCueFrame,
                in: visibleFrame
            ) == placement
        )
    }

    @Test
    func rejectsANonNativeGridFrame() {
        let customFrame = CGRect(
            x: 4,
            y: 43,
            width: visibleFrame.width * 0.56 - 8,
            height: visibleFrame.height - 8
        )

        #expect(
            SystemWindowPlacement.matching(
                targetFrame: customFrame,
                in: visibleFrame
            ) == nil
        )
    }

    @Test
    func mapsPlacementsToTheStableMenuSlots() {
        #expect(SystemWindowPlacement.leftHalf.moveResizeMenuIndex == 1)
        #expect(SystemWindowPlacement.rightHalf.moveResizeMenuIndex == 2)
        #expect(SystemWindowPlacement.topHalf.moveResizeMenuIndex == 3)
        #expect(SystemWindowPlacement.bottomHalf.moveResizeMenuIndex == 4)
        #expect(SystemWindowPlacement.topLeftQuarter.moveResizeMenuIndex == 6)
        #expect(SystemWindowPlacement.topRightQuarter.moveResizeMenuIndex == 7)
        #expect(SystemWindowPlacement.bottomLeftQuarter.moveResizeMenuIndex == 8)
        #expect(SystemWindowPlacement.bottomRightQuarter.moveResizeMenuIndex == 9)
    }

    @Test
    func locatesFillRelativeToMoveAndResize() {
        #expect(
            SystemWindowMoveResizeMenu.fillIndex(
                beforeMoveAndResizeIndex: 6,
                itemCount: 7
            ) == 4
        )
        #expect(
            SystemWindowMoveResizeMenu.fillIndex(
                beforeMoveAndResizeIndex: 1,
                itemCount: 6
            ) == nil
        )
    }

    @Test
    func recognizesTheMoveAndResizeMenuWithoutLocalizedLabels() {
        let states = [
            false,
            true, true, true, true,
            false,
            true, true, true, true,
            false,
            true, true, true,
            true,
        ]

        #expect(
            SystemWindowMoveResizeMenu.hasExpectedTopology(
                enabledStates: states
            )
        )
        #expect(
            SystemWindowMoveResizeMenu.previousSizeIndex(
                enabledStates: states
            ) == states.indices.last
        )
    }

    @Test
    func doesNotChooseADisabledPreviousSizeAction() {
        let states = [
            false,
            true, true, true, true,
            false,
            true, true, true, true,
            false,
            true, true, true,
            false,
        ]

        #expect(
            SystemWindowMoveResizeMenu.previousSizeIndex(
                enabledStates: states
            ) == nil
        )
    }
}
