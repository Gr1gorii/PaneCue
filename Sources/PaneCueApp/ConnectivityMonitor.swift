import Combine
import Foundation
import Network
import PaneCueCore

@MainActor
public final class ConnectivityMonitor: ObservableObject {
    @Published public private(set) var isOnline = true

    public var statusDidChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: PaneCueIdentity.subsystem("connectivity"),
        qos: .utility
    )

    public init() {
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
