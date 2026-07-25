import CoreGraphics
import Testing
@testable import PaneCueCore

@Suite("Layout planner")
struct LayoutPlannerTests {
    @Test
    func customScenarioRatioIsClamped() {
        let application = ScenarioApplication(
            bundleIdentifier: "com.example.primary",
            displayName: "Primary"
        )
        let secondaryApplication = ScenarioApplication(
            bundleIdentifier: "com.example.secondary",
            displayName: "Secondary"
        )

        let tooLarge = CustomScenario(
            name: "Large",
            primaryApplication: application,
            secondaryApplication: secondaryApplication,
            primaryRatio: 0.95
        )
        let tooSmall = CustomScenario(
            name: "Small",
            primaryApplication: application,
            secondaryApplication: secondaryApplication,
            primaryRatio: 0.2
        )

        #expect(tooLarge.primaryRatio == 0.8)
        #expect(tooSmall.primaryRatio == 0.5)
    }

    @Test
    func sideBySideLayoutUsesRequestedRatioAndGap() {
        let frame = CGRect(x: 0, y: 25, width: 1280, height: 775)
        let layout = LayoutPlanner.sideBySide(
            in: frame,
            primaryRatio: 0.65,
            gap: 8
        )

        #expect(layout.primary.minX == 0)
        #expect(layout.primary.minY == 25)
        #expect(layout.primary.height == 775)
        #expect(layout.secondary.minY == 25)
        #expect(layout.secondary.height == 775)
        #expect(layout.secondary.minX - layout.primary.maxX == 8)
        #expect(layout.secondary.maxX == frame.maxX)
        #expect(layout.primary.width + layout.secondary.width + 8 == 1280)
    }

    @Test
    func sideBySideRatioIsClamped() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let layout = LayoutPlanner.sideBySide(
            in: frame,
            primaryRatio: 0.95,
            gap: 0
        )

        #expect(layout.primary.width == 800)
        #expect(layout.secondary.width == 200)
    }

    @Test
    func pictureInPictureStaysInsideVisibleFrame() {
        let frame = CGRect(x: 0, y: 24, width: 1280, height: 776)
        let pip = LayoutPlanner.pictureInPicture(in: frame)

        #expect(pip.minX >= frame.minX)
        #expect(pip.minY >= frame.minY)
        #expect(pip.maxX <= frame.maxX)
        #expect(pip.maxY <= frame.maxY)
        #expect(abs(pip.width / pip.height - 16.0 / 9.0) < 0.001)
    }

    @Test
    func codeAndCallUsesFullIDEAndUpperRightCompactCall() {
        let frame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let layout = LayoutPlanner.codeAndCall(in: frame)

        #expect(layout.primary == frame)
        #expect(layout.secondary == CGRect(
            x: 1104,
            y: 41,
            width: 320,
            height: 240
        ))
    }

    @Test
    func appKitToAccessibilityCoordinateConversion() {
        let primaryScreen = CGRect(x: 0, y: 0, width: 1280, height: 832)
        let visibleFrame = CGRect(x: 0, y: 25, width: 1280, height: 782)

        let converted = ScreenGeometry.appKitRectToAccessibility(
            visibleFrame,
            primaryScreenFrame: primaryScreen
        )

        #expect(converted == CGRect(x: 0, y: 25, width: 1280, height: 782))
    }
}

@Suite("Application role classifier")
struct ApplicationRoleClassifierTests {
    @Test
    func recognizesCommonIDEsByBundleIdentifier() {
        #expect(ApplicationRoleClassifier.role(
            bundleIdentifier: "com.apple.dt.Xcode",
            applicationName: "Xcode",
            windowTitle: "PaneCue"
        ) == .ide)

        #expect(ApplicationRoleClassifier.role(
            bundleIdentifier: "com.jetbrains.intellij",
            applicationName: "IntelliJ IDEA",
            windowTitle: "PaneCue"
        ) == .ide)
    }

    @Test
    func recognizesNativeMeetingApplication() {
        #expect(ApplicationRoleClassifier.role(
            bundleIdentifier: "us.zoom.xos",
            applicationName: "zoom.us",
            windowTitle: "Zoom Meeting"
        ) == .meeting)
    }

    @Test
    func treatsBrowserAsMeetingOnlyForMeetingTab() {
        #expect(ApplicationRoleClassifier.role(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            windowTitle: "Daily sync - Google Meet"
        ) == .meeting)

        #expect(ApplicationRoleClassifier.role(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            windowTitle: "Swift Documentation"
        ) == .browser)
    }

    @Test
    func recognizesNotesApplications() {
        #expect(ApplicationRoleClassifier.role(
            bundleIdentifier: "com.apple.Notes",
            applicationName: "Notes",
            windowTitle: "PaneCue ideas"
        ) == .notes)

        #expect(ApplicationRoleClassifier.role(
            bundleIdentifier: "md.obsidian",
            applicationName: "Obsidian",
            windowTitle: "Workspace"
        ) == .notes)
    }

    @Test
    func recognizesDocumentationApplications() {
        #expect(ApplicationRoleClassifier.role(
            bundleIdentifier: "com.kapeli.dashdoc",
            applicationName: "Dash",
            windowTitle: "Swift Documentation"
        ) == .documentation)
    }
}
