import Foundation

/// Wire framing for the IAP TCP-forwarding relay (v4 subprotocol).
///
/// Verified against the reference implementation cedws/iapc. All
/// integers are big-endian. A frame is a `uint16` tag followed by a
/// tag-specific payload. See docs/IAP_TRANSPORT.md.
public enum IAPFrame: Equatable, Sendable {
    /// Relay → client, first frame: carries the session ID.
    case success(sessionID: Data)
    /// Tunneled payload bytes (either direction).
    case data(Data)
    /// Acknowledged running byte count (either direction).
    case ack(UInt64)
    /// A tag we don't handle; ignored per spec.
    case unknown(tag: UInt16)

    public enum Tag: UInt16 {
        case success = 0x0001
        case data = 0x0004
        case ack = 0x0007
    }

    /// Max payload per DATA frame; outgoing data is chunked to this.
    public static let maxFrameSize = 16384

    /// Send an ACK once this many unacked received bytes accumulate.
    public static let ackThreshold = 2 * maxFrameSize

    // MARK: - Encoding

    public func encoded() -> Data {
        switch self {
        case .success(let sessionID):
            var out = Data()
            out.appendBigEndian(UInt16(Tag.success.rawValue))
            out.appendBigEndian(UInt32(sessionID.count))
            out.append(sessionID)
            return out
        case .data(let payload):
            var out = Data()
            out.appendBigEndian(UInt16(Tag.data.rawValue))
            out.appendBigEndian(UInt32(payload.count))
            out.append(payload)
            return out
        case .ack(let n):
            var out = Data()
            out.appendBigEndian(UInt16(Tag.ack.rawValue))
            out.appendBigEndian(n)
            return out
        case .unknown(let tag):
            var out = Data()
            out.appendBigEndian(tag)
            return out
        }
    }

    public static func dataFrame(_ payload: Data) -> IAPFrame { .data(payload) }
    public static func ackFrame(_ n: UInt64) -> IAPFrame { .ack(n) }

    // MARK: - Decoding

    public enum DecodeError: Error, Equatable {
        case truncated
        case oversized
    }

    /// Decodes a single frame from `data` starting at offset 0.
    /// Returns the frame and the number of bytes consumed. A WebSocket
    /// binary message may carry one or more concatenated frames.
    public static func decode(_ data: Data) throws -> (frame: IAPFrame, consumed: Int) {
        guard data.count >= 2 else { throw DecodeError.truncated }
        let tag = data.readBigEndianUInt16(at: 0)

        switch Tag(rawValue: tag) {
        case .success:
            guard data.count >= 6 else { throw DecodeError.truncated }
            let len = Int(data.readBigEndianUInt32(at: 2))
            guard len <= maxFrameSize else { throw DecodeError.oversized }
            guard data.count >= 6 + len else { throw DecodeError.truncated }
            let sid = data.subdata(in: (data.startIndex + 6)..<(data.startIndex + 6 + len))
            return (.success(sessionID: sid), 6 + len)

        case .data:
            guard data.count >= 6 else { throw DecodeError.truncated }
            let len = Int(data.readBigEndianUInt32(at: 2))
            guard len <= maxFrameSize else { throw DecodeError.oversized }
            guard data.count >= 6 + len else { throw DecodeError.truncated }
            let payload = data.subdata(in: (data.startIndex + 6)..<(data.startIndex + 6 + len))
            return (.data(payload), 6 + len)

        case .ack:
            guard data.count >= 10 else { throw DecodeError.truncated }
            let n = data.readBigEndianUInt64(at: 2)
            return (.ack(n), 10)

        case .none:
            // Unknown tag: consume just the tag; payload handling for
            // unknown tags is undefined, so we stop after the tag.
            return (.unknown(tag: tag), 2)
        }
    }
}

// MARK: - Big-endian helpers

extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
    mutating func appendBigEndian(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }
    mutating func appendBigEndian(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    func readBigEndianUInt16(at offset: Int) -> UInt16 {
        let i = startIndex + offset
        return (UInt16(self[i]) << 8) | UInt16(self[i + 1])
    }
    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        var v: UInt32 = 0
        for k in 0..<4 { v = (v << 8) | UInt32(self[i + k]) }
        return v
    }
    func readBigEndianUInt64(at offset: Int) -> UInt64 {
        let i = startIndex + offset
        var v: UInt64 = 0
        for k in 0..<8 { v = (v << 8) | UInt64(self[i + k]) }
        return v
    }
}
