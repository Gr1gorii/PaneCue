import CoreGraphics

public enum ScenarioGridResizeHandle: String, CaseIterable, Sendable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading

    public var changesMinimumX: Bool {
        self == .topLeading || self == .leading || self == .bottomLeading
    }

    public var changesMaximumX: Bool {
        self == .topTrailing || self == .trailing || self == .bottomTrailing
    }

    public var changesMinimumY: Bool {
        self == .topLeading || self == .top || self == .topTrailing
    }

    public var changesMaximumY: Bool {
        self == .bottomLeading || self == .bottom || self == .bottomTrailing
    }
}

public enum ScenarioGridResolution {
    public static let columns = 24
    public static let rows = 16
    public static let majorLineInterval = 2
    public static let minimumWidth = 1.0 / 24.0
    public static let minimumHeight = 1.0 / 16.0
}

public enum ScenarioGridInteraction {
    public static func movedRect(
        from start: ScenarioGridRect,
        translation: CGSize,
        canvasSize: CGSize
    ) -> ScenarioGridRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return start
        }

        return ScenarioGridRect(
            x: clamp(
                start.x + translation.width / canvasSize.width,
                minimum: 0,
                maximum: 1 - start.width
            ),
            y: clamp(
                start.y + translation.height / canvasSize.height,
                minimum: 0,
                maximum: 1 - start.height
            ),
            width: start.width,
            height: start.height
        )
    }

    public static func resizedRect(
        from start: ScenarioGridRect,
        handle: ScenarioGridResizeHandle,
        translation: CGSize,
        canvasSize: CGSize,
        minimumWidth: Double = ScenarioGridResolution.minimumWidth,
        minimumHeight: Double = ScenarioGridResolution.minimumHeight
    ) -> ScenarioGridRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return start
        }

        let deltaX = translation.width / canvasSize.width
        let deltaY = translation.height / canvasSize.height
        var minimumX = start.x
        var maximumX = start.x + start.width
        var minimumY = start.y
        var maximumY = start.y + start.height

        if handle.changesMinimumX {
            minimumX = clamp(
                start.x + deltaX,
                minimum: 0,
                maximum: maximumX - minimumWidth
            )
        }
        if handle.changesMaximumX {
            maximumX = clamp(
                start.x + start.width + deltaX,
                minimum: minimumX + minimumWidth,
                maximum: 1
            )
        }
        if handle.changesMinimumY {
            minimumY = clamp(
                start.y + deltaY,
                minimum: 0,
                maximum: maximumY - minimumHeight
            )
        }
        if handle.changesMaximumY {
            maximumY = clamp(
                start.y + start.height + deltaY,
                minimum: minimumY + minimumHeight,
                maximum: 1
            )
        }

        return ScenarioGridRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    public static func snappedMovedRect(
        _ rect: ScenarioGridRect,
        columns: Int = ScenarioGridResolution.columns,
        rows: Int = ScenarioGridResolution.rows
    ) -> ScenarioGridRect {
        ScenarioGridRect(
            x: snap(rect.x, divisions: columns),
            y: snap(rect.y, divisions: rows),
            width: rect.width,
            height: rect.height
        )
    }

    public static func snappedResizedRect(
        _ rect: ScenarioGridRect,
        handle: ScenarioGridResizeHandle,
        columns: Int = ScenarioGridResolution.columns,
        rows: Int = ScenarioGridResolution.rows
    ) -> ScenarioGridRect {
        let minimumWidth = 1 / Double(max(columns, 1))
        let minimumHeight = 1 / Double(max(rows, 1))
        var minimumX = rect.x
        var maximumX = rect.x + rect.width
        var minimumY = rect.y
        var maximumY = rect.y + rect.height

        if handle.changesMinimumX {
            minimumX = min(
                snap(minimumX, divisions: columns),
                maximumX - minimumWidth
            )
        }
        if handle.changesMaximumX {
            maximumX = max(
                snap(maximumX, divisions: columns),
                minimumX + minimumWidth
            )
        }
        if handle.changesMinimumY {
            minimumY = min(
                snap(minimumY, divisions: rows),
                maximumY - minimumHeight
            )
        }
        if handle.changesMaximumY {
            maximumY = max(
                snap(maximumY, divisions: rows),
                minimumY + minimumHeight
            )
        }

        minimumX = clamp(minimumX, minimum: 0, maximum: 1)
        maximumX = clamp(maximumX, minimum: 0, maximum: 1)
        minimumY = clamp(minimumY, minimum: 0, maximum: 1)
        maximumY = clamp(maximumY, minimum: 0, maximum: 1)

        return ScenarioGridRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    private static func snap(
        _ value: Double,
        divisions: Int
    ) -> Double {
        let safeDivisions = max(divisions, 1)
        let step = 1 / Double(safeDivisions)
        return (value / step).rounded() * step
    }

    private static func clamp(
        _ value: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        min(max(value, minimum), maximum)
    }
}
