import CoreGraphics
import Foundation
import Testing
@testable import PaneCueCore

@Suite("Custom scenario 2.0")
struct CustomScenarioV2Tests {
    @Test
    func migratesLegacyTwoApplicationScenario() throws {
        let json = """
        {
          "id": "10000000-0000-0000-0000-000000000001",
          "name": "Legacy Research",
          "primaryApplication": {
            "bundleIdentifier": "com.example.ide",
            "displayName": "Example IDE"
          },
          "secondaryApplication": {
            "bundleIdentifier": "com.example.browser",
            "displayName": "Example Browser"
          },
          "primaryRatio": 0.7
        }
        """

        let scenario = try JSONDecoder().decode(
            CustomScenario.self,
            from: Data(json.utf8)
        )

        #expect(scenario.windows.count == 2)
        #expect(scenario.windows[0].target.application?.displayName
            == "Example IDE")
        #expect(scenario.windows[1].target.application?.displayName
            == "Example Browser")
        #expect(scenario.windows[0].gridRect.width == 0.7)
        #expect(scenario.windows[1].gridRect.x == 0.7)
    }

    @Test
    func roundTripsRolesConditionsAndActivation() throws {
        let scenario = CustomScenario(
            name: "Deep Work",
            windows: [
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .ide),
                    gridRect: .left
                ),
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .browser),
                    gridRect: .right,
                    display: .external,
                    urlString: "https://example.com/docs"
                )
            ],
            conditions: ScenarioConditions(
                onlyDuringCall: true,
                requiresExternalDisplay: true
            ),
            voicePhrase: "start deep work",
            hotKey: ScenarioHotKey(
                key: "D",
                usesCommand: true,
                usesOption: true,
                usesControl: false
            )
        )

        let data = try JSONEncoder().encode(scenario)
        let decoded = try JSONDecoder().decode(
            CustomScenario.self,
            from: data
        )

        #expect(decoded == scenario)
        #expect(decoded.windows[0].target.role == .ide)
        #expect(decoded.windows[1].display == .external)
        #expect(decoded.conditions.onlyDuringCall)
        #expect(decoded.voicePhrase == "start deep work")
        #expect(decoded.hotKey.displayName == "⌥⌘D")
    }

    @Test
    func gridRectIsKeptInsideDisplay() {
        let rect = ScenarioGridRect(
            x: 0.9,
            y: -0.4,
            width: 0.5,
            height: 2
        )

        #expect(rect.x == 0.5)
        #expect(rect.y == 0)
        #expect(rect.width == 0.5)
        #expect(rect.height == 1)
    }

    @Test
    func mapsNormalizedGridRectToScreenFrame() {
        let screen = CGRect(x: 100, y: 50, width: 1_000, height: 800)
        let grid = ScenarioGridRect(
            x: 0.25,
            y: 0.5,
            width: 0.5,
            height: 0.25
        )

        let frame = LayoutPlanner.frame(
            for: grid,
            in: screen,
            gap: 0
        )

        #expect(frame == CGRect(
            x: 350,
            y: 450,
            width: 500,
            height: 200
        ))
    }
}
