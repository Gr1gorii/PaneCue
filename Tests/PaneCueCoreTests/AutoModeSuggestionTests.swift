import Darwin
import Testing
@testable import PaneCueCore

@Suite("Auto Mode suggestion engine")
struct AutoModeSuggestionTests {
    @Test
    func suggestsCodeAndCallWhenMeetingAndIDEAreActive() {
        let context = workspace(
            activePID: 1,
            windows: [
                window(pid: 1, name: "VS Code", role: .ide),
                window(pid: 2, name: "FaceTime", role: .meeting),
                window(pid: 3, name: "Chrome", role: .browser)
            ]
        )

        #expect(
            AutoModeSuggestionEngine.suggestion(for: context)?.scenario
                == .codeAndCall
        )
    }

    @Test
    func suggestsDocumentationWhenIDEIsActive() {
        let context = workspace(
            activePID: 1,
            windows: [
                window(pid: 1, name: "Xcode", role: .ide),
                window(pid: 2, name: "Safari", role: .browser)
            ]
        )

        #expect(
            AutoModeSuggestionEngine.suggestion(for: context)?.scenario
                == .documentationAndCode
        )
    }

    @Test
    func suggestsNotesWhenNotesAreActive() {
        let context = workspace(
            activePID: 1,
            windows: [
                window(pid: 1, name: "Notes", role: .notes),
                window(pid: 2, name: "Chrome", role: .browser)
            ]
        )

        #expect(
            AutoModeSuggestionEngine.suggestion(for: context)?.scenario
                == .notesAndBrowser
        )
    }

    @Test
    func usesPreviousRoleToResolveBrowserContext() {
        let context = workspace(
            activePID: 2,
            previousRole: .notes,
            windows: [
                window(pid: 1, name: "Notes", role: .notes),
                window(pid: 2, name: "Chrome", role: .browser),
                window(pid: 3, name: "VS Code", role: .ide)
            ]
        )

        #expect(
            AutoModeSuggestionEngine.suggestion(for: context)?.scenario
                == .notesAndBrowser
        )
    }

    @Test
    func skipsAmbiguousBrowserContext() {
        let context = workspace(
            activePID: 2,
            windows: [
                window(pid: 1, name: "Notes", role: .notes),
                window(pid: 2, name: "Chrome", role: .browser),
                window(pid: 3, name: "VS Code", role: .ide)
            ]
        )

        #expect(AutoModeSuggestionEngine.suggestion(for: context) == nil)
    }

    @Test
    func canSuggestForFullScreenWorkWithoutApplyingIt() {
        let context = workspace(
            activePID: 1,
            windows: [
                window(
                    pid: 1,
                    name: "VS Code",
                    role: .ide,
                    isFullScreen: true
                ),
                window(pid: 2, name: "Safari", role: .browser)
            ]
        )

        #expect(
            AutoModeSuggestionEngine.suggestion(for: context)?.scenario
                == .documentationAndCode
        )
    }

    @Test
    func skipsUnrelatedApplications() {
        let context = workspace(
            activePID: 1,
            windows: [
                window(pid: 1, name: "Finder", role: .other),
                window(pid: 2, name: "Music", role: .other)
            ]
        )

        #expect(AutoModeSuggestionEngine.suggestion(for: context) == nil)
    }

    private func workspace(
        activePID: pid_t,
        previousRole: ApplicationRole? = nil,
        windows: [AutoModeWindowContext]
    ) -> AutoModeWorkspaceContext {
        AutoModeWorkspaceContext(
            windows: windows,
            frontmostProcessIdentifier: activePID,
            previousActiveRole: previousRole
        )
    }

    private func window(
        pid: pid_t,
        name: String,
        role: ApplicationRole,
        isFullScreen: Bool = false
    ) -> AutoModeWindowContext {
        AutoModeWindowContext(
            processIdentifier: pid,
            applicationName: name,
            role: role,
            isFullScreen: isFullScreen
        )
    }
}
