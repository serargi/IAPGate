import Foundation
import Darwin

/// Finds a free local TCP port on the loopback interface.
///
/// Used so each RDP tunnel gets its own `localhost:<port>`; a fixed
/// 3389 would collide on the second simultaneous connection.
public enum FreePort {

    /// Asks the OS for an unused loopback port by binding to port 0 and
    /// reading back the assigned port, then closing the socket. There's
    /// a tiny race between closing and the caller re-binding, which is
    /// acceptable here (gcloud binds almost immediately, and a failure
    /// just surfaces as a normal connection error).
    public static func find() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0 // let the OS choose

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var out = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &out) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }
        guard got == 0 else { return nil }
        return Int(UInt16(bigEndian: out.sin_port))
    }

    /// A free port, or `fallback` if detection failed.
    public static func find(default fallback: Int) -> Int {
        find() ?? fallback
    }
}
