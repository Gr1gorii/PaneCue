import Foundation

public enum ApplicationRole: String, Codable, Sendable, Hashable, CaseIterable {
    case ide
    case meeting
    case browser
    case notes
    case documentation
    case other

    public var displayName: String {
        switch self {
        case .ide:
            return "Any IDE"
        case .meeting:
            return "Any meeting app"
        case .browser:
            return "Any browser"
        case .notes:
            return "Any notes app"
        case .documentation:
            return "Any documentation app"
        case .other:
            return "Any other app"
        }
    }
}

public enum ApplicationRoleClassifier {
    private static let exactIDEIdentifiers: Set<String> = [
        "com.apple.dt.xcode",
        "com.microsoft.vscode",
        "com.microsoft.vscodeinsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf",
        "com.sublimetext.4",
        "dev.zed.zed",
        "com.panic.nova"
    ]

    private static let ideIdentifierPrefixes = [
        "com.jetbrains."
    ]

    private static let exactMeetingIdentifiers: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.webex.meetingmanager",
        "com.skype.skype",
        "com.apple.facetime"
    ]

    private static let exactBrowserIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox"
    ]

    private static let exactNotesIdentifiers: Set<String> = [
        "com.apple.notes",
        "notion.id",
        "md.obsidian",
        "net.shinyfrog.bear",
        "com.evernote.evernote",
        "com.lukilabs.lukiapp",
        "com.microsoft.onenote.mac",
        "com.agiletortoise.drafts-osx"
    ]

    private static let exactDocumentationIdentifiers: Set<String> = [
        "com.apple.preview",
        "com.kapeli.dashdoc",
        "com.apple.helpviewer",
        "com.apple.books"
    ]

    private static let ideNameMarkers = [
        "xcode",
        "visual studio code",
        "cursor",
        "windsurf",
        "intellij idea",
        "pycharm",
        "webstorm",
        "phpstorm",
        "rubymine",
        "clion",
        "goland",
        "rider",
        "android studio",
        "sublime text",
        "zed",
        "nova"
    ]

    private static let meetingNameMarkers = [
        "zoom",
        "microsoft teams",
        "webex",
        "skype",
        "facetime"
    ]

    private static let notesNameMarkers = [
        "notes",
        "notion",
        "obsidian",
        "bear",
        "evernote",
        "craft",
        "onenote",
        "drafts"
    ]

    private static let documentationNameMarkers = [
        "preview",
        "dash",
        "help viewer",
        "books"
    ]

    private static let browserMeetingTitleMarkers = [
        "google meet",
        "meet - ",
        "meet – ",
        "zoom meeting",
        "microsoft teams meeting",
        "whereby",
        "around meeting",
        "webex meeting",
        "riverside"
    ]

    public static func role(
        bundleIdentifier: String?,
        applicationName: String,
        windowTitle: String
    ) -> ApplicationRole {
        let identifier = bundleIdentifier?.lowercased() ?? ""
        let name = applicationName.lowercased()
        let title = windowTitle.lowercased()

        if exactMeetingIdentifiers.contains(identifier)
            || meetingNameMarkers.contains(where: name.contains) {
            return .meeting
        }

        let isBrowser = exactBrowserIdentifiers.contains(identifier)
        if isBrowser,
           browserMeetingTitleMarkers.contains(where: title.contains) {
            return .meeting
        }

        if exactIDEIdentifiers.contains(identifier)
            || ideIdentifierPrefixes.contains(where: identifier.hasPrefix)
            || ideNameMarkers.contains(where: name.contains) {
            return .ide
        }

        if exactNotesIdentifiers.contains(identifier)
            || notesNameMarkers.contains(where: name.contains) {
            return .notes
        }

        if exactDocumentationIdentifiers.contains(identifier)
            || documentationNameMarkers.contains(where: name.contains) {
            return .documentation
        }

        return isBrowser ? .browser : .other
    }
}
