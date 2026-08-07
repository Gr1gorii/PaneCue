import AppKit
import PaneCueCore

struct QuickCuePanelActions {
    let isVoiceAvailable: @MainActor () -> Bool
    let startVoice: @MainActor () async throws -> Void
    let stopVoice: @MainActor () async throws -> String
    let cancelVoice: @MainActor () -> Void
    let preparePreview: @MainActor
        (String) async throws -> ArrangementPreview
    let prepareExternalCommandPreview: @MainActor
        (String) async throws -> ArrangementPreview
    let prepareExternalCuePreview: @MainActor
        (UUID) async throws -> ArrangementPreview
    let selectCandidate: @MainActor
        (
            UUID,
            UUID,
            EphemeralWindowIdentifier
        ) async throws -> ArrangementPreview
    let applyPreview: @MainActor
        (ArrangementPreview) async throws -> WorkspaceApplyResult
    let rollback: @MainActor () async throws -> String
    let editFullPlan: @MainActor (ArrangementPreview) -> Void
    let discardPreview: @MainActor () async -> Void
}

@MainActor
final class QuickCuePanelController: NSObject, NSTextFieldDelegate {
    private static let preferredWidth: CGFloat = 620
    private static let composingHeight: CGFloat = 84

    private let actions: QuickCuePanelActions
    private let panel: QuickCuePanel
    private let commandField = NSTextField()
    private let contentStack = NSStackView()
    private var session = QuickCuePanelSession()
    private var operationTask: Task<Void, Never>?
    private var keyboardViews: [NSView] = []
    private var returnApplication: NSRunningApplication?
    private var performanceTracker = QuickCuePerformanceTracker()

    var performanceSnapshot: QuickCuePerformanceSnapshot {
        performanceTracker.snapshot
    }

    init(actions: QuickCuePanelActions) {
        self.actions = actions
        panel = QuickCuePanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: Self.preferredWidth,
                    height: Self.composingHeight
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    func present() {
        let startedAt = ProcessInfo.processInfo.systemUptime
        rememberFrontmostApplicationIfNeeded()
        session.present()
        showPanel()
        performanceTracker.recordHotKeyToVisible(
            ProcessInfo.processInfo.systemUptime - startedAt
        )
    }

    func presentExternalCommand(_ command: String) {
        prepareToReplaceSession()
        rememberFrontmostApplicationIfNeeded()
        guard case let .preparePreview(value) = session
            .beginExternalCommand(command) else {
            return
        }
        showPanel()
        startCommandPreview(
            value,
            startedAt: ProcessInfo.processInfo.systemUptime,
            startedFromTranscript: false,
            isExternal: true,
            tracksPerformance: false
        )
    }

    func presentExternalCue(id: UUID) {
        prepareToReplaceSession()
        rememberFrontmostApplicationIfNeeded()
        session.beginExternalCuePreview()
        showPanel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let preview = try await actions.prepareExternalCuePreview(id)
                try Task.checkCancellation()
                guard session.finishPreview(preview) else {
                    return
                }
                render()
            } catch is CancellationError {
                return
            } catch {
                session.failPreview(error.localizedDescription)
                render()
                panel.makeFirstResponder(commandField)
            }
        }
    }

    func dismiss() {
        dismiss(discardPreview: true)
    }

    func runLifecycleProbe(
        iterations: Int
    ) -> QuickCuePanelLifecycleProbeResult {
        let cycleCount = max(0, iterations)
        for _ in 0..<cycleCount {
            session.present()
            render()
            panel.orderFront(nil)
            dismiss(
                discardPreview: false,
                restorePreviousApplication: false
            )
        }
        let orphanWindowCount = NSApplication.shared.windows.filter { window in
            window is QuickCuePanel && window !== panel
        }.count
        return QuickCuePanelLifecycleProbeResult(
            completedCycles: cycleCount,
            orphanWindowCount: orphanWindowCount,
            panelIsVisible: panel.isVisible,
            sessionIsPresented: session.isPresented,
            hasActiveOperation: operationTask != nil
        )
    }

    func controlTextDidChange(_ notification: Notification) {
        session.updateDraft(commandField.stringValue)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector
                == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            submitCommand()
            return true
        }
        return false
    }

    private func configurePanel() {
        let visualEffect = NSVisualEffectView(
            frame: panel.contentView?.bounds ?? .zero
        )
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true
        panel.contentView = visualEffect

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 12
        visualEffect.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: visualEffect.leadingAnchor,
                constant: 22
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: visualEffect.trailingAnchor,
                constant: -22
            ),
            contentStack.topAnchor.constraint(
                equalTo: visualEffect.topAnchor,
                constant: 16
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: visualEffect.bottomAnchor,
                constant: -16
            )
        ])

        commandField.isBezeled = false
        commandField.drawsBackground = false
        commandField.focusRingType = .default
        commandField.font = .systemFont(ofSize: 20, weight: .medium)
        commandField.textColor = .labelColor
        commandField.placeholderString = "What should change?"
        commandField.lineBreakMode = .byTruncatingTail
        commandField.delegate = self
        commandField.setAccessibilityLabel("Quick Cue command")
        commandField.setAccessibilityHelp(
            "Describe the workspace, then press Return to create a Preview."
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.sharingType = .none
        panel.onCancel = { [weak self] in
            self?.dismiss()
        }
        panel.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        panel.setAccessibilityLabel("Quick Cue")
    }

    private func render() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        keyboardViews.removeAll(keepingCapacity: true)

        commandField.stringValue = session.draft
        commandField.isEditable = session.canEditCommand
        commandField.isSelectable = session.canEditCommand
        contentStack.addArrangedSubview(makeCommandRow())

        if session.isExternalRequest {
            contentStack.addArrangedSubview(makeMessageRow(
                "External request · Review before Apply",
                systemImage: "link",
                color: .systemPurple
            ))
        }

        switch session.phase {
        case .composing:
            if session.transcriptNeedsConfirmation {
                contentStack.addArrangedSubview(makeMessageRow(
                    "Transcript ready · edit it before Preview",
                    systemImage: "text.cursor",
                    color: .controlAccentColor
                ))
                contentStack.addArrangedSubview(
                    makeTranscriptConfirmationButtons()
                )
            }
            if let error = session.errorMessage {
                contentStack.addArrangedSubview(makeMessageRow(
                    error,
                    systemImage: "exclamationmark.triangle.fill",
                    color: .systemOrange
                ))
            }
        case .requestingVoice:
            contentStack.addArrangedSubview(makeProgressRow(
                "Preparing microphone and offline speech…"
            ))
            contentStack.addArrangedSubview(makeVoiceCancelButtons())
        case .recording:
            contentStack.addArrangedSubview(makeMessageRow(
                "Recording locally…",
                systemImage: "waveform.circle.fill",
                color: .systemRed
            ))
            contentStack.addArrangedSubview(makeRecordingButtons())
        case .transcribing:
            contentStack.addArrangedSubview(makeProgressRow(
                "Transcribing on this Mac…"
            ))
            contentStack.addArrangedSubview(makeVoiceCancelButtons())
        case .preparing:
            contentStack.addArrangedSubview(makeProgressRow(
                "Creating a safe Preview…"
            ))
        case .preview, .selectingCandidate, .applying:
            if let preview = session.preview {
                let previewView = makePreviewView(preview)
                contentStack.addArrangedSubview(previewView)
            }
            if session.phase == .selectingCandidate {
                contentStack.addArrangedSubview(makeProgressRow(
                    "Binding the selected window…"
                ))
            } else if session.phase == .applying {
                contentStack.addArrangedSubview(makeProgressRow(
                    "Applying after revalidation…"
                ))
            } else {
                if let error = session.errorMessage {
                    contentStack.addArrangedSubview(makeMessageRow(
                        error,
                        systemImage: "exclamationmark.triangle.fill",
                        color: .systemOrange
                    ))
                }
                contentStack.addArrangedSubview(makePreviewButtons())
            }
        case .result, .rollingBack:
            contentStack.addArrangedSubview(makeResultView())
            if session.phase == .rollingBack {
                contentStack.addArrangedSubview(makeProgressRow(
                    "Restoring the previous layout…"
                ))
            } else {
                contentStack.addArrangedSubview(makeResultButtons())
            }
        case .restored:
            contentStack.addArrangedSubview(makeMessageRow(
                session.statusMessage ?? "Previous layout restored",
                systemImage: "arrow.uturn.backward.circle.fill",
                color: .systemGreen
            ))
            contentStack.addArrangedSubview(makeDoneButtons())
        }

        let size = NSSize(
            width: Self.preferredWidth,
            height: preferredHeight
        )
        moveToActiveDisplay(size: size)
        panel.contentView?.layoutSubtreeIfNeeded()
        configureKeyViewLoop()
        if panel.isKeyWindow {
            focusInitialElement()
        }
    }

    private var preferredHeight: CGFloat {
        switch session.phase {
        case .composing:
            if session.transcriptNeedsConfirmation {
                return session.errorMessage == nil ? 166 : 208
            }
            return session.errorMessage == nil ? 84 : 126
        case .requestingVoice, .recording, .transcribing:
            return 166
        case .preparing:
            return 126
        case .preview, .selectingCandidate, .applying:
            guard let preview = session.preview else {
                return 202
            }
            let presentation = QuickCuePreviewPresentation(preview: preview)
            let slotHeight = CGFloat(presentation.slots.count) * 52
            let chooserHeight = min(
                CGFloat(presentation.candidateGroups.count) * 38
                    + CGFloat(presentation.candidateCount) * 52,
                268
            )
            let progressHeight: CGFloat = session.phase == .preview ? 0 : 42
            return 202 + slotHeight + chooserHeight + progressHeight
        case .result:
            return session.errorMessage == nil ? 190 : 228
        case .rollingBack:
            return 190
        case .restored:
            return 150
        }
    }

    private func makeCommandRow() -> NSView {
        let symbolView = NSImageView()
        symbolView.image = NSImage(
            systemSymbolName: "rectangle.split.2x1",
            accessibilityDescription: "Quick Cue"
        )
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 19,
            weight: .semibold
        )
        symbolView.contentTintColor = .controlAccentColor
        symbolView.setAccessibilityElement(false)
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 28),
            symbolView.heightAnchor.constraint(equalToConstant: 28)
        ])

        var trailingViews: [NSView] = []
        if session.canEditCommand {
            keyboardViews.append(commandField)
        }
        if session.phase == .composing, actions.isVoiceAvailable() {
            let microphone = QuickCueActionButton(
                image: NSImage(
                    systemSymbolName: "mic.fill",
                    accessibilityDescription: "Start offline voice"
                ) ?? NSImage(),
                target: self,
                action: #selector(startVoice)
            )
            microphone.bezelStyle = .texturedRounded
            microphone.isBordered = false
            microphone.contentTintColor = .controlAccentColor
            microphone.setAccessibilityLabel("Start offline voice")
            microphone.setAccessibilityHelp(
                "Record a command and transcribe it on this Mac."
            )
            trailingViews.append(microphone)
            keyboardViews.append(microphone)
        }

        let hint = NSTextField(
            labelWithString: session.canEditCommand ? "↵" : "esc"
        )
        hint.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        hint.textColor = .tertiaryLabelColor
        hint.setContentHuggingPriority(.required, for: .horizontal)
        hint.setAccessibilityElement(false)
        trailingViews.append(hint)

        let row = NSStackView(
            views: [symbolView, commandField] + trailingViews
        )
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func makeProgressRow(_ title: String) -> NSView {
        let progress: NSView
        if reduceMotion {
            let image = NSImageView()
            image.image = NSImage(
                systemSymbolName: "hourglass",
                accessibilityDescription: nil
            )
            image.contentTintColor = .secondaryLabelColor
            progress = image
        } else {
            let indicator = NSProgressIndicator()
            indicator.style = .spinning
            indicator.controlSize = .small
            indicator.startAnimation(nil)
            progress = indicator
        }
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        let row = NSStackView(views: [progress, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        row.setAccessibilityLabel(title)
        return row
    }

    private func makePreviewView(_ preview: ArrangementPreview) -> NSView {
        let presentation = QuickCuePreviewPresentation(preview: preview)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8

        let heading = NSTextField(labelWithString: presentation.title)
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(heading)

        for (index, slot) in presentation.slots.enumerated() {
            stack.addArrangedSubview(makePreviewRow(
                index: index,
                slot: slot
            ))
        }
        if !presentation.candidateGroups.isEmpty {
            stack.addArrangedSubview(makeCandidateChooser(
                presentation.candidateGroups
            ))
        }
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel("Quick Cue Preview")
        return stack
    }

    private func makePreviewRow(
        index: Int,
        slot: QuickCuePreviewSlotPresentation
    ) -> NSView {
        let number = NSTextField(labelWithString: "\(index + 1)")
        number.alignment = .center
        number.font = .systemFont(ofSize: 12, weight: .semibold)
        number.textColor = .controlAccentColor
        number.translatesAutoresizingMaskIntoConstraints = false
        number.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let title = NSTextField(labelWithString: slot.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(
            labelWithString: [
                slot.display,
                slot.geometry,
                slot.detail
            ]
                .compactMap { $0 }
                .joined(separator: " · ")
        )
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let state = NSTextField(labelWithString: slot.state)
        state.font = .systemFont(ofSize: 11, weight: .semibold)
        state.textColor = slot.state == "Ready"
            ? .systemGreen
            : .systemOrange
        state.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [number, text, state])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        row.setAccessibilityLabel(
            "\(index + 1), \(slot.title), \(slot.display), "
                + "\(slot.geometry), \(slot.state)"
                + (slot.detail.map { ", \($0)" } ?? "")
        )
        return row
    }

    private func makeCandidateChooser(
        _ groups: [QuickCueCandidateGroupPresentation]
    ) -> NSView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 7

        let heading = NSTextField(
            labelWithString: "Choose the exact window"
        )
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .systemOrange
        content.addArrangedSubview(heading)

        var shortcutNumber = 1
        for group in groups {
            let groupTitle = NSTextField(labelWithString: group.title)
            groupTitle.font = .systemFont(ofSize: 11, weight: .semibold)
            groupTitle.textColor = .secondaryLabelColor
            content.addArrangedSubview(groupTitle)

            for candidate in group.candidates {
                let button = QuickCueCandidateButton(
                    title: candidate.title,
                    target: self,
                    action: #selector(selectCandidate(_:))
                )
                button.slotID = group.slotID
                button.candidateID = candidate.id
                button.bezelStyle = .rounded
                button.alignment = .left
                button.isEnabled = candidate.isSelectable
                    && session.phase == .preview
                button.toolTip = candidate.detail
                button.setAccessibilityLabel(
                    "\(candidate.title), \(candidate.detail)"
                )
                button.setAccessibilityHelp(
                    candidate.isSelectable
                        ? "Select this window for \(group.title)"
                        : "This window is unavailable"
                )
                if candidate.isSelectable, shortcutNumber <= 9 {
                    button.title = "\(candidate.title) — "
                        + "\(candidate.detail)        ⌘\(shortcutNumber)"
                    button.keyEquivalent = "\(shortcutNumber)"
                    button.keyEquivalentModifierMask = [.command]
                    shortcutNumber += 1
                } else {
                    button.title = "\(candidate.title) — "
                        + "\(candidate.detail)"
                }
                content.addArrangedSubview(button)
                if button.isEnabled {
                    keyboardViews.append(button)
                }
            }
        }

        content.setAccessibilityRole(.group)
        content.setAccessibilityLabel("Quick Cue window candidates")

        let candidateCount = groups.reduce(0) {
            $0 + $1.candidates.count
        }
        guard candidateCount > 4 else {
            return content
        }

        let document = QuickCueFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(
                equalTo: scroll.contentView.widthAnchor
            ),
            scroll.heightAnchor.constraint(equalToConstant: 268)
        ])
        scroll.setAccessibilityLabel("Quick Cue window candidates")
        return scroll
    }

    private func makePreviewButtons() -> NSView {
        let cancel = makeButton(
            title: "Cancel",
            action: #selector(cancelPreview),
            help: "Close Quick Cue without moving windows."
        )
        let edit = makeButton(
            title: "Edit Full Plan",
            action: #selector(editFullPlan),
            help: "Open this Preview in the full Arrange editor."
        )
        let apply = makeButton(
            title: "Apply \(session.preview?.plan.windows.count ?? 0) Windows",
            action: #selector(applyPreview),
            help: "Revalidate and apply this Preview."
        )
        apply.bezelColor = .controlAccentColor
        apply.isEnabled = session.preview?.eligibility == .ready
        apply.keyEquivalent = "\r"
        apply.keyEquivalentModifierMask = [.command]
        return makeButtonRow([cancel, edit, apply])
    }

    private func makeTranscriptConfirmationButtons() -> NSView {
        let createPreview = makeButton(
            title: "Create Preview",
            action: #selector(confirmTranscript),
            help: "Create a Preview from the edited transcript."
        )
        createPreview.bezelColor = .controlAccentColor
        return makeButtonRow([createPreview])
    }

    private func makeRecordingButtons() -> NSView {
        let cancel = makeButton(
            title: "Cancel",
            action: #selector(cancelVoice)
        )
        let stop = makeButton(
            title: "Stop & Transcribe",
            action: #selector(stopVoice)
        )
        stop.bezelColor = .systemRed
        return makeButtonRow([cancel, stop])
    }

    private func makeVoiceCancelButtons() -> NSView {
        makeButtonRow([
            makeButton(
                title: "Cancel",
                action: #selector(cancelVoice)
            )
        ])
    }

    private func makeResultView() -> NSView {
        let result = session.applyResult
        let title = session.statusMessage ?? "Apply finished"
        let appearance = resultAppearance(result)
        let detail: String
        if let result {
            detail = "\(result.movedCount) moved · "
                + "\(result.unchangedCount) unchanged · "
                + "\(result.skippedCount + result.failedCount) need attention"
        } else {
            detail = "Review the result before continuing."
        }
        let stack = NSStackView(views: [
            makeMessageRow(
                title,
                systemImage: appearance.symbol,
                color: appearance.color
            ),
            secondaryLabel(detail)
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        if let error = session.errorMessage {
            stack.addArrangedSubview(makeMessageRow(
                error,
                systemImage: "exclamationmark.triangle.fill",
                color: .systemOrange
            ))
        }
        return stack
    }

    private func resultAppearance(
        _ result: WorkspaceApplyResult?
    ) -> (symbol: String, color: NSColor) {
        guard let result else {
            return ("minus.circle.fill", .secondaryLabelColor)
        }
        if result.failedCount > 0 {
            return ("exclamationmark.triangle.fill", .systemRed)
        }
        if result.skippedCount > 0 {
            return ("exclamationmark.triangle.fill", .systemOrange)
        }
        return result.didChangeAnyWindow
            ? ("checkmark.circle.fill", .systemGreen)
            : ("minus.circle.fill", .secondaryLabelColor)
    }

    private func makeResultButtons() -> NSView {
        var buttons = [
            makeButton(title: "Done", action: #selector(cancelPreview))
        ]
        if session.preview != nil {
            buttons.append(makeButton(
                title: "Edit Full Plan",
                action: #selector(editFullPlan)
            ))
        }
        if session.applyResult?.canRollback == true {
            let undo = makeButton(
                title: "Undo Apply",
                action: #selector(rollbackPreview)
            )
            undo.bezelColor = .controlAccentColor
            buttons.append(undo)
        }
        return makeButtonRow(buttons)
    }

    private func makeDoneButtons() -> NSView {
        makeButtonRow([
            makeButton(title: "Done", action: #selector(cancelPreview))
        ])
    }

    private func makeMessageRow(
        _ title: String,
        systemImage: String,
        color: NSColor
    ) -> NSView {
        let image = NSImageView()
        image.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: nil
        )
        image.contentTintColor = color
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func secondaryLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeButton(
        title: String,
        action: Selector,
        help: String? = nil
    ) -> NSButton {
        let button = QuickCueActionButton(
            title: title,
            target: self,
            action: action
        )
        button.bezelStyle = .rounded
        button.setAccessibilityLabel(title)
        if let help {
            button.setAccessibilityHelp(help)
        }
        keyboardViews.append(button)
        return button
    }

    private func makeButtonRow(_ buttons: [NSButton]) -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spacer] + buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    @objc
    private func startVoice() {
        guard session.requestVoiceStart(
            isAvailable: actions.isVoiceAvailable()
        ) == .startVoice else {
            NSSound.beep()
            return
        }
        render()
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await actions.startVoice()
                try Task.checkCancellation()
                guard session.finishVoiceStart() else {
                    actions.cancelVoice()
                    return
                }
                render()
            } catch is CancellationError {
                actions.cancelVoice()
            } catch {
                actions.cancelVoice()
                guard !Task.isCancelled else {
                    return
                }
                session.failVoiceStart(error.localizedDescription)
                render()
                panel.makeFirstResponder(commandField)
            }
        }
    }

    @objc
    private func stopVoice() {
        guard session.requestVoiceStop() == .stopAndTranscribe else {
            NSSound.beep()
            return
        }
        render()
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let transcript = try await actions.stopVoice()
                try Task.checkCancellation()
                guard session.finishVoiceTranscription(transcript) else {
                    return
                }
                render()
                panel.makeFirstResponder(commandField)
            } catch is CancellationError {
                actions.cancelVoice()
            } catch {
                actions.cancelVoice()
                guard !Task.isCancelled else {
                    return
                }
                session.failVoiceTranscription(error.localizedDescription)
                render()
                panel.makeFirstResponder(commandField)
            }
        }
    }

    @objc
    private func cancelVoice() {
        guard session.isVoiceOperationActive else {
            return
        }
        operationTask?.cancel()
        operationTask = nil
        actions.cancelVoice()
        session.cancelVoice()
        render()
        panel.makeFirstResponder(commandField)
    }

    @objc
    private func confirmTranscript() {
        submitCommand()
    }

    private func submitCommand() {
        commandField.stringValue = session.draft
        let startedAt = ProcessInfo.processInfo.systemUptime
        let startedFromTranscript = session.transcriptNeedsConfirmation
        guard case let .preparePreview(command) = session.submitCommand()
        else {
            NSSound.beep()
            return
        }
        render()
        startCommandPreview(
            command,
            startedAt: startedAt,
            startedFromTranscript: startedFromTranscript,
            isExternal: false,
            tracksPerformance: true
        )
    }

    private func startCommandPreview(
        _ command: String,
        startedAt: TimeInterval,
        startedFromTranscript: Bool,
        isExternal: Bool,
        tracksPerformance: Bool
    ) {
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let preview = try await (
                    isExternal
                        ? actions.prepareExternalCommandPreview(command)
                        : actions.preparePreview(command)
                )
                try Task.checkCancellation()
                guard session.finishPreview(preview) else {
                    return
                }
                render()
                if tracksPerformance {
                    performanceTracker.recordPreview(
                        ProcessInfo.processInfo.systemUptime - startedAt,
                        fromTranscript: startedFromTranscript
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                session.failPreview(error.localizedDescription)
                render()
                panel.makeFirstResponder(commandField)
            }
        }
    }

    private func rememberFrontmostApplicationIfNeeded() {
        guard !panel.isVisible else {
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo
            .processIdentifier {
            returnApplication = frontmost
        }
    }

    private func prepareToReplaceSession() {
        let wasUsingVoice = session.isVoiceOperationActive
        operationTask?.cancel()
        operationTask = nil
        if wasUsingVoice {
            actions.cancelVoice()
        }
    }

    private func showPanel() {
        updateAnimationBehavior()
        render()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusInitialElement()
    }

    @objc
    private func applyPreview() {
        guard case let .apply(preview) = session.requestApply() else {
            NSSound.beep()
            return
        }
        render()
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let result = try await actions.applyPreview(preview)
                try Task.checkCancellation()
                session.finishApply(result)
                render()
            } catch is CancellationError {
                return
            } catch {
                session.failApply(error.localizedDescription)
                render()
            }
        }
    }

    @objc
    private func selectCandidate(_ sender: QuickCueCandidateButton) {
        guard let slotID = sender.slotID,
              let candidateID = sender.candidateID,
              case let .selectCandidate(
                  previewID,
                  selectedSlotID,
                  selectedCandidateID
              ) = session.requestCandidateSelection(
                  slotID: slotID,
                  candidateID: candidateID
              ) else {
            NSSound.beep()
            return
        }
        render()
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let preview = try await actions.selectCandidate(
                    previewID,
                    selectedSlotID,
                    selectedCandidateID
                )
                try Task.checkCancellation()
                guard session.finishCandidateSelection(preview) else {
                    return
                }
                render()
            } catch is CancellationError {
                return
            } catch {
                session.failCandidateSelection(error.localizedDescription)
                render()
            }
        }
    }

    @objc
    private func rollbackPreview() {
        guard session.requestRollback() == .rollback else {
            NSSound.beep()
            return
        }
        render()
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let message = try await actions.rollback()
                try Task.checkCancellation()
                session.finishRollback(message)
                render()
            } catch is CancellationError {
                return
            } catch {
                session.failRollback(error.localizedDescription)
                render()
            }
        }
    }

    @objc
    private func editFullPlan() {
        guard let preview = session.preview else {
            return
        }
        dismiss(
            discardPreview: false,
            restorePreviousApplication: false
        )
        actions.editFullPlan(preview)
    }

    @objc
    private func cancelPreview() {
        dismiss()
    }

    private func dismiss(
        discardPreview: Bool,
        restorePreviousApplication: Bool = true
    ) {
        let wasUsingVoice = session.isVoiceOperationActive
        let applicationToRestore = returnApplication
        returnApplication = nil
        operationTask?.cancel()
        operationTask = nil
        if wasUsingVoice {
            actions.cancelVoice()
        }
        session.dismiss()
        commandField.stringValue = ""
        panel.makeFirstResponder(nil)
        panel.resignKey()
        panel.orderOut(nil)
        if restorePreviousApplication,
           let applicationToRestore,
           !applicationToRestore.isTerminated {
            applicationToRestore.activate(options: [])
        }
        if discardPreview {
            Task { @MainActor [actions] in
                await actions.discardPreview()
            }
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updateAnimationBehavior() {
        panel.animationBehavior = reduceMotion ? .none : .utilityWindow
    }

    private func configureKeyViewLoop() {
        let views = activeKeyboardViews
        guard !views.isEmpty else {
            return
        }
        for (index, view) in views.enumerated() {
            view.nextKeyView = views[(index + 1) % views.count]
        }
        panel.initialFirstResponder = views[0]
        panel.recalculateKeyViewLoop()
    }

    private func focusInitialElement() {
        guard let target = activeKeyboardViews.first else {
            panel.makeFirstResponder(nil)
            return
        }
        panel.makeFirstResponder(target)
    }

    private var activeKeyboardViews: [NSView] {
        keyboardViews.filter { view in
            guard !view.isHidden else {
                return false
            }
            return (view as? NSControl)?.isEnabled ?? true
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 48:
            moveKeyboardFocus(
                backwards: event.modifierFlags.contains(.shift)
            )
            return true
        case 53:
            dismiss()
            return true
        case 36, 49, 76:
            let actionModifiers: NSEvent.ModifierFlags = [
                .command,
                .control,
                .option
            ]
            guard event.modifierFlags.intersection(actionModifiers).isEmpty,
                  let button = focusedButton else {
                return false
            }
            button.performClick(nil)
            return true
        default:
            return false
        }
    }

    private func moveKeyboardFocus(backwards: Bool) {
        let views = activeKeyboardViews
        guard !views.isEmpty else {
            NSSound.beep()
            return
        }
        let currentIndex = views.firstIndex(where: {
            isKeyboardViewFocused($0)
        })
        let nextIndex: Int
        if let currentIndex {
            let offset = backwards ? -1 : 1
            nextIndex = (currentIndex + offset + views.count) % views.count
        } else {
            nextIndex = backwards ? views.count - 1 : 0
        }
        panel.makeFirstResponder(views[nextIndex])
    }

    private func isKeyboardViewFocused(_ view: NSView) -> Bool {
        if panel.firstResponder === view {
            return true
        }
        return view === commandField
            && panel.firstResponder === commandField.currentEditor()
    }

    private var focusedButton: NSButton? {
        activeKeyboardViews
            .first(where: { isKeyboardViewFocused($0) }) as? NSButton
    }

    private func moveToActiveDisplay(size: NSSize) {
        let screens = NSScreen.screens
        let mainIndex = NSScreen.main.flatMap { main in
            screens.firstIndex(where: { $0 === main })
        }
        guard let index = QuickCuePanelPlacement.targetScreenIndex(
            pointer: NSEvent.mouseLocation,
            screenFrames: screens.map(\.frame),
            mainScreenIndex: mainIndex
        ), screens.indices.contains(index) else {
            return
        }
        let frame = QuickCuePanelPlacement.panelFrame(
            preferredSize: size,
            visibleFrame: screens[index].visibleFrame
        )
        updateAnimationBehavior()
        panel.setFrame(
            frame,
            display: true,
            animate: QuickCueMotionPolicy.shouldAnimate(
                panelIsVisible: panel.isVisible,
                reduceMotion: reduceMotion
            )
        )
    }
}

@MainActor
private final class QuickCuePanel: NSPanel {
    var onCancel: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
private class QuickCueActionButton: NSButton {
    override var acceptsFirstResponder: Bool {
        true
    }
}

@MainActor
private final class QuickCueCandidateButton: QuickCueActionButton {
    var slotID: UUID?
    var candidateID: EphemeralWindowIdentifier?
}

@MainActor
private final class QuickCueFlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}
