import Combine
import Foundation
import Network
import PaneCueCore

@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline = true

    var statusDidChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: PaneCueIdentity.subsystem("connectivity"),
        qos: .utility
    )

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let online = path.status == .satisfied
                guard self.isOnline != online else {
                    return
                }
                self.isOnline = online
                self.statusDidChange?(online)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
