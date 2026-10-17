import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

enum AXHelpers {
    private static let zoomMenuIdentifiers: Set<String> = [
        "performZoom:",
        "Zoom",
    ]

    private struct MoveAndResizeMenuAccess {
        let menu: AXUIElement
    }

    static var fullScreenAttribute: CFString {
        "AXFullScreen" as CFString
    }

    static func copyValue(
        from element: AXUIElement,
        attribute: CFString
    ) -> CFTypeRef? {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &rawValue)
        guard error == .success else {
            return nil
        }
        return rawValue
    }

    static func copyString(
        from element: AXUIElement,
        attribute: CFString
    ) -> String? {
        copyValue(from: element, attribute: attribute) as? String
    }

    static func copyBool(
        from element: AXUIElement,
        attribute: CFString
    ) -> Bool? {
        copyValue(from: element, attribute: attribute) as? Bool
    }

    static func copyElements(
        from element: AXUIElement,
        attribute: CFString
    ) -> [AXUIElement] {
        copyValue(from: element, attribute: attribute) as? [AXUIElement] ?? []
    }

    static func copyElement(
        from element: AXUIElement,
        attribute: CFString
    ) -> AXUIElement? {
        guard let rawValue = copyValue(
            from: element,
            attribute: attribute
        ), CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(rawValue, to: AXUIElement.self)
    }

    static func copyPoint(
        from element: AXUIElement,
        attribute: CFString
    ) -> CGPoint? {
        guard let rawValue = copyValue(from: element, attribute: attribute) else {
            return nil
        }

        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    static func copySize(
        from element: AXUIElement,
        attribute: CFString
    ) -> CGSize? {
        guard let rawValue = copyValue(from: element, attribute: attribute) else {
            return nil
        }

        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard
            let position = copyPoint(
                from: element,
                attribute: kAXPositionAttribute as CFString
            ),
            let size = copySize(
                from: element,
                attribute: kAXSizeAttribute as CFString
            )
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    static func setFrame(
        _ frame: CGRect,
        on element: AXUIElement
    ) throws {
        guard
            isSettable(element, attribute: kAXPositionAttribute as CFString),
            isSettable(element, attribute: kAXSizeAttribute as CFString)
        else {
            throw PaneCueWindowError.operationFailed(
                details: "The target window does not expose settable position and size attributes."
            )
        }

        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw PaneCueWindowError.operationFailed(details: "Could not encode the target window size.")
        }

        var position = frame.origin
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw PaneCueWindowError.operationFailed(details: "Could not encode the target window position.")
        }

        let currentSize = copySize(
            from: element,
            attribute: kAXSizeAttribute as CFString
        )
        let shouldShrinkFirst = currentSize.map {
            frame.width < $0.width || frame.height < $0.height
        } ?? false

        func applyPosition() throws {
            let error = AXUIElementSetAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                positionValue
            )
            guard error == .success else {
                throw PaneCueWindowError.operationFailed(
                    details: "The target application rejected the requested window position (\(error.rawValue))."
                )
            }
        }

        func applySize() throws {
            let error = AXUIElementSetAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                sizeValue
            )
            guard error == .success else {
                throw PaneCueWindowError.operationFailed(
                    details: "The target application rejected the requested window size (\(error.rawValue))."
                )
            }
        }

        if shouldShrinkFirst {
            try applySize()
            try applyPosition()
        } else {
            // Move first when growing so applications do not clamp the new
            // size against the window's old screen edge.
            try applyPosition()
            try applySize()
        }

        // Some apps reconcile their constraints after the first change.
        // Reapply once in the same edge-safe order, without looping.
        if shouldShrinkFirst {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                sizeValue
            )
            _ = AXUIElementSetAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                positionValue
            )
        } else {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                positionValue
            )
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                sizeValue
            )
        }
        // A managed or previously filled window can accept the size while
        // snapping back to its old edge. Make position the final authority.
        _ = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            positionValue
        )
    }

    static func canSetFrame(on element: AXUIElement) -> Bool {
        isSettable(
            element,
            attribute: kAXPositionAttribute as CFString
        ) && isSettable(
            element,
            attribute: kAXSizeAttribute as CFString
        )
    }

    static func setPosition(
        _ position: CGPoint,
        on element: AXUIElement
    ) throws {
        guard isSettable(
            element,
            attribute: kAXPositionAttribute as CFString
        ) else {
            throw PaneCueWindowError.operationFailed(
                details: "The target window does not expose a settable position attribute."
            )
        }

        var position = position
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw PaneCueWindowError.operationFailed(
                details: "Could not encode the target window position."
            )
        }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            positionValue
        )
        guard error == .success else {
            throw PaneCueWindowError.operationFailed(
                details: "The target application rejected the requested window position (\(error.rawValue))."
            )
        }
    }

    static func setMinimized(
        _ minimized: Bool,
        on element: AXUIElement
    ) {
        guard isSettable(element, attribute: kAXMinimizedAttribute as CFString) else {
            return
        }

        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        _ = AXUIElementSetAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            value
        )
    }

    static func setFullScreen(
        _ fullScreen: Bool,
        on element: AXUIElement
    ) throws {
        guard isSettable(element, attribute: fullScreenAttribute) else {
            throw PaneCueWindowError.operationFailed(
                details: "The target window does not allow PaneCue to change fullscreen mode."
            )
        }

        let value: CFBoolean = fullScreen ? kCFBooleanTrue : kCFBooleanFalse
        let error = AXUIElementSetAttributeValue(
            element,
            fullScreenAttribute,
            value
        )
        guard error == .success else {
            throw PaneCueWindowError.operationFailed(
                details: "The target application rejected the fullscreen change (\(error.rawValue))."
            )
        }
    }

    static func raise(_ element: AXUIElement) {
        _ = AXUIElementPerformAction(
            element,
            kAXRaiseAction as CFString
        )
    }

    static func performSystemPlacement(
        _ placement: SystemWindowPlacement,
        on window: AXUIElement
    ) -> Bool {
        focus(window)
        Thread.sleep(forTimeInterval: 0.12)
        guard let menuAccess = moveAndResizeMenu(for: window) else {
            return false
        }

        let menu = menuAccess.menu

        let items = meaningfulMenuItems(from: menu)
        let enabledStates = items.map(isEnabled)
        guard SystemWindowMoveResizeMenu.hasExpectedTopology(
            enabledStates: enabledStates
        ), items.indices.contains(placement.moveResizeMenuIndex) else {
            cancelMenu(menu)
            return false
        }

        let item = items[placement.moveResizeMenuIndex]
        guard isEnabled(item) else {
            cancelMenu(menu)
            return false
        }

        let performed = performMenuSelection(on: item)
        if !performed {
            cancelMenu(menu)
        }
        return performed
    }

    static func performSystemFill(on window: AXUIElement) -> Bool {
        focus(window)
        Thread.sleep(forTimeInterval: 0.12)
        guard let windowMenu = openedWindowMenu(for: window) else {
            return false
        }

        let items = meaningfulMenuItems(from: windowMenu)
        guard let moveAndResizeIndex = moveAndResizeItemIndex(in: items) else {
            cancelMenu(windowMenu)
            return false
        }
        guard let fillIndex = SystemWindowMoveResizeMenu.fillIndex(
            beforeMoveAndResizeIndex: moveAndResizeIndex,
            itemCount: items.count
        ),
              isEnabled(items[fillIndex]) else {
            cancelMenu(windowMenu)
            return false
        }
        let performed = performMenuSelection(on: items[fillIndex])
        if !performed {
            cancelMenu(windowMenu)
        }
        return performed
    }

    static func performSystemZoom(on window: AXUIElement) -> Bool {
        focus(window)
        Thread.sleep(forTimeInterval: 0.12)
        guard let windowMenu = openedWindowMenu(for: window) else {
            return false
        }

        let items = meaningfulMenuItems(from: windowMenu)
        guard let zoomItem = items.first(where: {
            guard let identifier = copyString(
                from: $0,
                attribute: kAXIdentifierAttribute as CFString
            ) else {
                return false
            }
            return zoomMenuIdentifiers.contains(identifier)
        }), isEnabled(zoomItem) else {
            cancelMenu(windowMenu)
            return false
        }

        let performed = performMenuSelection(on: zoomItem)
        if !performed {
            cancelMenu(windowMenu)
        }
        return performed
    }

    static func performReturnToPreviousWindowSize(
        on window: AXUIElement
    ) -> Bool {
        focus(window)
        Thread.sleep(forTimeInterval: 0.12)
        guard let menuAccess = moveAndResizeMenu(for: window) else {
            return false
        }

        let menu = menuAccess.menu

        let items = meaningfulMenuItems(from: menu)
        let enabledStates = items.map(isEnabled)
        guard let previousSizeIndex = SystemWindowMoveResizeMenu
            .previousSizeIndex(enabledStates: enabledStates),
            items.indices.contains(previousSizeIndex) else {
            cancelMenu(menu)
            return false
        }

        let performed = performMenuSelection(on: items[previousSizeIndex])
        if !performed {
            cancelMenu(menu)
        }
        return performed
    }

    private static func moveAndResizeMenu(
        for window: AXUIElement
    ) -> MoveAndResizeMenuAccess? {
        var processIdentifier: pid_t = 0
        let pidResult = AXUIElementGetPid(
            window,
            &processIdentifier
        )
        guard pidResult == .success else {
            return nil
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        var menuBar: AXUIElement?
        for attempt in 0 ..< 4 {
            menuBar = copyElement(
                from: application,
                attribute: kAXMenuBarAttribute as CFString
            )
            if menuBar != nil {
                break
            }
            if attempt < 3 {
                Thread.sleep(forTimeInterval: 0.15)
            }
        }
        guard let menuBar else {
            return nil
        }

        guard let windowMenuBarItem = windowMenuBarItem(from: menuBar) else {
            return nil
        }
        let openedWindowMenu = openMenu(on: windowMenuBarItem)
        guard openedWindowMenu else {
            return nil
        }

        var moveAndResizeMenu: AXUIElement?
        for attempt in 0 ..< 6 {
            Thread.sleep(forTimeInterval: 0.15)
            moveAndResizeMenu = anchoredMoveAndResizeMenu(
                in: windowMenuBarItem
            ) ?? firstMoveAndResizeMenu(
                in: windowMenuBarItem,
                maximumDepth: 6
            ) ?? firstMoveAndResizeMenu(
                in: menuBar,
                maximumDepth: 6
            )
            if moveAndResizeMenu != nil || attempt == 5 {
                break
            }
        }
        guard let moveAndResizeMenu else {
            cancelMenu(windowMenuBarItem)
            return nil
        }
        return MoveAndResizeMenuAccess(menu: moveAndResizeMenu)
    }

    private static func openedWindowMenu(
        for window: AXUIElement
    ) -> AXUIElement? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(
            window,
            &processIdentifier
        ) == .success else {
            return nil
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        guard let menuBar = copyElement(
            from: application,
            attribute: kAXMenuBarAttribute as CFString
        ), let windowMenuBarItem = windowMenuBarItem(from: menuBar),
              openMenu(on: windowMenuBarItem) else {
            return nil
        }

        for attempt in 0 ..< 6 {
            Thread.sleep(forTimeInterval: 0.15)
            if let zoomItem = firstDescendant(
                of: windowMenuBarItem,
                identifiers: zoomMenuIdentifiers,
                maximumDepth: 6
            ), let windowMenu = copyElement(
                from: zoomItem,
                attribute: kAXParentAttribute as CFString
            ) {
                return windowMenu
            }
            if attempt == 5 {
                cancelMenu(windowMenuBarItem)
            }
        }
        return nil
    }

    private static func anchoredMoveAndResizeMenu(
        in windowMenuBarItem: AXUIElement
    ) -> AXUIElement? {
        guard let zoomItem = firstDescendant(
            of: windowMenuBarItem,
            identifiers: zoomMenuIdentifiers,
            maximumDepth: 6
        ), let windowMenu = copyElement(
            from: zoomItem,
            attribute: kAXParentAttribute as CFString
        ) else {
            return nil
        }

        let items = meaningfulMenuItems(from: windowMenu)
        guard let moveAndResizeIndex = moveAndResizeItemIndex(in: items) else {
            return nil
        }

        let moveAndResizeItem = items[moveAndResizeIndex]
        // AppKit exposes submenu descendants even while the submenu is still
        // hidden. Pressing one of those hidden Safari items reports success
        // without moving the window, so always open the submenu first.
        guard openMenu(on: moveAndResizeItem) else {
            return nil
        }
        Thread.sleep(forTimeInterval: 0.15)
        return firstMoveAndResizeMenu(
            in: moveAndResizeItem,
            maximumDepth: 3
        ) ?? firstMoveAndResizeMenu(
            in: windowMenu,
            maximumDepth: 4
        )
    }

    private static func moveAndResizeItemIndex(
        in items: [AXUIElement]
    ) -> Int? {
        items.firstIndex {
            firstMoveAndResizeMenu(
                in: $0,
                maximumDepth: 3
            ) != nil
        }
    }

    private static func windowMenuBarItem(
        from menuBar: AXUIElement
    ) -> AXUIElement? {
        let menuBarItems = copyMenuChildren(from: menuBar)
        guard menuBarItems.count >= 2 else {
            return nil
        }
        return menuBarItems[menuBarItems.index(
            menuBarItems.endIndex,
            offsetBy: -2
        )]
    }

    private static func firstDescendant(
        of element: AXUIElement,
        identifiers: Set<String>,
        maximumDepth: Int
    ) -> AXUIElement? {
        if let identifier = copyString(
            from: element,
            attribute: kAXIdentifierAttribute as CFString
        ), identifiers.contains(identifier) {
            return element
        }
        guard maximumDepth > 0 else {
            return nil
        }

        for child in copyMenuChildren(from: element) {
            if let match = firstDescendant(
                of: child,
                identifiers: identifiers,
                maximumDepth: maximumDepth - 1
            ) {
                return match
            }
        }
        return nil
    }

    private static func firstMoveAndResizeMenu(
        in element: AXUIElement,
        maximumDepth: Int
    ) -> AXUIElement? {
        let children = copyMenuChildren(from: element)
        let menuItems = meaningfulMenuItems(from: element)
        if SystemWindowMoveResizeMenu.hasExpectedTopology(
            enabledStates: menuItems.map(isEnabled)
        ) {
            return element
        }
        guard maximumDepth > 0 else {
            return nil
        }

        for child in children {
            if let match = firstMoveAndResizeMenu(
                in: child,
                maximumDepth: maximumDepth - 1
            ) {
                return match
            }
        }
        return nil
    }

    private static func meaningfulMenuItems(
        from element: AXUIElement
    ) -> [AXUIElement] {
        copyMenuChildren(from: element).filter {
            guard let title = copyString(
                from: $0,
                attribute: kAXTitleAttribute as CFString
            ) else {
                return false
            }
            return !title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }
    }

    private static func copyMenuChildren(
        from element: AXUIElement
    ) -> [AXUIElement] {
        let childAttributes: [CFString] = [
            kAXVisibleChildrenAttribute as CFString,
            kAXChildrenAttribute as CFString,
            "AXChildrenInNavigationOrder" as CFString,
        ]
        for attribute in childAttributes {
            let children = copyElements(
                from: element,
                attribute: attribute
            )
            if !children.isEmpty {
                return children
            }
        }
        return []
    }

    private static func performDefaultAction(
        on element: AXUIElement
    ) -> Bool {
        performAction(
            on: element,
            preferredActions: [
                kAXPickAction as String,
                kAXPressAction as String,
            ]
        )
    }

    private static func performMenuSelection(
        on element: AXUIElement
    ) -> Bool {
        performDefaultAction(on: element)
    }

    private static func openMenu(on element: AXUIElement) -> Bool {
        performAction(
            on: element,
            preferredActions: [
                kAXPickAction as String,
                kAXPressAction as String,
            ]
        )
    }

    private static func performAction(
        on element: AXUIElement,
        preferredActions: [String]
    ) -> Bool {
        var rawActionNames: CFArray?
        guard AXUIElementCopyActionNames(
            element,
            &rawActionNames
        ) == .success,
            let actionNames = rawActionNames as? [String] else {
            return false
        }

        guard let action = preferredActions.first(where: {
            actionNames.contains($0)
        }) else {
            return false
        }

        let result = AXUIElementPerformAction(
            element,
            action as CFString
        )
        return result == .success
    }

    private static func focus(_ window: AXUIElement) {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(
            window,
            &processIdentifier
        ) == .success else {
            raise(window)
            return
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        let runningApplication = NSRunningApplication(
            processIdentifier: processIdentifier
        )
        runningApplication?.unhide()
        let activationSucceeded = runningApplication?.activate(
            options: [.activateAllWindows]
        )
        let frontmostResult = AXUIElementSetAttributeValue(
            application,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        if activationSucceeded != true,
           frontmostResult != .success,
           let applicationURL = runningApplication?.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { _, _ in
            }
        }
        if isSettable(
            application,
            attribute: kAXFocusedWindowAttribute as CFString
        ) {
            _ = AXUIElementSetAttributeValue(
                application,
                kAXFocusedWindowAttribute as CFString,
                window
            )
        }
        raise(window)
        for attempt in 0 ..< 10 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == processIdentifier {
                break
            }
            if attempt < 9 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    private static func cancelMenu(_ element: AXUIElement) {
        _ = AXUIElementPerformAction(
            element,
            kAXCancelAction as CFString
        )
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        copyBool(
            from: element,
            attribute: kAXEnabledAttribute as CFString
        ) ?? false
    }

    private static func isSettable(
        _ element: AXUIElement,
        attribute: CFString
    ) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return error == .success && settable.boolValue
    }
}
