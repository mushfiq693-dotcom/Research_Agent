import Foundation
import Network
import OSLog

@MainActor
public final class ConnectivityMonitor: ObservableObject {
    public static let shared = ConnectivityMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.personalresearchagent.connectivity", qos: .utility)
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "ConnectivityMonitor")
    
    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var isExpensive: Bool = false
    @Published public private(set) var isConstrained: Bool = false
    
    private var isStarted = false
    
    private init() {
        start()
    }
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let connected = (path.status == .satisfied)
                let expensive = path.isExpensive
                let constrained = path.isConstrained
                
                self.isConnected = connected
                self.isExpensive = expensive
                self.isConstrained = constrained
                
                self.logger.info("Network connectivity changed: connected=\(connected), expensive=\(expensive)")
            }
        }
        monitor.start(queue: queue)
    }
    
    public func stop() {
        guard isStarted else { return }
        monitor.cancel()
        isStarted = false
    }
    
    public func checkCurrentConnection() -> Bool {
        return monitor.currentPath.status == .satisfied
    }
}
