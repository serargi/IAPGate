import Foundation
import CloudGateCore

/// Parameters identifying the IAP tunnel target.
public struct IAPTarget: Sendable, Equatable {
    public let project: String
    public let zone: String
    public let instance: String
    public let interface: String
    public let port: Int

    public init(project: String, zone: String, instance: String, interface: String = "nic0", port: Int) {
        self.project = project
        self.zone = zone
        self.instance = instance
        self.interface = interface
        self.port = port
    }
}

/// Builds the IAP connect URL. Pure and tested.
public enum IAPConnectURL {
    public static let host = "tunnel.cloudproxy.app"
    public static let path = "/v4/connect"
    public static let subprotocol = "relay.tunnel.cloudproxy.app"
    public static let origin = "bot:iap-tunneler"

    public static func make(_ target: IAPTarget) -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "project", value: target.project),
            URLQueryItem(name: "zone", value: target.zone),
            URLQueryItem(name: "instance", value: target.instance),
            URLQueryItem(name: "interface", value: target.interface),
            URLQueryItem(name: "port", value: String(target.port))
        ]
        return components.url!
    }
}

/// A live IAP tunnel over a WebSocket. Presents a simple byte-stream
/// API: `send(_:)` to push bytes toward the VM, and an `onData`
/// callback for bytes coming back. Handles the relay framing and ACKs.
///
/// Built on `URLSessionWebSocketTask` (system framework): TLS and proxy
/// handling come from the OS, and no third-party WebSocket dependency
/// is introduced.
public final class IAPTunnel: NSObject, @unchecked Sendable {

    public enum State: Sendable, Equatable {
        case connecting
        case connected(sessionID: String)
        case closed(CloudGateError?)
    }

    private let target: IAPTarget
    private let accessToken: String
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    private let lock = NSLock()
    private var receivedBytes: UInt64 = 0
    private var ackedReceived: UInt64 = 0
    private var connected = false
    /// Bytes to send that arrived before the tunnel reported connected.
    /// Flushed in order once the SUCCESS frame is received.
    private var pendingOutbound: [Data] = []

    /// Called with decoded payload bytes arriving from the VM.
    public var onData: (@Sendable (Data) -> Void)?
    /// Called once when the tunnel connects (session established).
    public var onConnect: (@Sendable (String) -> Void)?
    /// Called once when the tunnel closes (cleanly or with an error).
    public var onClose: (@Sendable (CloudGateError?) -> Void)?

    public init(
        target: IAPTarget,
        accessToken: String,
        session: URLSession? = nil
    ) {
        self.target = target
        self.accessToken = accessToken
        // A dedicated session with no timeout on the resource keeps the
        // long-lived tunnel task alive (shared session can time out).
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 0          // no request timeout
            config.timeoutIntervalForResource = 0          // no resource timeout
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    public func start() {
        let url = IAPConnectURL.make(target)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(IAPConnectURL.origin, forHTTPHeaderField: "Origin")
        request.setValue(IAPConnectURL.subprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")

        // With a URLRequest, the subprotocol is carried by the
        // Sec-WebSocket-Protocol header set above.
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receive()
    }

    /// Sends raw bytes toward the VM, chunked into DATA frames. If the
    /// tunnel isn't connected yet (no SUCCESS frame), the bytes are
    /// queued and flushed in order once it connects.
    public func send(_ bytes: Data) {
        lock.lock()
        let isConnected = connected
        if !isConnected { pendingOutbound.append(bytes) }
        lock.unlock()
        if isConnected { writeChunks(bytes) }
    }

    private func writeChunks(_ bytes: Data) {
        guard let task else { return }
        var offset = bytes.startIndex
        while offset < bytes.endIndex {
            let end = bytes.index(offset, offsetBy: IAPFrame.maxFrameSize, limitedBy: bytes.endIndex) ?? bytes.endIndex
            let chunk = bytes.subdata(in: offset..<end)
            let frame = IAPFrame.data(chunk).encoded()
            task.send(.data(frame)) { _ in }
            offset = end
        }
    }

    private func flushPending() {
        lock.lock()
        let queued = pendingOutbound
        pendingOutbound.removeAll()
        lock.unlock()
        for data in queued { writeChunks(data) }
    }

    public func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - Receive loop

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(with: .make(.iapTunnelFailed,
                    userMessage: "The IAP tunnel connection was lost: \(error.localizedDescription)",
                    technicalDetail: "ws receive error"))
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleIncoming(data)
                case .string(let s):
                    self.handleIncoming(Data(s.utf8))
                @unknown default:
                    break
                }
                self.receive()
            }
        }
    }

    /// A binary WebSocket message may contain one or more concatenated
    /// frames; decode them all.
    private func handleIncoming(_ message: Data) {
        var buffer = message
        while !buffer.isEmpty {
            do {
                let (frame, consumed) = try IAPFrame.decode(buffer)
                process(frame)
                buffer = buffer.subdata(in: (buffer.startIndex + consumed)..<buffer.endIndex)
            } catch {
                // Partial/truncated frame at the tail: nothing we can do
                // with a datagram WebSocket, so stop.
                break
            }
        }
    }

    private func process(_ frame: IAPFrame) {
        switch frame {
        case .success(let sid):
            lock.lock(); connected = true; lock.unlock()
            let sidString = sid.map { String(format: "%02x", $0) }.joined()
            onConnect?(sidString)
            flushPending()
        case .data(let payload):
            lock.lock()
            receivedBytes += UInt64(payload.count)
            let unacked = receivedBytes - ackedReceived
            let shouldAck = unacked > UInt64(IAPFrame.ackThreshold)
            if shouldAck { ackedReceived = receivedBytes }
            let ackValue = receivedBytes
            lock.unlock()

            onData?(payload)
            if shouldAck { sendAck(ackValue) }
        case .ack:
            break // send-side ack; retransmission unneeded over TCP
        case .unknown:
            break
        }
    }

    private func sendAck(_ n: UInt64) {
        task?.send(.data(IAPFrame.ack(n).encoded())) { _ in }
    }

    private func finish(with error: CloudGateError?) {
        onClose?(error)
        task = nil
    }
}
