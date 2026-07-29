import Testing
@testable import PaneCueCore

@Suite("Workspace Apply preflight")
struct WorkspaceApplyPreflightTests {
    @Test
    func selectedCandidateResolvesAnOtherwiseAmbiguousSlot() {
        let scenario = makeScenario(
            targets: [ScenarioWindowTarget(role: .browser)]
        )
        let selectedSlot = scenario.windows[0]
        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: [
                item("browser-one", role: .browser),
                item("browser-two", role: .browser)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false,
            selectedCandidateIDsBySlot: [
                selectedSlot.id: "browser-two"
            ]
        )

        #expect(
            decisions[0].status == .ready(candidateID: "browser-two")
        )
        #expect(decisions[0].candidateIDs == ["browser-two"])
    }

    @Test
    func frozenCandidateDoesNotFallBackToAReplacementAtApplyTime() {
        let scenario = makeScenario(
            targets: [ScenarioWindowTarget(role: .browser)]
        )
        let slotID = scenario.windows[0].id
        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: [item("replacement-window", role: .browser)],
            hasExternalDisplay: false,
            hasActiveCall: false,
            selectedCandidateIDsBySlot: [slotID: "closed-window"]
        )

        #expect(decisions[0].status == .missing)
        #expect(decisions[0].candidateIDs.isEmpty)
    }

    @Test
    func detectsClosedAndAmbiguousTargetsWithoutChoosingSilently() {
        let scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .ide),
                ScenarioWindowTarget(role: .browser),
                ScenarioWindowTarget(role: .notes)
            ]
        )
        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: [
                item("ide", role: .ide),
                item("browser-1", role: .browser),
                item("browser-2", role: .browser)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(decisions[0].status == .ready(candidateID: "ide"))
        #expect(decisions[1].status == .ambiguous(candidateCount: 2))
        #expect(decisions[2].status == .missing)
    }

    @Test
    func blocksFullscreenMinimizedAndUnchangeableWindows() {
        let scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .ide),
                ScenarioWindowTarget(role: .browser),
                ScenarioWindowTarget(role: .notes)
            ]
        )
        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: [
                item("ide", role: .ide, isFullScreen: true),
                item("browser", role: .browser, isMinimized: true),
                item("notes", role: .notes, canSetFrame: false)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(decisions[0].status == .fullScreen(candidateID: "ide"))
        #expect(decisions[1].status == .minimized(candidateID: "browser"))
        #expect(decisions[2].status == .unchangeable(candidateID: "notes"))
    }

    @Test
    func neverReusesOneWindowForTwoPreviewSlots() {
        let scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .ide),
                ScenarioWindowTarget(role: .ide)
            ]
        )
        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: [item("only-ide", role: .ide)],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(decisions[0].status == .ready(candidateID: "only-ide"))
        #expect(decisions[1].status == .missing)
    }

    @Test
    func matchesSpecificApplicationsByBundleIdentifier() {
        let target = ScenarioWindowTarget(
            application: ScenarioApplication(
                bundleIdentifier: "com.microsoft.VSCode",
                displayName: "VS Code"
            )
        )
        let scenario = makeScenario(
            targets: [target, ScenarioWindowTarget(role: .notes)]
        )
        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: [
                item(
                    "vscode",
                    role: .ide,
                    bundleIdentifier: "COM.MICROSOFT.VSCODE"
                ),
                item("notes", role: .notes)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(decisions[0].status == .ready(candidateID: "vscode"))
    }

    @Test
    func revalidatesDisplayAndCallConditions() {
        var externalScenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .ide),
                ScenarioWindowTarget(role: .browser)
            ]
        )
        externalScenario.conditions.requiresExternalDisplay = true

        let disconnected = WorkspaceApplyPreflight.evaluate(
            scenario: externalScenario,
            inventory: [
                item("ide", role: .ide),
                item("browser", role: .browser)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )
        #expect(disconnected.allSatisfy { $0.status == .conditionNotMet })

        var callScenario = externalScenario
        callScenario.conditions = ScenarioConditions(onlyDuringCall: true)
        let noCall = WorkspaceApplyPreflight.evaluate(
            scenario: callScenario,
            inventory: [
                item("ide", role: .ide),
                item("browser", role: .browser)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )
        #expect(noCall.allSatisfy { $0.status == .conditionNotMet })
    }

    @Test
    func blocksOnlyTheExternalSlotWhenDisplayDisappears() {
        var scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .ide),
                ScenarioWindowTarget(role: .browser)
            ]
        )
        scenario.windows[1].display = .external

        let decisions = WorkspaceApplyPreflight.evaluate(
            scenario: scenario,
            inventory: [
                item("ide", role: .ide),
                item("browser", role: .browser)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(decisions[0].status == .ready(candidateID: "ide"))
        #expect(decisions[1].status == .externalDisplayUnavailable)
    }

    private func makeScenario(
        targets: [ScenarioWindowTarget]
    ) -> CustomScenario {
        CustomScenario(
            name: "Acceptance",
            windows: zip(
                targets,
                WorkspacePlan.balancedRects(count: targets.count)
            ).map { target, rect in
                ScenarioWindowSlot(target: target, gridRect: rect)
            }
        )
    }

    private func item(
        _ id: String,
        role: ApplicationRole,
        bundleIdentifier: String? = nil,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        canSetFrame: Bool = true
    ) -> WorkspaceWindowInventoryItem {
        WorkspaceWindowInventoryItem(
            id: id,
            bundleIdentifier: bundleIdentifier,
            applicationName: "Fixture",
            role: role,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            canSetFrame: canSetFrame
        )
    }
}
