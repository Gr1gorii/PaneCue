import Carbon.HIToolbox
import Foundation
import PaneCueCore

enum CustomScenarioHotKeyError: LocalizedError {
    case installationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .installationFailed(status):
            return "PaneCue could not install custom shortcut handling (\(status))."
        }
    }
}

final class CustomScenarioHotKeyController: @unchecked Sendable {
    private static let signature: OSType = 0x50435332

    private let action: @Sendable (UUID) -> Void
    private var scenarioIDs: [UInt32: UUID] = [:]
    private var hotKeyReferences: [EventHotKeyRef] = []
    private var eventHandlerReference: EventHandlerRef?

    private(set) var unavailableShortcuts: [String] = []

    init(
        scenarios: [CustomScenario],
        action: @escaping @Sendable (UUID) -> Void
    ) throws {
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
                      hotKeyID.signature
                        == CustomScenarioHotKeyController.signature
                else {
                    return status
                }

                let controller = Unmanaged<
                    CustomScenarioHotKeyController
                >
                .fromOpaque(userData)
                .takeUnretainedValue()
                guard let scenarioID = controller.scenarioIDs[hotKeyID.id] else {
                    return OSStatus(eventNotHandledErr)
                }
                controller.action(scenarioID)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )

        guard handlerStatus == noErr else {
            throw CustomScenarioHotKeyError.installationFailed(
                handlerStatus
            )
        }

        var unavailable: [String] = []
        for (index, scenario) in scenarios.enumerated()
            where scenario.hotKey.isEnabled {
            guard let keyCode = Self.keyCode(for: scenario.hotKey.key) else {
                unavailable.append(scenario.hotKey.displayName)
                continue
            }

            let identifier = UInt32(index + 1_000)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode,
                Self.modifiers(for: scenario.hotKey),
                EventHotKeyID(
                    signature: Self.signature,
                    id: identifier
                ),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                unavailable.append(scenario.hotKey.displayName)
                continue
            }

            scenarioIDs[identifier] = scenario.id
            hotKeyReferences.append(reference)
        }
        unavailableShortcuts = unavailable
    }

    deinit {
        for reference in hotKeyReferences {
            UnregisterEventHotKey(reference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }

    private static func modifiers(
        for hotKey: ScenarioHotKey
    ) -> UInt32 {
        var modifiers: UInt32 = 0
        if hotKey.usesCommand { modifiers |= UInt32(cmdKey) }
        if hotKey.usesOption { modifiers |= UInt32(optionKey) }
        if hotKey.usesControl { modifiers |= UInt32(controlKey) }
        if hotKey.usesShift { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func keyCode(for key: String) -> UInt32? {
        keyCodes[String(key.uppercased().prefix(1))]
    }

    private static let keyCodes: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A),
        "B": UInt32(kVK_ANSI_B),
        "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D),
        "E": UInt32(kVK_ANSI_E),
        "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G),
        "H": UInt32(kVK_ANSI_H),
        "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J),
        "K": UInt32(kVK_ANSI_K),
        "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M),
        "N": UInt32(kVK_ANSI_N),
        "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P),
        "Q": UInt32(kVK_ANSI_Q),
        "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S),
        "T": UInt32(kVK_ANSI_T),
        "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V),
        "W": UInt32(kVK_ANSI_W),
        "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y),
        "Z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9)
    ]
}
