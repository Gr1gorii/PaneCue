import AppKit

@MainActor
final class VoiceCommandHUDController {
    private let panel: NSPanel
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let size = NSSize(width: 320, height: 86)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let visualEffect = NSVisualEffectView(
            frame: NSRect(origin: .zero, size: size)
        )
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 20
        visualEffect.layer?.masksToBounds = true
        panel.contentView = visualEffect

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 24,
            weight: .semibold
        )

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let row = NSStackView(views: [symbolView, labels])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        visualEffect.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 22),
            row.trailingAnchor.constraint(lessThanOrEqualTo: visualEffect.trailingAnchor, constant: -22),
            row.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 30),
            symbolView.heightAnchor.constraint(equalToConstant: 30)
        ])

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.sharingType = .none
    }

    func showListening() {
        show(
            symbol: "mic.fill",
            title: "Слушаю…",
            detail: "Повторите Voice Command, чтобы выполнить",
            tint: .systemRed
        )
    }

    func showProcessing() {
        show(
            symbol: "waveform",
            title: "Подбираю сценарий…",
            detail: "PaneCue анализирует только эту команду",
            tint: .systemBlue
        )
    }

    func showSuccess(_ message: String) {
        show(
            symbol: "checkmark.circle.fill",
            title: "Готово",
            detail: message,
            tint: .systemGreen
        )
        hide(after: 1.8)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel.orderOut(nil)
    }

    private func show(
        symbol: String,
        title: String,
        detail: String,
        tint: NSColor
    ) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        symbolView.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )
        symbolView.contentTintColor = tint
        titleLabel.stringValue = title
        detailLabel.stringValue = detail

        if let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let panelSize = panel.frame.size
            panel.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.midX - panelSize.width / 2,
                    y: visibleFrame.maxY - panelSize.height - 28
                )
            )
        }

        panel.orderFrontRegardless()
    }

    private func hide(after delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }
}
