import ApplicationServices
import CoreGraphics

public struct ManagedWindow {
    public let element: AXUIElement
    public let processIdentifier: pid_t
    public let bundleIdentifier: String?
    public let applicationName: String
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool
    public let isFullScreen: Bool

    public var area: CGFloat {
        frame.width * frame.height
    }
}

public struct WindowSnapshot {
    public let element: AXUIElement
    public let applicationName: String
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool
    public let isFullScreen: Bool
}

public struct PairLayout: Equatable {
    public let primary: CGRect
    public let secondary: CGRect

    public init(primary: CGRect, secondary: CGRect) {
        self.primary = primary
        self.secondary = secondary
    }
}

public enum PaneCueWindowError: LocalizedError {
    case accessibilityPermissionRequired
    case notEnoughEligibleWindows(found: Int)
    case requiredRoleMissing(role: String, examples: String)
    case conditionNotMet(details: String)
    case noUsableScreen
    case noSnapshot
    case unsupportedWindow(application: String, title: String)
    case operationFailed(details: String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "PaneCue needs Accessibility access before it can arrange windows."
        case let .notEnoughEligibleWindows(found):
            return "PaneCue found \(found) eligible window(s). Keep two normal app windows open and try again."
        case let .requiredRoleMissing(role, examples):
            return "PaneCue could not find a \(role) window. Open \(examples), then try again."
        case let .conditionNotMet(details):
            return "This scenario is not available right now. \(details)"
        case .noUsableScreen:
            return "PaneCue could not determine a usable screen area."
        case .noSnapshot:
            return "There is no previous PaneCue layout to restore."
        case let .unsupportedWindow(application, title):
            return "\(application) does not allow PaneCue to move “\(title)”."
        case let .operationFailed(details):
            return details
        }
    }
}
