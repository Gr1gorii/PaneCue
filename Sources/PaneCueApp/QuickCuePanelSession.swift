import Foundation
import PaneCueCore

enum QuickCuePanelPhase: Equatable, Sendable {
    case composing
    case preparing
    case preview
    case applying
    case result
    case rollingBack
    case restored
}

enum QuickCuePanelEffect: Equatable, Sendable {
    case preparePreview(String)
    case apply(ArrangementPreview)
    case rollback
}

struct QuickCuePanelSession: Equatable, Sendable {
    private(set) var isPresented = false
    private(set) var draft = ""
    private(set) var phase: QuickCuePanelPhase = .composing
    private(set) var preview: ArrangementPreview?
    private(set) var applyResult: WorkspaceApplyResult?
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?

    var canEditCommand: Bool {
        phase == .composing
    }

    mutating func present() {
        isPresented = true
    }

    mutating func updateDraft(_ value: String) {
        guard isPresented, canEditCommand else {
            return
        }
        draft = value
        errorMessage = nil
    }

    mutating func submitCommand() -> QuickCuePanelEffect? {
        guard isPresented, phase == .composing else {
            return nil
        }
        let command = draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !command.isEmpty else {
            return nil
        }

        preview = nil
        applyResult = nil
        statusMessage = nil
        errorMessage = nil
        phase = .preparing
        return .preparePreview(command)
    }

    @discardableResult
    mutating func finishPreview(_ value: ArrangementPreview) -> Bool {
        guard isPresented, phase == .preparing else {
            return false
        }
        preview = value
        phase = .preview
        return true
    }

    mutating func failPreview(_ message: String) {
        guard isPresented, phase == .preparing else {
            return
        }
        phase = .composing
        errorMessage = message
    }

    mutating func requestApply() -> QuickCuePanelEffect? {
        guard isPresented,
              phase == .preview,
              let preview,
              preview.eligibility == .ready else {
            return nil
        }
        phase = .applying
        errorMessage = nil
        return .apply(preview)
    }

    mutating func finishApply(_ result: WorkspaceApplyResult) {
        guard isPresented, phase == .applying else {
            return
        }
        applyResult = result
        statusMessage = result.summary
        phase = .result
    }

    mutating func failApply(_ message: String) {
        guard isPresented, phase == .applying else {
            return
        }
        errorMessage = message
        phase = .preview
    }

    mutating func requestRollback() -> QuickCuePanelEffect? {
        guard isPresented,
              phase == .result,
              applyResult?.canRollback == true else {
            return nil
        }
        phase = .rollingBack
        errorMessage = nil
        return .rollback
    }

    mutating func finishRollback(_ message: String) {
        guard isPresented, phase == .rollingBack else {
            return
        }
        statusMessage = message
        phase = .restored
    }

    mutating func failRollback(_ message: String) {
        guard isPresented, phase == .rollingBack else {
            return
        }
        errorMessage = message
        phase = .result
    }

    mutating func dismiss() {
        isPresented = false
        draft.removeAll(keepingCapacity: false)
        phase = .composing
        preview = nil
        applyResult = nil
        statusMessage = nil
        errorMessage = nil
    }
}

struct QuickCuePreviewSlotPresentation: Equatable, Sendable {
    let title: String
    let display: String
    let state: String
    let detail: String?
}

struct QuickCuePreviewPresentation: Equatable, Sendable {
    let title: String
    let slots: [QuickCuePreviewSlotPresentation]
    let canApply: Bool

    init(preview: ArrangementPreview) {
        title = "Preview · \(preview.plan.windows.count) windows"
        canApply = preview.eligibility == .ready
        slots = preview.plan.windows.map { window in
            let resolution = preview.resolution?[window.id]
            return QuickCuePreviewSlotPresentation(
                title: window.target.displayName,
                display: window.display.displayName,
                state: Self.stateDescription(resolution?.state),
                detail: Self.matchDescription(resolution?.state)
            )
        }
    }

    private static func stateDescription(
        _ state: ArrangementTargetResolutionState?
    ) -> String {
        switch state {
        case .resolved:
            return "Ready"
        case let .ambiguous(candidateCount):
            return "Choose 1 of \(candidateCount)"
        case .missing:
            return "Not open"
        case .unsupported:
            return "Unavailable"
        case nil:
            return "Needs review"
        }
    }

    private static func matchDescription(
        _ state: ArrangementTargetResolutionState?
    ) -> String? {
        guard case let .resolved(target) = state else {
            return nil
        }
        return "\(target.localizedApplicationName) · "
            + target.matchReason.shortDescription
    }
}

enum QuickCueTextFlowError: LocalizedError {
    case previewUnavailable

    var errorDescription: String? {
        switch self {
        case .previewUnavailable:
            return "PaneCue could not create a safe Preview for that command."
        }
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
