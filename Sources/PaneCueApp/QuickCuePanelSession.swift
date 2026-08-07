import Foundation
import PaneCueCore

enum QuickCuePanelPhase: Equatable, Sendable {
    case composing
    case requestingVoice
    case recording
    case transcribing
    case preparing
    case preview
    case selectingCandidate
    case applying
    case result
    case rollingBack
    case restored
}

enum QuickCuePanelEffect: Equatable, Sendable {
    case startVoice
    case stopAndTranscribe
    case preparePreview(String)
    case selectCandidate(
        previewID: UUID,
        slotID: UUID,
        candidateID: EphemeralWindowIdentifier
    )
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
    private(set) var transcriptNeedsConfirmation = false
    private var draftBeforeVoice: String?

    var canEditCommand: Bool {
        phase == .composing
    }

    var isVoiceOperationActive: Bool {
        switch phase {
        case .requestingVoice, .recording, .transcribing:
            return true
        default:
            return false
        }
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

    mutating func requestVoiceStart(
        isAvailable: Bool
    ) -> QuickCuePanelEffect? {
        guard isPresented,
              phase == .composing,
              isAvailable else {
            return nil
        }
        draftBeforeVoice = draft
        transcriptNeedsConfirmation = false
        errorMessage = nil
        phase = .requestingVoice
        return .startVoice
    }

    @discardableResult
    mutating func finishVoiceStart() -> Bool {
        guard isPresented, phase == .requestingVoice else {
            return false
        }
        phase = .recording
        return true
    }

    mutating func failVoiceStart(_ message: String) {
        guard isPresented, phase == .requestingVoice else {
            return
        }
        restoreDraftBeforeVoice()
        phase = .composing
        errorMessage = message
    }

    mutating func requestVoiceStop() -> QuickCuePanelEffect? {
        guard isPresented, phase == .recording else {
            return nil
        }
        phase = .transcribing
        return .stopAndTranscribe
    }

    @discardableResult
    mutating func finishVoiceTranscription(_ value: String) -> Bool {
        guard isPresented, phase == .transcribing else {
            return false
        }
        let transcript = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !transcript.isEmpty else {
            failVoiceTranscription(
                "PaneCue could not recognize the offline voice command."
            )
            return false
        }
        draft = transcript
        draftBeforeVoice = nil
        transcriptNeedsConfirmation = true
        errorMessage = nil
        phase = .composing
        return true
    }

    mutating func failVoiceTranscription(_ message: String) {
        guard isPresented, phase == .transcribing else {
            return
        }
        restoreDraftBeforeVoice()
        transcriptNeedsConfirmation = false
        phase = .composing
        errorMessage = message
    }

    mutating func cancelVoice() {
        guard isPresented, isVoiceOperationActive else {
            return
        }
        restoreDraftBeforeVoice()
        transcriptNeedsConfirmation = false
        phase = .composing
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
        transcriptNeedsConfirmation = false
        draftBeforeVoice = nil
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

    mutating func requestCandidateSelection(
        slotID: UUID,
        candidateID: EphemeralWindowIdentifier
    ) -> QuickCuePanelEffect? {
        guard isPresented,
              phase == .preview,
              let preview,
              let slot = preview.resolution?[slotID],
              case .ambiguous = slot.state,
              slot.candidates.contains(where: {
                  $0.id == candidateID && $0.isSelectable
              }) else {
            return nil
        }
        phase = .selectingCandidate
        errorMessage = nil
        return .selectCandidate(
            previewID: preview.id,
            slotID: slotID,
            candidateID: candidateID
        )
    }

    @discardableResult
    mutating func finishCandidateSelection(
        _ value: ArrangementPreview
    ) -> Bool {
        guard isPresented, phase == .selectingCandidate else {
            return false
        }
        preview = value
        phase = .preview
        return true
    }

    mutating func failCandidateSelection(_ message: String) {
        guard isPresented, phase == .selectingCandidate else {
            return
        }
        phase = .preview
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
        transcriptNeedsConfirmation = false
        draftBeforeVoice = nil
    }

    private mutating func restoreDraftBeforeVoice() {
        if let draftBeforeVoice {
            draft = draftBeforeVoice
        }
        self.draftBeforeVoice = nil
    }
}

struct QuickCuePreviewSlotPresentation: Equatable, Sendable {
    let title: String
    let display: String
    let geometry: String
    let state: String
    let detail: String?
}

struct QuickCueCandidatePresentation: Equatable, Sendable {
    let id: EphemeralWindowIdentifier
    let title: String
    let detail: String
    let isSelectable: Bool
}

struct QuickCueCandidateGroupPresentation: Equatable, Sendable {
    let slotID: UUID
    let title: String
    let candidates: [QuickCueCandidatePresentation]
}

struct QuickCuePreviewPresentation: Equatable, Sendable {
    let title: String
    let slots: [QuickCuePreviewSlotPresentation]
    let candidateGroups: [QuickCueCandidateGroupPresentation]
    let canApply: Bool

    init(preview: ArrangementPreview) {
        title = "Preview · \(preview.plan.windows.count) windows"
        canApply = preview.eligibility == .ready
        slots = preview.plan.windows.map { window in
            let resolution = preview.resolution?[window.id]
            return QuickCuePreviewSlotPresentation(
                title: window.target.displayName,
                display: window.display.displayName,
                geometry: Self.geometryDescription(window.gridRect),
                state: Self.stateDescription(resolution?.state),
                detail: Self.matchDescription(resolution?.state)
            )
        }
        candidateGroups = preview.plan.windows.compactMap { window in
            guard let resolution = preview.resolution?[window.id],
                  case .ambiguous = resolution.state,
                  !resolution.candidates.isEmpty else {
                return nil
            }
            return QuickCueCandidateGroupPresentation(
                slotID: window.id,
                title: window.target.displayName,
                candidates: resolution.candidates.map { candidate in
                    QuickCueCandidatePresentation(
                        id: candidate.id,
                        title: candidate.localizedApplicationName,
                        detail: candidate.localDifferentiator
                            ?? "Window",
                        isSelectable: candidate.isSelectable
                    )
                }
            )
        }
    }

    var candidateCount: Int {
        candidateGroups.reduce(0) { $0 + $1.candidates.count }
    }

    private static func geometryDescription(
        _ rect: ScenarioGridRect
    ) -> String {
        let normalized = rect.normalized
        return "\(percent(normalized.width)) × "
            + "\(percent(normalized.height)) · "
            + "x \(percent(normalized.x)), y \(percent(normalized.y))"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
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

enum QuickCueMotionPolicy {
    static func shouldAnimate(
        panelIsVisible: Bool,
        reduceMotion: Bool
    ) -> Bool {
        panelIsVisible && !reduceMotion
    }
}

struct QuickCuePerformanceSnapshot: Equatable, Sendable {
    let hotKeyToVisibleP95: TimeInterval?
    let textToPreviewP95: TimeInterval?
    let transcriptToPreviewP95: TimeInterval?

    var meetsLatencyGates: Bool {
        Self.meets(hotKeyToVisibleP95, limit: 0.2)
            && Self.meets(textToPreviewP95, limit: 0.5)
            && Self.meets(transcriptToPreviewP95, limit: 0.5)
    }

    private static func meets(
        _ value: TimeInterval?,
        limit: TimeInterval
    ) -> Bool {
        value.map { $0 < limit } ?? false
    }
}

struct QuickCuePerformanceTracker: Sendable {
    private static let maximumSampleCount = 100
    private var hotKeyToVisibleSamples: [TimeInterval] = []
    private var textToPreviewSamples: [TimeInterval] = []
    private var transcriptToPreviewSamples: [TimeInterval] = []

    var snapshot: QuickCuePerformanceSnapshot {
        QuickCuePerformanceSnapshot(
            hotKeyToVisibleP95: Self.percentile95(
                hotKeyToVisibleSamples
            ),
            textToPreviewP95: Self.percentile95(
                textToPreviewSamples
            ),
            transcriptToPreviewP95: Self.percentile95(
                transcriptToPreviewSamples
            )
        )
    }

    mutating func recordHotKeyToVisible(_ duration: TimeInterval) {
        Self.append(duration, to: &hotKeyToVisibleSamples)
    }

    mutating func recordPreview(
        _ duration: TimeInterval,
        fromTranscript: Bool
    ) {
        if fromTranscript {
            Self.append(duration, to: &transcriptToPreviewSamples)
        } else {
            Self.append(duration, to: &textToPreviewSamples)
        }
    }

    static func percentile95(
        _ samples: [TimeInterval]
    ) -> TimeInterval? {
        let valid = samples
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()
        guard !valid.isEmpty else {
            return nil
        }
        let rank = Int(ceil(Double(valid.count) * 0.95)) - 1
        return valid[min(max(rank, 0), valid.count - 1)]
    }

    private static func append(
        _ duration: TimeInterval,
        to samples: inout [TimeInterval]
    ) {
        guard duration.isFinite, duration >= 0 else {
            return
        }
        samples.append(duration)
        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
        }
    }
}

struct QuickCuePanelLifecycleProbeResult: Equatable, Sendable {
    let completedCycles: Int
    let orphanWindowCount: Int
    let panelIsVisible: Bool
    let sessionIsPresented: Bool
    let hasActiveOperation: Bool

    var passed: Bool {
        completedCycles > 0
            && orphanWindowCount == 0
            && !panelIsVisible
            && !sessionIsPresented
            && !hasActiveOperation
    }
}
