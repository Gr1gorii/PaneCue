import CoreGraphics

enum VerifiedWindowFrameMutation {
    static func set(
        targetFrame: CGRect,
        applicationName: String,
        tolerance: CGFloat = 8,
        maximumAttemptCount: Int = 3,
        readFrame: () -> CGRect?,
        writeFrame: () throws -> Void,
        settle: () -> Void
    ) throws {
        let attemptCount = max(1, maximumAttemptCount)

        func attemptVerifiedWrites() throws -> Bool {
            for attempt in 0 ..< attemptCount {
                try writeFrame()
                if let appliedFrame = readFrame(),
                   framesApproximatelyEqual(
                       appliedFrame,
                       targetFrame,
                       tolerance: tolerance
                   ) {
                    return true
                }
                if attempt + 1 < attemptCount {
                    settle()
                }
            }
            return false
        }

        if try attemptVerifiedWrites() {
            return
        }

        throw PaneCueWindowError.operationFailed(
            details: "\(applicationName) did not accept the requested window size and position."
        )
    }

    static func framesApproximatelyEqual(
        _ first: CGRect,
        _ second: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance
            && abs(first.height - second.height) <= tolerance
    }
}
