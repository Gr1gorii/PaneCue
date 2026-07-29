import Testing
@testable import PaneCueCore

@Suite("Arrangement target resolution")
struct ArrangementTargetResolutionTests {
    @Test
    func assignsOneFrozenStateToEverySlot() throws {
        let specificApplication = ScenarioApplication(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor"
        )
        let scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(application: specificApplication),
                ScenarioWindowTarget(role: .browser),
                ScenarioWindowTarget(role: .documentation),
                ScenarioWindowTarget(role: .notes)
            ]
        )
        let resolution = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [
                item(
                    "editor-window",
                    role: .ide,
                    bundleIdentifier: "com.example.Editor"
                ),
                item("browser-one", role: .browser),
                item("browser-two", role: .browser),
                item("notes-window", role: .notes, isFullScreen: true)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(resolution.slots.count == scenario.windows.count)
        guard case let .resolved(target) = resolution.slots[0].state else {
            Issue.record("Specific application did not resolve")
            return
        }
        #expect(target.bundleIdentifier == "com.example.Editor")
        #expect(target.matchReason == .specificApplication)
        #expect(
            resolution.slots[1].state
                == .ambiguous(candidateCount: 2)
        )
        #expect(
            resolution.slots[1].candidates.map(\.windowIdentifier.rawValue)
                == ["browser-one", "browser-two"]
        )
        #expect(resolution.slots[2].state == .missing)
        #expect(
            resolution.slots[3].state
                == .unsupported(.fullScreen)
        )
        #expect(!resolution.isReadyForApply)
        #expect(resolution.requiresCandidateSelection)
    }

    @Test
    func resolvedTargetCarriesOnlyTheFrozenLocalMetadata() throws {
        let scenario = makeScenario(
            targets: [ScenarioWindowTarget(role: .browser)]
        )
        let slotID = try #require(scenario.windows.first?.id)
        let resolution = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [
                item(
                    "temporary-window-7",
                    role: .browser,
                    bundleIdentifier: "com.example.Browser",
                    applicationName: "Browser",
                    display: .external
                )
            ],
            hasExternalDisplay: true,
            hasActiveCall: false
        )

        let slot = try #require(resolution[slotID])
        guard case let .resolved(target) = slot.state else {
            Issue.record("Browser target did not resolve")
            return
        }

        #expect(target.bundleIdentifier == "com.example.Browser")
        #expect(target.windowIdentifier.rawValue == "temporary-window-7")
        #expect(target.display == .external)
        #expect(target.matchReason == .matchedRole(.browser))
        #expect(target.localizedApplicationName == "Browser")
        #expect(resolution.isReadyForApply)

        let storedFields = Set(
            Mirror(reflecting: target).children.compactMap(\.label)
        )
        #expect(
            storedFields == [
                "bundleIdentifier",
                "windowIdentifier",
                "display",
                "matchReason",
                "localizedApplicationName"
            ]
        )
    }

    @Test
    func exposesTheFiveFrozenMatchReasonDescriptionsWithoutConfidence() {
        let reasons: [ArrangementTargetMatchReason] = [
            .specificApplication,
            .matchedRole(.browser),
            .selectedByUser,
            .onlyMatchingWindow,
            .savedCueMapping
        ]

        #expect(
            reasons.map(\.shortDescription) == [
                "Specific application",
                "Matched role: Browser",
                "Selected by you",
                "Only matching window",
                "Saved Cue mapping"
            ]
        )
        #expect(
            reasons.allSatisfy {
                !$0.shortDescription.contains("%")
                    && !$0.shortDescription
                        .localizedCaseInsensitiveContains("confidence")
            }
        )
    }

    @Test
    func savedCueSourceAttributesEveryResolvedSlotToItsMapping() throws {
        let scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .browser),
                ScenarioWindowTarget(role: .notes)
            ]
        )
        let resolution = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [
                item("browser-window", role: .browser),
                item("notes-window", role: .notes)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false,
            requestSource: .savedCue
        )

        let reasons = try resolution.slots.map { slot in
            guard case let .resolved(target) = slot.state else {
                throw MatchReasonFixtureError.unresolvedSlot
            }
            return target.matchReason
        }
        #expect(reasons == [.savedCueMapping, .savedCueMapping])
    }

    @Test
    func candidateWithoutBundleIdentifierIsUnsupported() {
        let scenario = makeScenario(
            targets: [ScenarioWindowTarget(role: .notes)]
        )
        let resolution = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [
                item(
                    "notes-window",
                    role: .notes,
                    bundleIdentifier: nil
                )
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(
            resolution.slots.first?.state
                == .unsupported(.missingBundleIdentifier)
        )
        #expect(!resolution.isReadyForApply)
    }

    @Test
    func mapsEveryExistingBlockerToUnsupported() {
        let scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .ide),
                ScenarioWindowTarget(role: .browser),
                ScenarioWindowTarget(role: .notes)
            ]
        )
        let resolution = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [
                item("ide", role: .ide, isMinimized: true),
                item("browser", role: .browser, canSetFrame: false),
                item("notes", role: .notes, isFullScreen: true)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(
            resolution.slots.map(\.state) == [
                .unsupported(.minimized),
                .unsupported(.unchangeable),
                .unsupported(.fullScreen)
            ]
        )
    }

    @Test
    func mapsUnavailableExternalDisplayToUnsupported() {
        let scenario = CustomScenario(
            name: "External Display Fixture",
            windows: [
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .browser),
                    gridRect: .left,
                    display: .external
                )
            ]
        )
        let resolution = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [item("browser", role: .browser)],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(
            resolution.slots.first?.state
                == ArrangementTargetResolutionState.unsupported(
                    .externalDisplayUnavailable
                )
        )
    }

    @Test
    func mapsUnmetScenarioConditionToUnsupported() {
        let scenario = CustomScenario(
            name: "Call Condition Fixture",
            windows: [
                ScenarioWindowSlot(
                    target: ScenarioWindowTarget(role: .meeting),
                    gridRect: .left
                )
            ],
            conditions: ScenarioConditions(onlyDuringCall: true)
        )
        let resolution = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [item("meeting", role: .meeting)],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(
            resolution.slots.first?.state
                == ArrangementTargetResolutionState.unsupported(
                    .conditionNotMet
                )
        )
    }

    @Test
    func selectingCandidateBindsItToTheRequestedSlot() throws {
        let scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .browser),
                ScenarioWindowTarget(role: .notes)
            ]
        )
        let initial = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [
                item("browser-one", role: .browser),
                item("browser-two", role: .browser),
                item("notes", role: .notes)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        #expect(!initial.isReadyForApply)
        let selected = try initial.selecting(
            EphemeralWindowIdentifier(rawValue: "browser-two"),
            for: scenario.windows[0].id
        )

        guard case let .resolved(target) = selected.slots[0].state else {
            Issue.record("The selected candidate was not bound to its slot")
            return
        }
        #expect(target.windowIdentifier.rawValue == "browser-two")
        #expect(target.matchReason == .selectedByUser)
        #expect(
            selected.selectedCandidateIDsBySlot[scenario.windows[0].id]
                == "browser-two"
        )
        #expect(selected.isReadyForApply)
    }

    @Test
    func selectionNeverAssignsOneWindowToTwoSlots() throws {
        let scenario = makeScenario(
            targets: [
                ScenarioWindowTarget(role: .browser),
                ScenarioWindowTarget(role: .browser)
            ]
        )
        let initial = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [
                item("browser-one", role: .browser),
                item("browser-two", role: .browser)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )

        let selected = try initial.selecting(
            EphemeralWindowIdentifier(rawValue: "browser-one"),
            for: scenario.windows[0].id
        )

        guard case let .resolved(first) = selected.slots[0].state,
              case let .resolved(second) = selected.slots[1].state else {
            Issue.record("The remaining unique candidate was not resolved")
            return
        }
        #expect(first.windowIdentifier.rawValue == "browser-one")
        #expect(first.matchReason == .selectedByUser)
        #expect(second.windowIdentifier.rawValue == "browser-two")
        #expect(second.matchReason == .onlyMatchingWindow)
        #expect(first.windowIdentifier != second.windowIdentifier)
        #expect(selected.isReadyForApply)
    }

    @Test
    func unsupportedCandidateCannotBeSelected() throws {
        let scenario = makeScenario(
            targets: [ScenarioWindowTarget(role: .browser)]
        )
        let initial = WorkspaceTargetResolver.resolve(
            scenario: scenario,
            inventory: [
                item(
                    "blocked-browser",
                    role: .browser,
                    isFullScreen: true
                ),
                item("available-browser", role: .browser)
            ],
            hasExternalDisplay: false,
            hasActiveCall: false
        )
        let blocked = try #require(
            initial.slots[0].candidates.first(where: {
                $0.windowIdentifier.rawValue == "blocked-browser"
            })
        )

        #expect(!blocked.isSelectable)
        #expect(blocked.unsupportedReason == .fullScreen)
        #expect(throws: ArrangementTargetSelectionError.candidateUnsupported) {
            try initial.selecting(
                blocked.windowIdentifier,
                for: scenario.windows[0].id
            )
        }
    }

    private func makeScenario(
        targets: [ScenarioWindowTarget]
    ) -> CustomScenario {
        CustomScenario(
            name: "Resolution Fixture",
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
        bundleIdentifier: String? = "com.example.Application",
        applicationName: String = "Application",
        display: ScenarioDisplayTarget = .main,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        canSetFrame: Bool = true
    ) -> WorkspaceWindowInventoryItem {
        WorkspaceWindowInventoryItem(
            id: id,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            role: role,
            display: display,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            canSetFrame: canSetFrame
        )
    }
}

private enum MatchReasonFixtureError: Error {
    case unresolvedSlot
}
