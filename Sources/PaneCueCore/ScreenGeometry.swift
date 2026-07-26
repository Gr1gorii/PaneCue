import AppKit
import CoreGraphics

public enum ScreenGeometry {
    public static func containedFrame(
        _ frame: CGRect,
        in visibleFrame: CGRect
    ) -> CGRect {
        let fittedSize = CGSize(
            width: min(frame.width, visibleFrame.width),
            height: min(frame.height, visibleFrame.height)
        )
        return CGRect(
            x: min(
                max(frame.minX, visibleFrame.minX),
                visibleFrame.maxX - fittedSize.width
            ),
            y: min(
                max(frame.minY, visibleFrame.minY),
                visibleFrame.maxY - fittedSize.height
            ),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    public static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    public static func centeredFrame(
        windowSize: CGSize,
        in visibleFrame: CGRect
    ) -> CGRect {
        let fittedSize = CGSize(
            width: min(windowSize.width, visibleFrame.width),
            height: min(windowSize.height, visibleFrame.height)
        )
        return CGRect(
            x: visibleFrame.minX
                + (visibleFrame.width - fittedSize.width) / 2,
            y: visibleFrame.minY
                + (visibleFrame.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

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
