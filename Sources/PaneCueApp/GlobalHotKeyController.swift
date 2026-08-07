import Carbon.HIToolbox
import Foundation
import OSLog

enum GlobalHotKeyError: LocalizedError {
    case installationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var shortcutStatus: QuickCueShortcutStatus {
        switch self {
        case let .registrationFailed(status)
            where status == OSStatus(eventHotKeyExistsErr):
            return .conflict
        case .installationFailed, .registrationFailed:
            return .unavailable
        }
    }

    var errorDescription: String? {
        switch self {
        case let .installationFailed(status):
            return "PaneCue could not install the Quick Cue shortcut handler (\(status))."
        case let .registrationFailed(status)
            where status == OSStatus(eventHotKeyExistsErr):
            return "⌥ Space is already used by another application."
        case let .registrationFailed(status):
            return "PaneCue could not register ⌥ Space (\(status))."
        }
    }
}

enum QuickCueShortcutStatus: Equatable, Sendable {
    case active
    case conflict
    case unavailable

    var title: String {
        switch self {
        case .active:
            return "Available"
        case .conflict:
            return "Conflict"
        case .unavailable:
            return "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .active:
            return "Press ⌥ Space from any application"
        case .conflict:
            return "Another application already uses ⌥ Space"
        case .unavailable:
            return "The global shortcut could not be registered"
        }
    }
}

final class GlobalHotKeyController: @unchecked Sendable {
    private static let signature: OSType = 0x50437565
    private static let identifier: UInt32 = 1
    private static let logger = Logger(
        subsystem: "io.github.gr1gorii.PaneCue",
        category: "QuickCueHotKey"
    )

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
                if let rejectionStatus = HotKeyEventRouter.rejectionStatus(
                    readStatus: status,
                    receivedSignature: hotKeyID.signature,
                    expectedSignature: GlobalHotKeyController.signature,
                    receivedIdentifier: hotKeyID.id,
                    expectedIdentifier: GlobalHotKeyController.identifier
                ) {
                    return rejectionStatus
                }

                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                GlobalHotKeyController.logger.notice("Quick Cue hotkey received")
                controller.action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )

        guard handlerStatus == noErr else {
            Self.logger.error("Quick Cue hotkey handler installation failed")
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
            Self.logger.error("Quick Cue hotkey registration failed")
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
            }
            self.eventHandlerReference = nil
            throw GlobalHotKeyError.registrationFailed(registrationStatus)
        }
        Self.logger.notice("Quick Cue hotkey registered")
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
