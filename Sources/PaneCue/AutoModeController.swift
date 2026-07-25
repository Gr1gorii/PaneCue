import AppKit
import OSLog
import PaneCueCore

@MainActor
final class AutoModeController: NSObject {
    private static let enabledKey = "PaneCue.autoMode.isEnabled"

    private let windowManager: WindowManager
    private let defaults: UserDefaults
    private let shouldPresentSuggestion: () -> Bool
    private let suggestionHandler: (AutoModeSuggestion) -> Void
    private let enabledDidChange: (Bool) -> Void
    private let workspaceNotificationCenter =
        NSWorkspace.shared.notificationCenter
    private let logger = Logger(
        subsystem: PaneCueIdentity.bundleIdentifier,
        category: "AutoMode"
    )

    private var isStarted = false
    private var evaluationTask: Task<Void, Never>?
    private var timer: Timer?
    private var lastActivatedApplicationPID: pid_t?
    private var lastFrontmostPID: pid_t?
    private var lastActiveRole: ApplicationRole?
    private var previousRoleForCurrentActivation: ApplicationRole?
    private var cooldownUntilByScenario: [AutoModeScenario: Date] = [:]
    private var globalPauseUntil = Date.distantPast

    private(set) var isEnabled: Bool

    init(
        windowManager: WindowManager,
        defaults: UserDefaults = .standard,
        shouldPresentSuggestion: @escaping () -> Bool,
        suggestionHandler: @escaping (AutoModeSuggestion) -> Void,
        enabledDidChange: @escaping (Bool) -> Void
    ) {
        self.windowManager = windowManager
        self.defaults = defaults
        self.shouldPresentSuggestion = shouldPresentSuggestion
        self.suggestionHandler = suggestionHandler
        self.enabledDidChange = enabledDidChange
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        super.init()
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        let notifications: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]
        for name in notifications {
            workspaceNotificationCenter.addObserver(
                self,
                selector: #selector(workspaceDidChange),
                name: name,
                object: nil
            )
        }

        timer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(periodicEvaluation),
            userInfo: nil,
            repeats: true
        )

        if isEnabled {
            scheduleEvaluation(after: .seconds(1))
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }

        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        evaluationTask?.cancel()

        if enabled {
            globalPauseUntil = Date.distantPast
            scheduleEvaluation(after: .milliseconds(700))
        }

        enabledDidChange(enabled)
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func dismiss(_ suggestion: AutoModeSuggestion) {
        cooldownUntilByScenario[suggestion.scenario] =
            Date().addingTimeInterval(10 * 60)
    }

    func markApplied(_ suggestion: AutoModeSuggestion) {
        cooldownUntilByScenario[suggestion.scenario] =
            Date().addingTimeInterval(5 * 60)
        pauseSuggestions(for: 60)
    }

    func pauseSuggestions(for seconds: TimeInterval) {
        globalPauseUntil = max(
            globalPauseUntil,
            Date().addingTimeInterval(seconds)
        )
        evaluationTask?.cancel()
    }

    func workspaceMayHaveChanged() {
        scheduleEvaluation(after: .seconds(1))
    }

    @objc
    private func workspaceDidChange(_ notification: Notification) {
        if notification.name
            == NSWorkspace.didActivateApplicationNotification,
           let application = notification.userInfo?[
               NSWorkspace.applicationUserInfoKey
           ] as? NSRunningApplication,
           application.activationPolicy == .regular,
           application.processIdentifier
               != ProcessInfo.processInfo.processIdentifier {
            lastActivatedApplicationPID =
                application.processIdentifier
        }
        scheduleEvaluation(after: .milliseconds(700))
    }

    @objc
    private func periodicEvaluation() {
        scheduleEvaluation(after: .milliseconds(100))
    }

    private func scheduleEvaluation(
        after delay: Duration
    ) {
        guard isEnabled else {
            return
        }

        evaluationTask?.cancel()
        evaluationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.evaluateWorkspace()
        }
    }

    private func evaluateWorkspace() {
        guard isEnabled else {
            return
        }
        guard Date() >= globalPauseUntil else {
            logger.debug("Skipping evaluation during the global cooldown")
            return
        }
        guard shouldPresentSuggestion() else {
            logger.debug("Skipping evaluation while another PaneCue action is active")
            return
        }
        guard windowManager.hasAccessibilityPermission else {
            logger.debug("Skipping evaluation without Accessibility access")
            return
        }

        let windows: [ManagedWindow]
        do {
            windows = try windowManager.eligibleWindows()
        } catch {
            logger.error(
                "Could not inspect windows: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        let windowContexts = windows.map { window in
            AutoModeWindowContext(
                processIdentifier: window.processIdentifier,
                applicationName: window.applicationName,
                role: ApplicationRoleClassifier.role(
                    bundleIdentifier: window.bundleIdentifier,
                    applicationName: window.applicationName,
                    windowTitle: window.title
                ),
                isMinimized: window.isMinimized,
                isFullScreen: window.isFullScreen
            )
        }
        let eligiblePIDs = Set(
            windowContexts.map(\.processIdentifier)
        )
        let workspaceFrontmostPID =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostPID: pid_t?
        if let workspaceFrontmostPID,
           eligiblePIDs.contains(workspaceFrontmostPID) {
            frontmostPID = workspaceFrontmostPID
        } else if let lastActivatedApplicationPID,
                  eligiblePIDs.contains(lastActivatedApplicationPID) {
            frontmostPID = lastActivatedApplicationPID
        } else {
            frontmostPID = nil
        }

        let baseContext = AutoModeWorkspaceContext(
            windows: windowContexts,
            frontmostProcessIdentifier: frontmostPID
        )
        let currentRole = AutoModeSuggestionEngine.activeRole(
            for: baseContext
        )

        if frontmostPID != lastFrontmostPID {
            previousRoleForCurrentActivation = lastActiveRole
            lastFrontmostPID = frontmostPID
        }
        lastActiveRole = currentRole

        let context = AutoModeWorkspaceContext(
            windows: windowContexts,
            frontmostProcessIdentifier: frontmostPID,
            previousActiveRole: previousRoleForCurrentActivation
        )
        guard let suggestion = AutoModeSuggestionEngine.suggestion(
            for: context
        ) else {
            logger.debug(
                "No suggestion for \(windowContexts.count, privacy: .public) eligible windows; active role: \(String(describing: currentRole), privacy: .public)"
            )
            return
        }

        let cooldownUntil =
            cooldownUntilByScenario[suggestion.scenario]
                ?? Date.distantPast
        guard Date() >= cooldownUntil else {
            logger.debug(
                "Skipping \(suggestion.scenario.title, privacy: .public) during its cooldown"
            )
            return
        }

        logger.info(
            "Suggesting \(suggestion.scenario.title, privacy: .public)"
        )
        cooldownUntilByScenario[suggestion.scenario] =
            Date().addingTimeInterval(2 * 60)
        suggestionHandler(suggestion)
    }
}
