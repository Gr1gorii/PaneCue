import ApplicationServices
import CoreGraphics

enum AXHelpers {
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

        let sizeError = AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        guard sizeError == .success else {
            throw PaneCueWindowError.operationFailed(
                details: "The target application rejected the requested window size (\(sizeError.rawValue))."
            )
        }

        let positionError = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            positionValue
        )
        guard positionError == .success else {
            throw PaneCueWindowError.operationFailed(
                details: "The target application rejected the requested window position (\(positionError.rawValue))."
            )
        }

        // Some apps constrain size after the first move. Reapply once, without looping.
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

    private static func isSettable(
        _ element: AXUIElement,
        attribute: CFString
    ) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return error == .success && settable.boolValue
    }
}
