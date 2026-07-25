import AppKit
import ApplicationServices
import OSLog

@MainActor
public final class WindowManager {
    private let logger = Logger(
        subsystem: PaneCueIdentity.bundleIdentifier,
        category: "WindowManager"
    )

    private var activeSnapshot: [WindowSnapshot]?
    private var activeScenarioName: String?

    public init() {}

    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public var canRestore: Bool {
        activeSnapshot != nil
    }

    public var currentScenarioName: String? {
        activeScenarioName
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        // The imported global constant is mutable in the legacy C header and
        // therefore rejected by Swift 6 strict concurrency checking.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func eligibleWindows() throws -> [ManagedWindow] {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let runningApplications = NSWorkspace.shared.runningApplications.filter { application in
            !application.isTerminated
                && application.processIdentifier != ownPID
                && application.activationPolicy == .regular
        }

        return runningApplications.flatMap { application in
            windows(for: application)
        }
    }

    public func applyCodeAndCallLayout() throws -> String {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        restoreActiveLayoutBeforeApplying()

        guard let visibleFrame = ScreenGeometry.primaryVisibleFrameInAccessibilityCoordinates() else {
            throw PaneCueWindowError.noUsableScreen
        }

        let windows = try eligibleWindows()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let ideWindows = windows.filter {
            role(of: $0) == .ide
        }
        guard let ide = preferredWindow(
            among: ideWindows,
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "code editor",
                examples: "Xcode, VS Code, Cursor, or a JetBrains IDE"
            )
        }

        let meetingWindows = windows.filter {
            $0.processIdentifier != ide.processIdentifier
                && role(of: $0) == .meeting
        }
        guard let meeting = preferredMeetingWindow(
            among: meetingWindows,
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "call",
                examples: "Zoom, Teams, FaceTime, Webex, or a supported browser meeting"
            )
        }

        let snapshot = [ide].map { window in
            WindowSnapshot(
                element: window.element,
                applicationName: window.applicationName,
                title: window.title,
                frame: window.frame,
                isMinimized: window.isMinimized,
                isFullScreen: window.isFullScreen
            )
        }

        do {
            AXHelpers.setMinimized(false, on: ide.element)
            if !ide.isFullScreen {
                try leaveFullScreenIfNeeded(ide)
                try AXHelpers.setFrame(visibleFrame, on: ide.element)
            }
            AXHelpers.raise(ide.element)

            activeSnapshot = snapshot
            activeScenarioName = "Code + Call"

            logger.info(
                "Applied Code + Call to \(ide.applicationName, privacy: .public) and \(meeting.applicationName, privacy: .public)"
            )

            return "Code + Call · \(ide.applicationName) + \(meeting.applicationName)"
        } catch {
            restore(snapshot, clearingOnCompletion: false)
            throw error
        }
    }

    public func applyDocumentationAndCodeLayout() throws -> String {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        restoreActiveLayoutBeforeApplying()

        guard let visibleFrame = ScreenGeometry.primaryVisibleFrameInAccessibilityCoordinates() else {
            throw PaneCueWindowError.noUsableScreen
        }

        let windows = try eligibleWindows()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        guard let ide = preferredWindow(
            among: windows.filter { role(of: $0) == .ide },
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "code editor",
                examples: "Xcode, VS Code, Cursor, or a JetBrains IDE"
            )
        }

        let documentationWindows = windows.filter { window in
            guard window.processIdentifier != ide.processIdentifier else {
                return false
            }
            let windowRole = role(of: window)
            return windowRole == .browser || windowRole == .documentation
        }

        guard let documentation = preferredWindow(
            among: documentationWindows,
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "documentation",
                examples: "Safari, Chrome, Firefox, Preview, or Dash"
            )
        }

        return try applyPairLayout(
            primary: ide,
            secondary: documentation,
            visibleFrame: visibleFrame,
            scenarioName: "Documentation + Code",
            summary: "Documentation + Code · \(ide.applicationName) 65% + \(documentation.applicationName) 35%"
        )
    }

    public func applyNotesAndBrowserLayout() throws -> String {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        restoreActiveLayoutBeforeApplying()

        guard let visibleFrame = ScreenGeometry.primaryVisibleFrameInAccessibilityCoordinates() else {
            throw PaneCueWindowError.noUsableScreen
        }

        let windows = try eligibleWindows()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        guard let browser = preferredWindow(
            among: windows.filter { role(of: $0) == .browser },
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "browser",
                examples: "Safari, Chrome, Firefox, Edge, or Brave"
            )
        }

        guard let notes = preferredWindow(
            among: windows.filter {
                $0.processIdentifier != browser.processIdentifier
                    && role(of: $0) == .notes
            },
            frontmostPID: frontmostPID
        ) else {
            throw PaneCueWindowError.requiredRoleMissing(
                role: "notes",
                examples: "Apple Notes, Notion, Obsidian, Bear, or Craft"
            )
        }

        return try applyPairLayout(
            primary: browser,
            secondary: notes,
            visibleFrame: visibleFrame,
            scenarioName: "Notes + Browser",
            summary: "Notes + Browser · \(browser.applicationName) 65% + \(notes.applicationName) 35%"
        )
    }

    public func applyCustomLayout(
        _ scenario: CustomScenario
    ) throws -> String {
        guard hasAccessibilityPermission else {
            throw PaneCueWindowError.accessibilityPermissionRequired
        }

        guard scenario.windows.count >= 2 else {
            throw PaneCueWindowError.notEnoughEligibleWindows(
                found: scenario.windows.count
            )
        }

        let windows = try eligibleWindows()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?
            .processIdentifier

        if scenario.conditions.requiresExternalDisplay,
           !ScreenGeometry.hasExternalDisplay {
            throw PaneCueWindowError.conditionNotMet(
                details: "Connect an external display and try again."
            )
        }

        if scenario.conditions.onlyDuringCall,
           !windows.contains(where: { role(of: $0) == .meeting }) {
            throw PaneCueWindowError.conditionNotMet(
                details: "Start or open a call window and try again."
            )
        }

        var selected: [(slot: ScenarioWindowSlot, window: ManagedWindow)] = []
        for slot in scenario.windows {
            let candidates = windows.filter { window in
                target(slot.target, matches: window)
                    && !selected.contains(where: {
                        sameWindow($0.window, window)
                    })
            }
            guard let window = preferredWindow(
                among: candidates,
                frontmostPID: frontmostPID
            ) else {
                throw PaneCueWindowError.requiredRoleMissing(
                    role: slot.target.displayName,
                    examples: "Open another matching window or edit this scenario"
                )
            }
            selected.append((slot, window))
        }

        guard let mainFrame = ScreenGeometry
            .visibleFrameInAccessibilityCoordinates(for: .main) else {
            throw PaneCueWindowError.noUsableScreen
        }
        let externalFrame = ScreenGeometry
            .visibleFrameInAccessibilityCoordinates(for: .external)

        restoreActiveLayoutBeforeApplying()

        let snapshot = selected.map { selection in
            WindowSnapshot(
                element: selection.window.element,
                applicationName: selection.window.applicationName,
                title: selection.window.title,
                frame: selection.window.frame,
                isMinimized: selection.window.isMinimized,
                isFullScreen: selection.window.isFullScreen
            )
        }

        do {
            for selection in selected {
                let window = selection.window
                let screenFrame = selection.slot.display == .external
                    ? (externalFrame ?? mainFrame)
                    : mainFrame
                let targetFrame = LayoutPlanner.frame(
                    for: selection.slot.gridRect,
                    in: screenFrame
                )

                AXHelpers.setMinimized(false, on: window.element)
                try leaveFullScreenIfNeeded(window)
                try AXHelpers.setFrame(targetFrame, on: window.element)
            }

            for selection in selected.reversed() {
                AXHelpers.raise(selection.window.element)
            }

            activeSnapshot = snapshot
            activeScenarioName = scenario.name
            let names = selected.map(\.window.applicationName)
                .joined(separator: " + ")
            logger.info(
                "Applied \(scenario.name, privacy: .public) to \(selected.count, privacy: .public) windows"
            )
            return "\(scenario.name) · \(names)"
        } catch {
            restore(snapshot, clearingOnCompletion: false)
            throw error
        }
    }

    public func restorePreviousLayout() throws -> String {
        guard let snapshot = activeSnapshot else {
            throw PaneCueWindowError.noSnapshot
        }

        let failures = restore(snapshot, clearingOnCompletion: true)
        activeScenarioName = nil
        if failures.isEmpty {
            return "Previous layout restored"
        }

        throw PaneCueWindowError.operationFailed(
            details: "PaneCue restored the available windows, but \(failures.count) window(s) were unavailable. The old snapshot was cleared."
        )
    }

    private func windows(for application: NSRunningApplication) -> [ManagedWindow] {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let elements = AXHelpers.copyElements(
            from: applicationElement,
            attribute: kAXWindowsAttribute as CFString
        )

        return elements.compactMap { windowElement in
            guard let frame = AXHelpers.frame(of: windowElement) else {
                return nil
            }

            guard frame.width >= 200, frame.height >= 140 else {
                return nil
            }

            let role = AXHelpers.copyString(
                from: windowElement,
                attribute: kAXRoleAttribute as CFString
            )
            guard role == (kAXWindowRole as String) else {
                return nil
            }

            let title = AXHelpers.copyString(
                from: windowElement,
                attribute: kAXTitleAttribute as CFString
            ) ?? "Untitled Window"

            let minimized = AXHelpers.copyBool(
                from: windowElement,
                attribute: kAXMinimizedAttribute as CFString
            ) ?? false

            let fullScreen = AXHelpers.copyBool(
                from: windowElement,
                attribute: AXHelpers.fullScreenAttribute
            ) ?? false

            return ManagedWindow(
                element: windowElement,
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.localizedName ?? application.bundleIdentifier ?? "Application",
                title: title,
                frame: frame,
                isMinimized: minimized,
                isFullScreen: fullScreen
            )
        }
    }

    private func role(of window: ManagedWindow) -> ApplicationRole {
        ApplicationRoleClassifier.role(
            bundleIdentifier: window.bundleIdentifier,
            applicationName: window.applicationName,
            windowTitle: window.title
        )
    }

    private func target(
        _ target: ScenarioWindowTarget,
        matches window: ManagedWindow
    ) -> Bool {
        switch target.kind {
        case .application:
            guard let identifier = target.application?.bundleIdentifier else {
                return false
            }
            return window.bundleIdentifier?.caseInsensitiveCompare(
                identifier
            ) == .orderedSame
        case .role:
            return role(of: window) == (target.role ?? .other)
        }
    }

    private func sameWindow(
        _ first: ManagedWindow,
        _ second: ManagedWindow
    ) -> Bool {
        first.processIdentifier == second.processIdentifier
            && CFEqual(first.element, second.element)
    }

    private func preferredWindow(
        among windows: [ManagedWindow],
        frontmostPID: pid_t?
    ) -> ManagedWindow? {
        windows.max { left, right in
            windowPriority(left, frontmostPID: frontmostPID)
                < windowPriority(right, frontmostPID: frontmostPID)
        }
    }

    private func preferredMeetingWindow(
        among windows: [ManagedWindow],
        frontmostPID: pid_t?
    ) -> ManagedWindow? {
        windows.max { left, right in
            meetingWindowPriority(left, frontmostPID: frontmostPID)
                < meetingWindowPriority(right, frontmostPID: frontmostPID)
        }
    }

    private func windowPriority(
        _ window: ManagedWindow,
        frontmostPID: pid_t?
    ) -> Double {
        let frontmostBonus = window.processIdentifier == frontmostPID ? 1_000_000_000.0 : 0
        let visibleBonus = window.isMinimized ? 0 : 100_000_000.0
        return frontmostBonus + visibleBonus + Double(window.area)
    }

    private func meetingWindowPriority(
        _ window: ManagedWindow,
        frontmostPID: pid_t?
    ) -> Double {
        let title = window.title.lowercased()
        let meetingTitleMarkers = [
            "meeting",
            "meet",
            "call",
            "facetime",
            "zoom"
        ]
        let titleBonus = meetingTitleMarkers.contains(where: title.contains)
            ? 10_000_000_000.0
            : 0
        return titleBonus + windowPriority(window, frontmostPID: frontmostPID)
    }

    private func applyPairLayout(
        primary: ManagedWindow,
        secondary: ManagedWindow,
        visibleFrame: CGRect,
        primaryRatio: CGFloat = 0.65,
        scenarioName: String,
        summary: String
    ) throws -> String {
        let snapshot = [primary, secondary].map { window in
            WindowSnapshot(
                element: window.element,
                applicationName: window.applicationName,
                title: window.title,
                frame: window.frame,
                isMinimized: window.isMinimized,
                isFullScreen: window.isFullScreen
            )
        }
        let layout = LayoutPlanner.sideBySide(
            in: visibleFrame,
            primaryRatio: primaryRatio
        )

        do {
            AXHelpers.setMinimized(false, on: primary.element)
            AXHelpers.setMinimized(false, on: secondary.element)
            try leaveFullScreenIfNeeded(primary)
            try leaveFullScreenIfNeeded(secondary)
            try AXHelpers.setFrame(layout.primary, on: primary.element)
            try AXHelpers.setFrame(layout.secondary, on: secondary.element)
            AXHelpers.raise(secondary.element)
            AXHelpers.raise(primary.element)

            activeSnapshot = snapshot
            activeScenarioName = scenarioName
            logger.info(
                "Applied \(scenarioName, privacy: .public) to \(primary.applicationName, privacy: .public) and \(secondary.applicationName, privacy: .public)"
            )
            return summary
        } catch {
            restore(snapshot, clearingOnCompletion: false)
            throw error
        }
    }

    private func restoreActiveLayoutBeforeApplying() {
        guard let snapshot = activeSnapshot else {
            return
        }

        let failures = restore(snapshot, clearingOnCompletion: true)
        activeScenarioName = nil

        if !failures.isEmpty {
            logger.warning(
                "Discarded a stale scenario snapshot after \(failures.count, privacy: .public) restoration failure(s)"
            )
        }
    }

    private func leaveFullScreenIfNeeded(_ window: ManagedWindow) throws {
        guard window.isFullScreen else {
            return
        }

        try AXHelpers.setFullScreen(false, on: window.element)
        try waitForFullScreenState(
            false,
            on: window.element,
            applicationName: window.applicationName
        )
    }

    private func waitForFullScreenState(
        _ expectedState: Bool,
        on element: AXUIElement,
        applicationName: String
    ) throws {
        let deadline = Date(timeIntervalSinceNow: 2)

        while Date() < deadline {
            let currentState = AXHelpers.copyBool(
                from: element,
                attribute: AXHelpers.fullScreenAttribute
            ) ?? false
            if currentState == expectedState {
                return
            }

            RunLoop.current.run(
                until: Date(timeIntervalSinceNow: 0.05)
            )
        }

        throw PaneCueWindowError.operationFailed(
            details: "\(applicationName) did not finish changing fullscreen mode."
        )
    }

    @discardableResult
    private func restore(
        _ snapshot: [WindowSnapshot],
        clearingOnCompletion: Bool
    ) -> [Error] {
        var failures: [Error] = []

        for window in snapshot {
            do {
                AXHelpers.setMinimized(false, on: window.element)

                let currentlyFullScreen = AXHelpers.copyBool(
                    from: window.element,
                    attribute: AXHelpers.fullScreenAttribute
                ) ?? false

                if window.isFullScreen {
                    if !currentlyFullScreen {
                        try AXHelpers.setFullScreen(true, on: window.element)
                        try waitForFullScreenState(
                            true,
                            on: window.element,
                            applicationName: window.applicationName
                        )
                    }
                } else {
                    if currentlyFullScreen {
                        try AXHelpers.setFullScreen(false, on: window.element)
                        try waitForFullScreenState(
                            false,
                            on: window.element,
                            applicationName: window.applicationName
                        )
                    }
                    try AXHelpers.setFrame(window.frame, on: window.element)
                }

                AXHelpers.setMinimized(window.isMinimized, on: window.element)
            } catch {
                failures.append(error)
                logger.error(
                    "Could not restore \(window.applicationName, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if clearingOnCompletion {
            activeSnapshot = nil
        }

        return failures
    }
}
