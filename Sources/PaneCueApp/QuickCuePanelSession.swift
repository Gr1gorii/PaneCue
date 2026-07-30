import Foundation

struct QuickCuePanelSession: Equatable, Sendable {
    private(set) var isPresented = false
    private(set) var draft = ""

    mutating func present() {
        isPresented = true
    }

    mutating func updateDraft(_ value: String) {
        guard isPresented else {
            return
        }
        draft = value
    }

    mutating func dismiss() {
        isPresented = false
        draft.removeAll(keepingCapacity: false)
    }
}

enum QuickCuePanelPlacement {
    static func targetScreenIndex(
        pointer: CGPoint,
        screenFrames: [CGRect],
        mainScreenIndex: Int?
    ) -> Int? {
        if let pointerScreen = screenFrames.firstIndex(where: {
            $0.contains(pointer)
        }) {
            return pointerScreen
        }
        if let mainScreenIndex,
           screenFrames.indices.contains(mainScreenIndex) {
            return mainScreenIndex
        }
        return screenFrames.indices.first
    }

    static func panelFrame(
        preferredSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let horizontalMargin = min(24, visibleFrame.width * 0.05)
        let width = min(
            preferredSize.width,
            max(1, visibleFrame.width - horizontalMargin * 2)
        )
        let height = min(
            preferredSize.height,
            max(1, visibleFrame.height)
        )
        let centerY = visibleFrame.midY + visibleFrame.height * 0.22
        let origin = CGPoint(
            x: visibleFrame.midX - width / 2,
            y: centerY - height / 2
        )
        return CGRect(
            origin: origin,
            size: CGSize(width: width, height: height)
        )
    }
}
