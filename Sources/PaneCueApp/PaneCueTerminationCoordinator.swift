import Foundation

@MainActor
final class PaneCueTerminationCoordinator {
    struct Request {
        let task: Task<Void, Never>
        let startedCleanup: Bool
    }

    private var cleanupTask: Task<Void, Never>?
    private(set) var isComplete = false

    func begin(
        cleanup: @escaping @MainActor () async -> Void
    ) -> Request {
        if let cleanupTask {
            return Request(
                task: cleanupTask,
                startedCleanup: false
            )
        }

        let task = Task { @MainActor [weak self] in
            await cleanup()
            self?.isComplete = true
        }
        cleanupTask = task
        return Request(task: task, startedCleanup: true)
    }
}
