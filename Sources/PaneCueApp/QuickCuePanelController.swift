import AppKit

@MainActor
final class QuickCuePanelController: NSObject, NSTextFieldDelegate {
    private static let preferredSize = NSSize(width: 620, height: 84)

    private let panel: QuickCuePanel
    private let commandField = NSTextField()
    private var session = QuickCuePanelSession()

    override init() {
        panel = QuickCuePanel(
            contentRect: NSRect(origin: .zero, size: Self.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    func present() {
        session.present()
        commandField.stringValue = session.draft
        moveToActiveDisplay()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(commandField)
    }

    func dismiss() {
        session.dismiss()
        commandField.stringValue = ""
        panel.orderOut(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        session.updateDraft(commandField.stringValue)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:))
        else {
            return false
        }
        dismiss()
        return true
    }

    private func configurePanel() {
        let visualEffect = NSVisualEffectView(
            frame: NSRect(origin: .zero, size: Self.preferredSize)
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

        let symbolView = NSImageView()
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.image = NSImage(
            systemSymbolName: "rectangle.split.2x1",
            accessibilityDescription: "Quick Cue"
        )
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 19,
            weight: .semibold
        )
        symbolView.contentTintColor = .controlAccentColor

        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.isBezeled = false
        commandField.drawsBackground = false
        commandField.focusRingType = .none
        commandField.font = .systemFont(ofSize: 20, weight: .medium)
        commandField.textColor = .labelColor
        commandField.placeholderString = "What should change?"
        commandField.lineBreakMode = .byTruncatingTail
        commandField.delegate = self
        commandField.setAccessibilityLabel("Quick Cue command")

        let escapeLabel = NSTextField(labelWithString: "esc")
        escapeLabel.translatesAutoresizingMaskIntoConstraints = false
        escapeLabel.font = .monospacedSystemFont(
            ofSize: 11,
            weight: .medium
        )
        escapeLabel.textColor = .tertiaryLabelColor
        escapeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let content = NSStackView(
            views: [symbolView, commandField, escapeLabel]
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 16
        visualEffect.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(
                equalTo: visualEffect.leadingAnchor,
                constant: 22
            ),
            content.trailingAnchor.constraint(
                equalTo: visualEffect.trailingAnchor,
                constant: -22
            ),
            content.topAnchor.constraint(
                equalTo: visualEffect.topAnchor,
                constant: 16
            ),
            content.bottomAnchor.constraint(
                equalTo: visualEffect.bottomAnchor,
                constant: -16
            ),
            symbolView.widthAnchor.constraint(equalToConstant: 28),
            symbolView.heightAnchor.constraint(equalToConstant: 28)
        ])

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

    private func moveToActiveDisplay() {
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
            preferredSize: Self.preferredSize,
            visibleFrame: screens[index].visibleFrame
        )
        panel.setFrame(frame, display: true)
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
