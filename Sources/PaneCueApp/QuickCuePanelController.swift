import AppKit
import PaneCueCore

struct QuickCuePanelActions {
    let preparePreview: @MainActor
        (String) async throws -> ArrangementPreview
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
        session.present()
        render()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if session.canEditCommand {
            panel.makeFirstResponder(commandField)
        }
    }

    func dismiss() {
        dismiss(discardPreview: true)
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
        contentStack.alignment = .leading
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
        commandField.focusRingType = .none
        commandField.font = .systemFont(ofSize: 20, weight: .medium)
        commandField.textColor = .labelColor
        commandField.placeholderString = "What should change?"
        commandField.lineBreakMode = .byTruncatingTail
        commandField.delegate = self
        commandField.setAccessibilityLabel("Quick Cue command")

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
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
    }

    private func render() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        commandField.stringValue = session.draft
        commandField.isEditable = session.canEditCommand
        commandField.isSelectable = session.canEditCommand
        contentStack.addArrangedSubview(makeCommandRow())

        switch session.phase {
        case .composing:
            if let error = session.errorMessage {
                contentStack.addArrangedSubview(makeMessageRow(
                    error,
                    systemImage: "exclamationmark.triangle.fill",
                    color: .systemOrange
                ))
            }
        case .preparing:
            contentStack.addArrangedSubview(makeProgressRow(
                "Creating a safe Preview…"
            ))
        case .preview, .applying:
            if let preview = session.preview {
                contentStack.addArrangedSubview(makePreviewView(preview))
            }
            if session.phase == .applying {
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
    }

    private var preferredHeight: CGFloat {
        switch session.phase {
        case .composing:
            return session.errorMessage == nil ? 84 : 126
        case .preparing:
            return 126
        case .preview, .applying:
            let count = CGFloat(session.preview?.plan.windows.count ?? 0)
            let base: CGFloat = session.phase == .applying ? 166 : 202
            return base + count * 44
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
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 28),
            symbolView.heightAnchor.constraint(equalToConstant: 28)
        ])

        let hint = NSTextField(
            labelWithString: session.canEditCommand ? "↵" : "esc"
        )
        hint.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        hint.textColor = .tertiaryLabelColor
        hint.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [symbolView, commandField, hint])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func makeProgressRow(_ title: String) -> NSView {
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        let row = NSStackView(views: [progress, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        return row
    }

    private func makePreviewView(_ preview: ArrangementPreview) -> NSView {
        let presentation = QuickCuePreviewPresentation(preview: preview)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
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
            labelWithString: [slot.display, slot.detail]
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
        return row
    }

    private func makePreviewButtons() -> NSView {
        let cancel = makeButton(
            title: "Cancel",
            action: #selector(cancelPreview)
        )
        let edit = makeButton(
            title: "Edit Full Plan",
            action: #selector(editFullPlan)
        )
        let apply = makeButton(
            title: "Apply \(session.preview?.plan.windows.count ?? 0) Windows",
            action: #selector(applyPreview)
        )
        apply.bezelColor = .controlAccentColor
        apply.isEnabled = session.preview?.eligibility == .ready
        apply.keyEquivalent = "\r"
        apply.keyEquivalentModifierMask = [.command]
        return makeButtonRow([cancel, edit, apply])
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
        action: Selector
    ) -> NSButton {
        let button = NSButton(
            title: title,
            target: self,
            action: action
        )
        button.bezelStyle = .rounded
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

    private func submitCommand() {
        commandField.stringValue = session.draft
        guard case let .preparePreview(command) = session.submitCommand()
        else {
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
                let preview = try await actions.preparePreview(command)
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
        dismiss(discardPreview: false)
        actions.editFullPlan(preview)
    }

    @objc
    private func cancelPreview() {
        dismiss()
    }

    private func dismiss(discardPreview: Bool) {
        operationTask?.cancel()
        operationTask = nil
        session.dismiss()
        commandField.stringValue = ""
        panel.orderOut(nil)
        if discardPreview {
            Task { @MainActor [actions] in
                await actions.discardPreview()
            }
        }
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
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }
}

@MainActor
private final class QuickCuePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
