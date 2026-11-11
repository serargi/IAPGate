import Foundation
import Network
import CloudGateCore

/// Bridges a local loopback TCP port to an IAP tunnel.
///
/// Listens on 127.0.0.1 with an ephemeral port. For the (single) local
/// connection, it opens an `IAPTunnel` to the target VM and pumps bytes
/// both ways: local→tunnel and tunnel→local. SSH/RDP clients connect to
/// the local port and are unaware of IAP.
///
/// Security (SECURITY.md / THREAT_MODEL 1, 6): binds to loopback only,
/// ephemeral port, and tears everything down on close/failure.
public final class LoopbackForwarder: @unchecked Sendable {

    private let target: IAPTarget
    private let accessToken: String
    private var listener: NWListener?
    private var tunnel: IAPTunnel?
    private var connection: NWConnection?
    private let lock = NSLock()

    /// Called once the local listener is ready, with the chosen port.
    public var onListening: (@Sendable (UInt16) -> Void)?
    /// Called when the forwarder stops (cleanly or with an error).
    public var onClose: (@Sendable (CloudGateError?) -> Void)?

    public init(target: IAPTarget, accessToken: String) {
        self.target = target
        self.accessToken = accessToken
    }

    /// Starts listening on an ephemeral loopback port.
    public func start() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = listener.port?.rawValue {
                self?.onListening?(port)
            }
            if case .failed = state {
                self?.stop(error: .make(.localPortUnavailable,
                    userMessage: "Could not open the local port.",
                    technicalDetail: "NWListener failed"))
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    public func stop(error: CloudGateError? = nil) {
        lock.lock()
        let conn = connection; let tun = tunnel; let lis = listener
        connection = nil; tunnel = nil; listener = nil
        lock.unlock()

        conn?.cancel()
        tun?.close()
        lis?.cancel()
        onClose?(error)
    }

    // MARK: - Local connection

    private func accept(_ conn: NWConnection) {
        lock.lock()
        // Only one active session per forwarder; reject extras.
        guard connection == nil else { lock.unlock(); conn.cancel(); return }
        connection = conn
        lock.unlock()

        let tunnel = IAPTunnel(target: target, accessToken: accessToken)
        self.tunnel = tunnel

        // Tunnel → local
        tunnel.onData = { [weak self] data in
            self?.connection?.send(content: data, completion: .contentProcessed { _ in })
        }
        tunnel.onClose = { [weak self] err in
            self?.stop(error: err)
        }

        conn.start(queue: .global(qos: .userInitiated))
        tunnel.start()
        // The IAP tunnel buffers outbound bytes until the WebSocket is
        // open, so it's safe to start pumping immediately; SSH's first
        // bytes are queued and flushed once connected.
        pumpLocalToTunnel(conn, tunnel)
    }

    /// Local → tunnel: continuously read from the local socket and push
    /// into the tunnel.
    private func pumpLocalToTunnel(_ conn: NWConnection, _ tunnel: IAPTunnel) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: IAPFrame.maxFrameSize) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                tunnel.send(data)
            }
            if isComplete || error != nil {
                self.stop(error: error == nil ? nil : .make(.iapTunnelFailed,
                    userMessage: "The local connection was interrupted.",
                    technicalDetail: "local recv error"))
                return
            }
            self.pumpLocalToTunnel(conn, tunnel)
        }
    }
}
