import CoreGraphics

enum VerifiedWindowFrameMutation {
    static func set(
        targetFrame: CGRect,
        applicationName: String,
        tolerance: CGFloat = 8,
        maximumAttemptCount: Int = 3,
        readFrame: () -> CGRect?,
        writeFrame: () throws -> Void,
        recoverConstrainedWindow: (() throws -> Bool)? = nil,
        settle: () -> Void
    ) throws {
        let attemptCount = max(1, maximumAttemptCount)
        var lastWriteError: Error?

        func attemptVerifiedWrites() -> Bool {
            for attempt in 0 ..< attemptCount {
                do {
                    try writeFrame()
                } catch {
                    lastWriteError = error
                }
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

        if attemptVerifiedWrites() {
            return
        }

        if let recoverConstrainedWindow,
           try recoverConstrainedWindow() {
            // Native Window-menu placements are animated by AppKit. Safari in
            // particular can report the old frame briefly after accepting the
            // menu action, so poll before falling back to direct AX writes.
            for _ in 0 ..< attemptCount {
                settle()
                if let recoveredFrame = readFrame(),
                   framesApproximatelyEqual(
                       recoveredFrame,
                       targetFrame,
                       tolerance: tolerance
                   ) {
                    return
                }
            }
            if attemptVerifiedWrites() {
                return
            }
        }

        if let lastWriteError {
            throw lastWriteError
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
