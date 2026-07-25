import AppKit
import CoreGraphics

public enum ScreenGeometry {
    public static func appKitRectToAccessibility(
        _ rect: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    @MainActor
    public static func primaryVisibleFrameInAccessibilityCoordinates() -> CGRect? {
        visibleFrameInAccessibilityCoordinates(for: .main)
    }

    @MainActor
    public static var hasExternalDisplay: Bool {
        NSScreen.screens.count > 1
    }

    @MainActor
    public static func visibleFrameInAccessibilityCoordinates(
        for target: ScenarioDisplayTarget
    ) -> CGRect? {
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else {
            return nil
        }

        let selectedScreen: NSScreen
        switch target {
        case .main:
            selectedScreen = primaryScreen
        case .external:
            guard screens.count > 1 else {
                return nil
            }
            selectedScreen = screens[1]
        }

        return appKitRectToAccessibility(
            selectedScreen.visibleFrame,
            primaryScreenFrame: primaryScreen.frame
        )
    }
}
