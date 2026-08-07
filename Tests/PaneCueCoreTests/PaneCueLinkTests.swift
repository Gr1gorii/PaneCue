import Foundation
import Testing
@testable import PaneCueCore

@Suite("PaneCue Links")
struct PaneCueLinkTests {
    @Test
    func parsesTheThreeFrozenRoutes() throws {
        let cueID = try #require(
            UUID(uuidString: "8AC37E2C-878C-40C0-ABF7-A048945FD1C8")
        )

        #expect(
            PaneCueLinkParser.parse("panecue://show")
                == .accepted(.show)
        )
        #expect(
            PaneCueLinkParser.parse(
                "panecue://preview?text=fixture%20value"
            ) == .accepted(
                .preview(command: "fixture value")
            )
        )
        #expect(
            PaneCueLinkParser.parse(
                "panecue://preview?text=%D1%82%D0%B5%D1%81%D1%82"
            ) == .accepted(.preview(command: "тест"))
        )
        #expect(
            PaneCueLinkParser.parse("panecue://cue?id=\(cueID)")
                == .accepted(.cue(id: cueID))
        )
    }

    @Test
    func rejectsEveryRouteThatCouldImplyExternalApply() {
        let values = [
            "panecue://apply",
            "panecue://run-without-confirmation",
            "panecue://open-arbitrary-url?url=https%3A%2F%2Fexample.com"
        ]

        for value in values {
            #expect(
                PaneCueLinkParser.parse(value)
                    == .rejected(.unsupported)
            )
        }
    }

    @Test
    func rejectsMalformedOrUnexpectedInputs() {
        let malformed = [
            "https://show",
            "panecue://show/extra",
            "panecue://show?extra=1",
            "panecue://preview",
            "panecue://preview?text=",
            "panecue://preview?text=one&text=two",
            "panecue://preview?command=one",
            "panecue://preview?text=%ZZ",
            "panecue://preview?text=one%0Atwo",
            "panecue://cue?id=not-a-uuid",
            "panecue://cue?id=8AC37E2C-878C-40C0-ABF7-A048945FD1C8&x=1",
            "panecue://user@show",
            "panecue://show:80",
            "panecue://show#fragment"
        ]

        for value in malformed {
            #expect(
                PaneCueLinkParser.parse(value)
                    == .rejected(.malformed)
            )
        }
    }

    @Test
    func rejectsOversizedURLAndCommand() {
        let longCommand = String(
            repeating: "x",
            count: PaneCueLinkParser.maximumCommandByteCount + 1
        )
        let longURL = String(
            repeating: "x",
            count: PaneCueLinkParser.maximumURLByteCount + 1
        )

        #expect(
            PaneCueLinkParser.parse(
                "panecue://preview?text=\(longCommand)"
            ) == .rejected(.oversized)
        )
        #expect(
            PaneCueLinkParser.parse(longURL)
                == .rejected(.oversized)
        )
    }

    @Test
    func suppressesImmediateDuplicatesWithoutKeepingRawRequests() {
        var gate = PaneCueLinkAdmissionGate()
        let value = "panecue://preview?text=fixture"

        #expect(
            gate.admit(value, at: 10)
                == .accepted(.preview(command: "fixture"))
        )
        #expect(gate.admit(value, at: 10.5) == .rejected(.repeated))
        #expect(
            gate.admit(value, at: 12)
                == .accepted(.preview(command: "fixture"))
        )
    }

    @Test
    func rateLimitsDifferentValidRequestsAndRecovers() {
        var gate = PaneCueLinkAdmissionGate()

        for index in 0..<PaneCueLinkAdmissionGate
            .maximumRequestsPerRateInterval {
            #expect(
                gate.admit(
                    "panecue://preview?text=command%20\(index)",
                    at: Double(index)
                ) == .accepted(.preview(command: "command \(index)"))
            )
        }
        #expect(
            gate.admit(
                "panecue://preview?text=blocked",
                at: 5
            ) == .rejected(.rateLimited)
        )
        #expect(
            gate.admit(
                "panecue://preview?text=accepted",
                at: 10
            ) == .accepted(.preview(command: "accepted"))
        )
    }
}
