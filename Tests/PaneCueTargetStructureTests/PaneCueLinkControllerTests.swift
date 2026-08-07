import Foundation
import PaneCueCore
import Testing
@testable import PaneCueApp

@Suite("PaneCue Link application boundary")
struct PaneCueLinkControllerTests {
    @Test
    @MainActor
    func queuesTheLastColdLaunchRequestThenDispatchesVisibleUI() throws {
        var received: [PaneCueLinkRequest] = []
        let controller = PaneCueLinkController(
            actions: PaneCueLinkActions(
                show: { received.append(.show) },
                previewCommand: {
                    received.append(.preview(command: $0))
                },
                previewCue: { received.append(.cue(id: $0)) }
            )
        )
        let cueID = try #require(
            UUID(uuidString: "8AC37E2C-878C-40C0-ABF7-A048945FD1C8")
        )

        _ = controller.receive(
            [try #require(URL(string: "panecue://show"))],
            at: 0
        )
        _ = controller.receive(
            [try #require(URL(string: "panecue://cue?id=\(cueID)"))],
            at: 0.1
        )
        #expect(received.isEmpty)

        controller.applicationDidBecomeReady()
        #expect(received == [.cue(id: cueID)])

        _ = controller.receive(
            [
                try #require(
                    URL(string: "panecue://preview?text=fixture")
                )
            ],
            at: 0.2
        )
        #expect(
            received == [
                .cue(id: cueID),
                .preview(command: "fixture")
            ]
        )
    }

    @Test
    @MainActor
    func prohibitedAndRepeatedLinksNeverReachAnAction() throws {
        var actionCount = 0
        let controller = PaneCueLinkController(
            actions: PaneCueLinkActions(
                show: { actionCount += 1 },
                previewCommand: { _ in actionCount += 1 },
                previewCue: { _ in actionCount += 1 }
            )
        )
        controller.applicationDidBecomeReady()
        let show = try #require(URL(string: "panecue://show"))

        let prohibited = controller.receive(
            [try #require(URL(string: "panecue://apply"))],
            at: 10
        )
        #expect(prohibited == [.rejected(.unsupported)])
        #expect(actionCount == 0)

        let first = controller.receive([show], at: 11)
        let repeated = controller.receive([show], at: 11.5)
        #expect(first == [.accepted(.show)])
        #expect(repeated == [.rejected(.repeated)])
        #expect(actionCount == 1)
    }
}
