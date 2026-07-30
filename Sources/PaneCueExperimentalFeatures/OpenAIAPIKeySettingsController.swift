import AppKit
import Carbon.HIToolbox

private final class PasteEnabledSecureTextField: NSSecureTextField {
    var didPaste: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift
        ])

        guard event.type == .keyDown,
              modifiers == .command,
              event.keyCode == UInt16(kVK_ANSI_V)
        else {
            return super.performKeyEquivalent(with: event)
        }

        guard let value = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return true
        }

        stringValue = value
        didPaste?()
        window?.makeFirstResponder(self)
        return true
    }
}

@MainActor
final class OpenAIAPIKeySettingsController: NSObject, NSTextFieldDelegate {
    private let keyStore: OpenAIAPIKeyStore
    private weak var activeSecureField: NSSecureTextField?
    private weak var characterCountLabel: NSTextField?

    init(keyStore: OpenAIAPIKeyStore) {
        self.keyStore = keyStore
        super.init()
    }

    func present() throws -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let hasExistingKey = keyStore.hasKey
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = hasExistingKey
            ? "OpenAI API key is configured"
            : "Connect voice commands"
        alert.informativeText = hasExistingKey
            ? "Paste a new key only if you want to replace the current one. PaneCue never displays the saved key."
            : "Paste the full secret key. PaneCue stores it only in macOS Keychain and never displays it again."

        let secureField = PasteEnabledSecureTextField(
            frame: NSRect(x: 0, y: 0, width: 360, height: 26)
        )
        secureField.delegate = self
        secureField.didPaste = { [weak self] in
            self?.updateCharacterCount()
        }
        secureField.placeholderString = hasExistingKey
            ? "Paste a replacement key with ⌘V"
            : "Paste API key with ⌘V"

        let characterCountLabel = NSTextField(
            labelWithString: "No value pasted"
        )
        characterCountLabel.font = .systemFont(ofSize: 11)
        characterCountLabel.textColor = .secondaryLabelColor

        let pasteButton = NSButton(
            title: "Paste from Clipboard",
            target: self,
            action: #selector(pasteFromClipboard)
        )
        pasteButton.bezelStyle = .rounded

        let detailRow = NSStackView(views: [
            characterCountLabel,
            NSView(),
            pasteButton
        ])
        detailRow.orientation = .horizontal
        detailRow.alignment = .centerY
        detailRow.spacing = 8

        let accessory = NSStackView(views: [secureField, detailRow])
        accessory.frame = NSRect(x: 0, y: 0, width: 380, height: 62)
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        secureField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        detailRow.widthAnchor.constraint(equalToConstant: 380).isActive = true
        alert.accessoryView = accessory

        alert.addButton(withTitle: hasExistingKey ? "Replace Key" : "Save Key")
        alert.addButton(withTitle: "Cancel")
        if hasExistingKey {
            alert.addButton(withTitle: "Remove Key")
        }

        activeSecureField = secureField
        self.characterCountLabel = characterCountLabel
        alert.window.initialFirstResponder = secureField
        alert.window.makeFirstResponder(secureField)
        let response = alert.runModal()
        activeSecureField = nil
        self.characterCountLabel = nil

        switch response {
        case .alertFirstButtonReturn:
            try keyStore.save(secureField.stringValue)
            presentSavedConfirmation()
            return "OpenAI API key saved in Keychain"
        case .alertThirdButtonReturn:
            try keyStore.delete()
            return "OpenAI API key removed"
        default:
            return nil
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        updateCharacterCount()
    }

    @objc
    private func pasteFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            characterCountLabel?.stringValue = "Clipboard contains no text"
            NSSound.beep()
            return
        }

        activeSecureField?.stringValue = value
        updateCharacterCount()
        activeSecureField?.window?.makeFirstResponder(activeSecureField)
    }

    private func updateCharacterCount() {
        let count = activeSecureField?.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count ?? 0
        characterCountLabel?.stringValue = count == 0
            ? "No value pasted"
            : "Pasted: \(count) characters"
    }

    private func presentSavedConfirmation() {
        let confirmation = NSAlert()
        confirmation.alertStyle = .informational
        confirmation.messageText = "API key saved"
        confirmation.informativeText = "The key is now in macOS Keychain. Use Voice Command from PaneCue when Cloud mode is selected."
        confirmation.addButton(withTitle: "OK")
        confirmation.runModal()
    }
}
