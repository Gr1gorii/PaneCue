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

    @Test
    func deterministicFuzzNeverCrashesOrCreatesApplyAuthority() {
        var generator = PaneCueLinkFuzzGenerator(
            state: 0x5041_4E45_4355_4532
        )

        for index in 0..<4_096 {
            let candidate = generator.candidate(iteration: index)

            switch PaneCueLinkParser.parse(candidate) {
            case .accepted(.show),
                 .accepted(.preview),
                 .accepted(.cue):
                // The exhaustive switch is the security assertion: accepted
                // input can only produce one of the three Preview-only
                // authorities in PaneCueLinkRequest. Apply is not a case.
                break
            case .rejected:
                break
            }
        }
    }
}

private struct PaneCueLinkFuzzGenerator {
    private static let alphabet = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:/?&=%#@.-_+ \n\t"
            .utf8
    )

    var state: UInt64

    mutating func candidate(iteration: Int) -> String {
        if iteration.isMultiple(of: 31) {
            return String(
                repeating: "x",
                count: PaneCueLinkParser.maximumURLByteCount
                    + Int(next() % 32)
                    + 1
            )
        }

        var bytes: [UInt8]
        if iteration.isMultiple(of: 2) {
            let routes = ["show", "preview?text=fixture", "cue?id=fixture"]
            let route = routes[iteration % routes.count]
            bytes = Array(
                "\(PaneCueLinkParser.scheme)://\(route)".utf8
            )
        } else {
            bytes = []
        }

        let editCount = 1 + Int(next() % 24)
        for _ in 0..<editCount {
            switch next() % 3 {
            case 0 where !bytes.isEmpty:
                bytes.remove(at: Int(next() % UInt64(bytes.count)))
            case 1 where !bytes.isEmpty:
                bytes[Int(next() % UInt64(bytes.count))] = randomByte()
            default:
                let index = bytes.isEmpty
                    ? 0
                    : Int(next() % UInt64(bytes.count + 1))
                bytes.insert(randomByte(), at: index)
            }
        }

        return String(decoding: bytes, as: UTF8.self)
    }

    private mutating func randomByte() -> UInt8 {
        Self.alphabet[Int(next() % UInt64(Self.alphabet.count))]
    }

    private mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
