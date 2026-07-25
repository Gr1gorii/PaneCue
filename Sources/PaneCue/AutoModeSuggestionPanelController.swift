import AppKit
import PaneCueCore
import SwiftUI

@MainActor
final class AutoModeSuggestionPanelController {
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 390,
                height: 174
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.sharingType = .readOnly
        panel.title = "PaneCue Auto Mode"
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show(
        suggestion: AutoModeSuggestion,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let rootView = AutoModeSuggestionView(
            suggestion: suggestion,
            onApply: { [weak self] in
                self?.hide()
                onApply()
            },
            onDismiss: { [weak self] in
                self?.hide()
                onDismiss()
            }
        )
        panel.contentViewController = NSHostingController(
            rootView: rootView
        )

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.maxX - panel.frame.width - 18,
                    y: visibleFrame.maxY - panel.frame.height - 18
                )
            )
        }

        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct AutoModeSuggestionView: View {
    let suggestion: AutoModeSuggestion
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.purple.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 11)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Mode suggests")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(suggestion.scenario.title)
                        .font(.headline)
                }
                Spacer()
            }

            Text(suggestion.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 390, height: 174)
        .background(
            .ultraThickMaterial,
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.1))
        }
    }
}
