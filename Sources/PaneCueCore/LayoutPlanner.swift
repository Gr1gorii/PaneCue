import CoreGraphics

public enum LayoutPlanner {
    public static func frame(
        for gridRect: ScenarioGridRect,
        in visibleFrame: CGRect,
        gap: CGFloat = 8
    ) -> CGRect {
        let normalized = gridRect.normalized
        let rawFrame = CGRect(
            x: visibleFrame.minX
                + visibleFrame.width * CGFloat(normalized.x),
            y: visibleFrame.minY
                + visibleFrame.height * CGFloat(normalized.y),
            width: visibleFrame.width * CGFloat(normalized.width),
            height: visibleFrame.height * CGFloat(normalized.height)
        )
        let inset = max(gap, 0) / 2
        return rawFrame.insetBy(dx: inset, dy: inset)
    }

    public static func sideBySide(
        in visibleFrame: CGRect,
        primaryRatio: CGFloat = 0.65,
        gap: CGFloat = 8
    ) -> PairLayout {
        let safeRatio = min(max(primaryRatio, 0.5), 0.8)
        let safeGap = max(gap, 0)
        let usableWidth = max(visibleFrame.width - safeGap, 0)
        let primaryWidth = floor(usableWidth * safeRatio)
        let secondaryWidth = usableWidth - primaryWidth

        let primary = CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: primaryWidth,
            height: visibleFrame.height
        )

        let secondary = CGRect(
            x: primary.maxX + safeGap,
            y: visibleFrame.minY,
            width: secondaryWidth,
            height: visibleFrame.height
        )

        return PairLayout(primary: primary, secondary: secondary)
    }

    public static func pictureInPicture(
        in visibleFrame: CGRect,
        preferredWidth: CGFloat = 260,
        margin: CGFloat = 16,
        verticalPlacement: CGFloat = 0.5
    ) -> CGRect {
        let maximumWidth = visibleFrame.width * 0.22
        let width = min(max(preferredWidth, 220), max(maximumWidth, 220))
        let height = width * 9 / 16
        let safeMargin = max(margin, 0)
        let placement = min(max(verticalPlacement, 0), 1)
        let availableVerticalTravel = max(visibleFrame.height - height - safeMargin * 2, 0)

        return CGRect(
            x: visibleFrame.maxX - width - safeMargin,
            y: visibleFrame.minY + safeMargin + availableVerticalTravel * placement,
            width: width,
            height: height
        )
    }

    public static func codeAndCall(
        in visibleFrame: CGRect,
        compactCallSize: CGSize = CGSize(width: 320, height: 240),
        margin: CGFloat = 16
    ) -> PairLayout {
        let safeMargin = max(margin, 0)
        let maximumWidth = max(visibleFrame.width - safeMargin * 2, 0)
        let maximumHeight = max(visibleFrame.height - safeMargin * 2, 0)
        let width = min(max(compactCallSize.width, 220), maximumWidth)
        let height = min(max(compactCallSize.height, 135), maximumHeight)

        let compactCall = CGRect(
            x: visibleFrame.maxX - width - safeMargin,
            y: visibleFrame.minY + safeMargin,
            width: width,
            height: height
        )

        return PairLayout(
            primary: visibleFrame,
            secondary: compactCall
        )
    }
}
