import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: LocalizedError {
    case installationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .installationFailed(status):
            return "PaneCue could not install the voice shortcut handler (\(status))."
        case let .registrationFailed(status):
            return "PaneCue could not register ⌥ Space (\(status))."
        }
    }
}

final class GlobalHotKeyController: @unchecked Sendable {
    private static let signature: OSType = 0x50437565
    private static let identifier: UInt32 = 1

    private let action: @Sendable () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(action: @escaping @Sendable () -> Void) throws {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == GlobalHotKeyController.signature,
                      hotKeyID.id == GlobalHotKeyController.identifier
                else {
                    return status
                }

                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )

        guard handlerStatus == noErr else {
            throw GlobalHotKeyError.installationFailed(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard registrationStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
            }
            self.eventHandlerReference = nil
            throw GlobalHotKeyError.registrationFailed(registrationStatus)
        }
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }
}
