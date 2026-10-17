import CoreGraphics

enum SystemWindowPlacement: CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter

    var moveResizeMenuIndex: Int {
        switch self {
        case .leftHalf:
            1
        case .rightHalf:
            2
        case .topHalf:
            3
        case .bottomHalf:
            4
        case .topLeftQuarter:
            6
        case .topRightQuarter:
            7
        case .bottomLeftQuarter:
            8
        case .bottomRightQuarter:
            9
        }
    }

    static func matching(
        targetFrame: CGRect,
        in visibleFrame: CGRect,
        tolerance: CGFloat = 8
    ) -> Self? {
        allCases.first { placement in
            framesApproximatelyEqual(
                placement.nativeFrame(in: visibleFrame),
                targetFrame,
                tolerance: tolerance
            )
        }
    }

    func nativeFrame(in visibleFrame: CGRect) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2

        switch self {
        case .leftHalf:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: halfWidth,
                height: visibleFrame.height
            )
        case .rightHalf:
            return CGRect(
                x: visibleFrame.minX + halfWidth,
                y: visibleFrame.minY,
                width: halfWidth,
                height: visibleFrame.height
            )
        case .topHalf:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: halfHeight
            )
        case .bottomHalf:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY + halfHeight,
                width: visibleFrame.width,
                height: halfHeight
            )
        case .topLeftQuarter:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: halfWidth,
                height: halfHeight
            )
        case .topRightQuarter:
            return CGRect(
                x: visibleFrame.minX + halfWidth,
                y: visibleFrame.minY,
                width: halfWidth,
                height: halfHeight
            )
        case .bottomLeftQuarter:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY + halfHeight,
                width: halfWidth,
                height: halfHeight
            )
        case .bottomRightQuarter:
            return CGRect(
                x: visibleFrame.minX + halfWidth,
                y: visibleFrame.minY + halfHeight,
                width: halfWidth,
                height: halfHeight
            )
        }
    }

    private static func framesApproximatelyEqual(
        _ first: CGRect,
        _ second: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance
            && abs(first.height - second.height) <= tolerance
    }
}

enum SystemWindowMoveResizeMenu {
    static func fillIndex(
        beforeMoveAndResizeIndex moveAndResizeIndex: Int,
        itemCount: Int
    ) -> Int? {
        let index = moveAndResizeIndex - 2
        return (0 ..< itemCount).contains(index) ? index : nil
    }

    static func hasExpectedTopology(
        enabledStates: [Bool]
    ) -> Bool {
        guard enabledStates.count >= 11 else {
            return false
        }

        return !enabledStates[0]
            && enabledStates[1 ... 4].allSatisfy { $0 }
            && !enabledStates[5]
            && enabledStates[6 ... 9].allSatisfy { $0 }
            && !enabledStates[10]
    }

    static func previousSizeIndex(
        enabledStates: [Bool]
    ) -> Int? {
        guard hasExpectedTopology(enabledStates: enabledStates),
              let lastIndex = enabledStates.indices.last,
              lastIndex > 10,
              enabledStates[lastIndex] else {
            return nil
        }
        return lastIndex
    }
}
