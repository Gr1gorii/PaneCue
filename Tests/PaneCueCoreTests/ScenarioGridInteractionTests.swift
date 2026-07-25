import CoreGraphics
import Testing
@testable import PaneCueCore

@Suite("Scenario grid interaction")
struct ScenarioGridInteractionTests {
    private let canvas = CGSize(width: 1_200, height: 800)
    private let start = ScenarioGridRect(
        x: 0.25,
        y: 0.25,
        width: 0.5,
        height: 0.5
    )

    @Test
    func movementRemainsContinuousUntilCommit() {
        let preview = ScenarioGridInteraction.movedRect(
            from: start,
            translation: CGSize(width: 17, height: 13),
            canvasSize: canvas
        )

        #expect(
            abs(preview.x - (0.25 + 17.0 / 1_200.0)) < 0.000_001
        )
        #expect(
            abs(preview.y - (0.25 + 13.0 / 800.0)) < 0.000_001
        )

        let committed = ScenarioGridInteraction.snappedMovedRect(preview)
        #expect(committed.x == 0.25)
        #expect(committed.y == 0.25)
    }

    @Test
    func movementCannotLeaveCanvas() {
        let moved = ScenarioGridInteraction.movedRect(
            from: start,
            translation: CGSize(width: 10_000, height: -10_000),
            canvasSize: canvas
        )

        #expect(moved.x == 0.5)
        #expect(moved.y == 0)
        #expect(moved.width == start.width)
        #expect(moved.height == start.height)
    }

    @Test
    func everyResizeHandleChangesOnlyItsEdges() {
        for handle in ScenarioGridResizeHandle.allCases {
            let resized = ScenarioGridInteraction.resizedRect(
                from: start,
                handle: handle,
                translation: CGSize(width: 120, height: 80),
                canvasSize: canvas
            )

            let minimumXChanged = abs(resized.x - start.x) > 0.000_001
            let maximumXChanged = abs(
                resized.x + resized.width - start.x - start.width
            ) > 0.000_001
            let minimumYChanged = abs(resized.y - start.y) > 0.000_001
            let maximumYChanged = abs(
                resized.y + resized.height - start.y - start.height
            ) > 0.000_001

            #expect(minimumXChanged == handle.changesMinimumX)
            #expect(maximumXChanged == handle.changesMaximumX)
            #expect(minimumYChanged == handle.changesMinimumY)
            #expect(maximumYChanged == handle.changesMaximumY)
        }
    }

    @Test
    func resizeEnforcesMinimumSize() {
        let resized = ScenarioGridInteraction.resizedRect(
            from: start,
            handle: .topLeading,
            translation: CGSize(width: 10_000, height: 10_000),
            canvasSize: canvas
        )

        #expect(abs(resized.width - 1.0 / 24.0) < 0.000_001)
        #expect(abs(resized.height - 1.0 / 16.0) < 0.000_001)
        #expect(abs(resized.x + resized.width - 0.75) < 0.000_001)
        #expect(abs(resized.y + resized.height - 0.75) < 0.000_001)
    }

    @Test
    func onlyDraggedEdgesSnapOnCommit() {
        let preview = ScenarioGridInteraction.resizedRect(
            from: start,
            handle: .bottomTrailing,
            translation: CGSize(width: 103, height: 61),
            canvasSize: canvas
        )
        let committed = ScenarioGridInteraction.snappedResizedRect(
            preview,
            handle: .bottomTrailing
        )

        #expect(committed.x == start.x)
        #expect(committed.y == start.y)
        #expect(
            abs(
                committed.x + committed.width - 20.0 / 24.0
            ) < 0.000_001
        )
        #expect(
            abs(
                committed.y + committed.height - 13.0 / 16.0
            ) < 0.000_001
        )
    }

    @Test
    func movementSnapsToDetailedGrid() {
        let rect = ScenarioGridRect(
            x: 0.08,
            y: 0.13,
            width: 0.25,
            height: 0.25
        )

        let committed = ScenarioGridInteraction.snappedMovedRect(rect)

        #expect(abs(committed.x - 2.0 / 24.0) < 0.000_001)
        #expect(abs(committed.y - 2.0 / 16.0) < 0.000_001)
    }
}
