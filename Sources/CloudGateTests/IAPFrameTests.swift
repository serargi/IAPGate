import Foundation
import TestKit
import Transport

func iapFrameSuite() -> TestSuite {
    let s = TestSuite("IAP relay framing")

    s.test("encodes a DATA frame: tag 0x0004 + len + payload") { t in
        let payload = Data([0xAA, 0xBB, 0xCC])
        let encoded = IAPFrame.data(payload).encoded()
        // tag(2) + len(4) + payload(3) = 9 bytes
        t.expectEqual(encoded.count, 9)
        t.expectEqual(encoded[0], 0x00); t.expectEqual(encoded[1], 0x04)
        // length big-endian = 3
        t.expectEqual(encoded[2], 0x00); t.expectEqual(encoded[3], 0x00)
        t.expectEqual(encoded[4], 0x00); t.expectEqual(encoded[5], 0x03)
        t.expectEqual(Array(encoded[6...]), [0xAA, 0xBB, 0xCC])
    }

    s.test("encodes an ACK frame: tag 0x0007 + uint64") { t in
        let encoded = IAPFrame.ack(258).encoded()
        t.expectEqual(encoded.count, 10)
        t.expectEqual(encoded[0], 0x00); t.expectEqual(encoded[1], 0x07)
        // 258 = 0x0102 in the last two bytes
        t.expectEqual(encoded[8], 0x01); t.expectEqual(encoded[9], 0x02)
    }

    s.test("decodes a SUCCESS frame and session id") { t in
        var bytes = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x04]) // tag + len=4
        bytes.append(contentsOf: [0x73, 0x69, 0x64, 0x31])      // "sid1"
        do {
            let (frame, consumed) = try IAPFrame.decode(bytes)
            t.expectEqual(consumed, 10)
            if case .success(let sid) = frame {
                t.expectEqual(String(data: sid, encoding: .utf8), "sid1")
            } else { t.expect(false, "expected success frame") }
        } catch { t.expect(false, "decode threw: \(error)") }
    }

    s.test("decodes a DATA frame") { t in
        let bytes = Data([0x00, 0x04, 0x00, 0x00, 0x00, 0x02, 0x41, 0x42])
        do {
            let (frame, consumed) = try IAPFrame.decode(bytes)
            t.expectEqual(consumed, 8)
            if case .data(let d) = frame { t.expectEqual(Array(d), [0x41, 0x42]) }
            else { t.expect(false, "expected data frame") }
        } catch { t.expect(false, "decode threw: \(error)") }
    }

    s.test("decodes an ACK frame") { t in
        let bytes = Data([0x00, 0x07, 0,0,0,0,0,0, 0x01, 0x00]) // 256
        do {
            let (frame, consumed) = try IAPFrame.decode(bytes)
            t.expectEqual(consumed, 10)
            if case .ack(let n) = frame { t.expectEqual(n, 256) }
            else { t.expect(false, "expected ack frame") }
        } catch { t.expect(false, "decode threw: \(error)") }
    }

    s.test("round-trips multiple concatenated frames") { t in
        var buf = IAPFrame.data(Data([1,2,3])).encoded()
        buf.append(IAPFrame.ack(10).encoded())
        do {
            let (f1, c1) = try IAPFrame.decode(buf)
            if case .data(let d) = f1 { t.expectEqual(Array(d), [1,2,3]) } else { t.expect(false) }
            let rest = buf.subdata(in: (buf.startIndex + c1)..<buf.endIndex)
            let (f2, _) = try IAPFrame.decode(rest)
            if case .ack(let n) = f2 { t.expectEqual(n, 10) } else { t.expect(false) }
        } catch { t.expect(false, "decode threw: \(error)") }
    }

    s.test("truncated frame throws") { t in
        t.expectThrows(IAPFrame.DecodeError.truncated) {
            _ = try IAPFrame.decode(Data([0x00, 0x04, 0x00, 0x00, 0x00, 0x05, 0x41]))
        }
    }

    s.test("connect URL has required query params and subprotocol host") { t in
        let target = IAPTarget(project: "cmc", zone: "europe-southwest1-a",
                               instance: "segwdtipro1", port: 22)
        let url = IAPConnectURL.make(target).absoluteString
        t.expect(url.hasPrefix("wss://tunnel.cloudproxy.app/v4/connect"))
        t.expect(url.contains("project=cmc"))
        t.expect(url.contains("zone=europe-southwest1-a"))
        t.expect(url.contains("instance=segwdtipro1"))
        t.expect(url.contains("interface=nic0"))
        t.expect(url.contains("port=22"))
    }

    return s
}
