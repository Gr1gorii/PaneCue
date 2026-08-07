import Foundation
import PaneCueCore

struct PaneCueLinkActions {
    let show: @MainActor () -> Void
    let previewCommand: @MainActor (String) -> Void
    let previewCue: @MainActor (UUID) -> Void
}

/// Owns the application-lifecycle boundary for external links. Its action
/// surface intentionally has no Apply operation.
@MainActor
final class PaneCueLinkController {
    private let actions: PaneCueLinkActions
    private var gate = PaneCueLinkAdmissionGate()
    private var pendingRequest: PaneCueLinkRequest?
    private var isApplicationReady = false

    init(actions: PaneCueLinkActions) {
        self.actions = actions
    }

    func applicationDidBecomeReady() {
        isApplicationReady = true
        guard let pendingRequest else {
            return
        }
        self.pendingRequest = nil
        dispatch(pendingRequest)
    }

    @discardableResult
    func receive(
        _ urls: [URL],
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> [PaneCueLinkAdmission] {
        urls.map { url in
            let admission = gate.admit(url, at: time)
            guard case let .accepted(request) = admission else {
                return admission
            }
            guard isApplicationReady else {
                pendingRequest = request
                return admission
            }
            dispatch(request)
            return admission
        }
    }

    private func dispatch(_ request: PaneCueLinkRequest) {
        switch request {
        case .show:
            actions.show()
        case let .preview(command):
            actions.previewCommand(command)
        case let .cue(id):
            actions.previewCue(id)
        }
    }
}
