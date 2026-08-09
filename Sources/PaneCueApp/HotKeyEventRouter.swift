import Carbon.HIToolbox

enum HotKeyEventRouter {
    static func rejectionStatus(
        readStatus: OSStatus,
        receivedSignature: OSType,
        expectedSignature: OSType,
        receivedIdentifier: UInt32? = nil,
        expectedIdentifier: UInt32? = nil
    ) -> OSStatus? {
        guard readStatus == noErr else {
            return readStatus
        }
        guard receivedSignature == expectedSignature else {
            return OSStatus(eventNotHandledErr)
        }
        if let expectedIdentifier,
           receivedIdentifier != expectedIdentifier {
            return OSStatus(eventNotHandledErr)
        }
        return nil
    }
}
