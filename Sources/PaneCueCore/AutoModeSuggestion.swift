import Foundation

public enum AutoModeScenario: String, CaseIterable, Hashable, Sendable {
    case codeAndCall
    case documentationAndCode
    case notesAndBrowser

    public var title: String {
        switch self {
        case .codeAndCall:
            return "Code + Call"
        case .documentationAndCode:
            return "Documentation + Code"
        case .notesAndBrowser:
            return "Notes + Browser"
        }
    }

    public var action: VoiceCommandAction {
        switch self {
        case .codeAndCall:
            return .applyCodeAndCall
        case .documentationAndCode:
            return .applyDocumentationAndCode
        case .notesAndBrowser:
            return .applyNotesAndBrowser
        }
    }
}

public struct AutoModeWindowContext: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let applicationName: String
    public let role: ApplicationRole
    public let isMinimized: Bool
    public let isFullScreen: Bool

    public init(
        processIdentifier: pid_t,
        applicationName: String,
        role: ApplicationRole,
        isMinimized: Bool = false,
        isFullScreen: Bool = false
    ) {
        self.processIdentifier = processIdentifier
        self.applicationName = applicationName
        self.role = role
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
    }
}

public struct AutoModeWorkspaceContext: Equatable, Sendable {
    public let windows: [AutoModeWindowContext]
    public let frontmostProcessIdentifier: pid_t?
    public let previousActiveRole: ApplicationRole?

    public init(
        windows: [AutoModeWindowContext],
        frontmostProcessIdentifier: pid_t?,
        previousActiveRole: ApplicationRole? = nil
    ) {
        self.windows = windows
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.previousActiveRole = previousActiveRole
    }
}

public struct AutoModeSuggestion: Equatable, Sendable {
    public let scenario: AutoModeScenario
    public let reason: String

    public init(
        scenario: AutoModeScenario,
        reason: String
    ) {
        self.scenario = scenario
        self.reason = reason
    }
}

public enum AutoModeSuggestionEngine {
    public static func suggestion(
        for context: AutoModeWorkspaceContext
    ) -> AutoModeSuggestion? {
        let windows = context.windows.filter { !$0.isMinimized }
        guard !windows.isEmpty else {
            return nil
        }

        let activeWindows = windows.filter {
            $0.processIdentifier == context.frontmostProcessIdentifier
        }

        let activeRole = preferredActiveRole(in: activeWindows)
        let ide = preferredWindow(role: .ide, in: windows)
        let meeting = preferredWindow(role: .meeting, in: windows)
        let browser = preferredWindow(role: .browser, in: windows)
        let notes = preferredWindow(role: .notes, in: windows)
        let documentation = preferredWindow(
            role: .documentation,
            in: windows
        )

        if let ide,
           let meeting,
           activeRole == .ide || activeRole == .meeting {
            return AutoModeSuggestion(
                scenario: .codeAndCall,
                reason: "\(ide.applicationName) and \(meeting.applicationName) are active."
            )
        }

        if activeRole == .notes,
           let notes,
           let browser {
            return AutoModeSuggestion(
                scenario: .notesAndBrowser,
                reason: "\(notes.applicationName) is being used with \(browser.applicationName)."
            )
        }

        if activeRole == .ide,
           let ide,
           let reference = documentation ?? browser {
            return AutoModeSuggestion(
                scenario: .documentationAndCode,
                reason: "\(ide.applicationName) is being used with \(reference.applicationName)."
            )
        }

        if activeRole == .documentation,
           let documentation,
           let ide {
            return AutoModeSuggestion(
                scenario: .documentationAndCode,
                reason: "\(documentation.applicationName) is open beside \(ide.applicationName)."
            )
        }

        if activeRole == .browser,
           let browser {
            switch context.previousActiveRole {
            case .notes:
                if let notes {
                    return AutoModeSuggestion(
                        scenario: .notesAndBrowser,
                        reason: "You switched between \(notes.applicationName) and \(browser.applicationName)."
                    )
                }
            case .ide, .documentation:
                if let ide {
                    return AutoModeSuggestion(
                        scenario: .documentationAndCode,
                        reason: "You switched between \(ide.applicationName) and \(browser.applicationName)."
                    )
                }
            default:
                break
            }

            if let ide, notes == nil {
                return AutoModeSuggestion(
                    scenario: .documentationAndCode,
                    reason: "\(browser.applicationName) is the only reference app open with \(ide.applicationName)."
                )
            }

            if let notes, ide == nil {
                return AutoModeSuggestion(
                    scenario: .notesAndBrowser,
                    reason: "\(browser.applicationName) is being used with \(notes.applicationName)."
                )
            }
        }

        return nil
    }

    public static func activeRole(
        for context: AutoModeWorkspaceContext
    ) -> ApplicationRole? {
        preferredActiveRole(
            in: context.windows.filter {
                !$0.isMinimized
                    && $0.processIdentifier
                        == context.frontmostProcessIdentifier
            }
        )
    }

    private static func preferredWindow(
        role: ApplicationRole,
        in windows: [AutoModeWindowContext]
    ) -> AutoModeWindowContext? {
        windows.first { $0.role == role }
    }

    private static func preferredActiveRole(
        in windows: [AutoModeWindowContext]
    ) -> ApplicationRole? {
        let priority: [ApplicationRole] = [
            .meeting,
            .ide,
            .notes,
            .documentation,
            .browser,
            .other
        ]
        return priority.first { role in
            windows.contains { $0.role == role }
        }
    }
}
