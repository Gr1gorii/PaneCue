import CoreGraphics
import Testing
@testable import PaneCueCore

@Suite("Verified window frame mutation")
struct VerifiedWindowFrameMutationTests {
    @Test
    func retriesAfterAnApplicationIgnoresTheFirstWrite() throws {
        let target = CGRect(x: 40, y: 80, width: 1_200, height: 800)
        var current = CGRect(x: 0, y: 0, width: 600, height: 500)
        var writeCount = 0
        var settleCount = 0

        try VerifiedWindowFrameMutation.set(
            targetFrame: target,
            applicationName: "Browser",
            readFrame: { current },
            writeFrame: {
                writeCount += 1
                if writeCount == 2 {
                    current = target
                }
            },
            settle: {
                settleCount += 1
            }
        )

        #expect(writeCount == 2)
        #expect(settleCount == 1)
        #expect(current == target)
    }

    @Test
    func acceptsAFrameInsideTheAccessibilityTolerance() throws {
        let target = CGRect(x: 40, y: 80, width: 1_200, height: 800)
        var writeCount = 0

        try VerifiedWindowFrameMutation.set(
            targetFrame: target,
            applicationName: "Browser",
            readFrame: {
                CGRect(x: 44, y: 76, width: 1_204, height: 796)
            },
            writeFrame: {
                writeCount += 1
            },
            settle: {
                Issue.record("A verified frame should not wait or retry")
            }
        )

        #expect(writeCount == 1)
    }

    @Test
    func rejectsALyingAccessibilityWrite() {
        let target = CGRect(x: 40, y: 80, width: 1_200, height: 800)
        var writeCount = 0
        var settleCount = 0

        #expect(throws: PaneCueWindowError.self) {
            try VerifiedWindowFrameMutation.set(
                targetFrame: target,
                applicationName: "Browser",
                readFrame: {
                    CGRect(x: 0, y: 0, width: 600, height: 500)
                },
                writeFrame: {
                    writeCount += 1
                },
                settle: {
                    settleCount += 1
                }
            )
        }

        #expect(writeCount == 3)
        #expect(settleCount == 2)
    }

    @Test
    func acceptsAFrameAppliedBySystemRecovery() throws {
        let target = CGRect(x: 40, y: 80, width: 1_200, height: 800)
        var current = CGRect(x: 0, y: 0, width: 600, height: 500)
        var writeCount = 0
        var recoveryCount = 0

        try VerifiedWindowFrameMutation.set(
            targetFrame: target,
            applicationName: "Browser",
            readFrame: { current },
            writeFrame: {
                writeCount += 1
            },
            recoverConstrainedWindow: {
                recoveryCount += 1
                current = target
                return true
            },
            settle: {}
        )

        #expect(writeCount == 3)
        #expect(recoveryCount == 1)
        #expect(current == target)
    }

    @Test
    func recoversAfterTheApplicationRejectsDirectWrites() throws {
        let target = CGRect(x: 40, y: 80, width: 1_200, height: 800)
        var current = CGRect(x: 0, y: 0, width: 600, height: 500)
        var writeCount = 0
        var recoveryCount = 0

        try VerifiedWindowFrameMutation.set(
            targetFrame: target,
            applicationName: "Browser",
            readFrame: { current },
            writeFrame: {
                writeCount += 1
                throw PaneCueWindowError.operationFailed(
                    details: "Direct AX mutation rejected"
                )
            },
            recoverConstrainedWindow: {
                recoveryCount += 1
                current = target
                return true
            },
            settle: {}
        )

        #expect(writeCount == 3)
        #expect(recoveryCount == 1)
        #expect(current == target)
    }

    @Test
    func waitsForAnAnimatedSystemRecoveryToReachItsTarget() throws {
        let target = CGRect(x: 40, y: 80, width: 1_200, height: 800)
        let original = CGRect(x: 0, y: 0, width: 600, height: 500)
        var current = original
        var didRecover = false
        var recoveryReadCount = 0
        var settleCount = 0

        try VerifiedWindowFrameMutation.set(
            targetFrame: target,
            applicationName: "Safari",
            readFrame: {
                if didRecover {
                    recoveryReadCount += 1
                    if recoveryReadCount == 3 {
                        current = target
                    }
                }
                return current
            },
            writeFrame: {},
            recoverConstrainedWindow: {
                didRecover = true
                return true
            },
            settle: {
                settleCount += 1
            }
        )

        #expect(recoveryReadCount == 3)
        #expect(settleCount == 5)
        #expect(current == target)
    }

}
