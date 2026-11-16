import Foundation
import TestKit
import Transport

/// Thread-safe collector for PTY output.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ data: Data) {
        lock.lock(); text += String(decoding: data, as: UTF8.self); lock.unlock()
    }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}

func ptySessionSuite() -> TestSuite {
    let s = TestSuite("PTYSession")

    s.test("terminateAllBlocking kills the child and its grandchildren before returning") { t in
        let box = OutputBox()
        let session = PTYSession()
        session.onOutput = { box.append($0) }
        // The shell starts a background `sleep` (a grandchild, like the
        // ssh that gcloud spawns) and prints its pid.
        session.start(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 300 & echo CHILD:$!; wait"])

        // Wait for the grandchild pid to show up in the output.
        var grandchild: pid_t?
        let deadline = Date().addingTimeInterval(5)
        while grandchild == nil, Date() < deadline {
            if let range = box.value.range(of: #"CHILD:(\d+)"#, options: .regularExpression) {
                let digits = box.value[range].dropFirst("CHILD:".count)
                grandchild = pid_t(digits)
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        t.expect(grandchild != nil, "grandchild pid was reported")
        guard let grandchild else { return }
        t.expect(kill(grandchild, 0) == 0, "grandchild is alive before shutdown")

        t.expect(PTYSession.hasLiveSessions, "session counts as live")

        let began = Date()
        PTYSession.terminateAllBlocking(grace: 0.1, timeout: 3)
        // Graceful signals must be enough; hitting the timeout means the
        // child ignored SIGHUP/SIGTERM and only SIGKILL worked.
        t.expect(Date().timeIntervalSince(began) < 1.5, "shutdown did not need SIGKILL")

        // No polling here: the call must not return until they are gone.
        t.expect(kill(grandchild, 0) != 0, "grandchild is gone when the call returns")
        t.expect(!PTYSession.hasLiveSessions, "no live sessions remain")
    }

    s.test("terminateAllBlocking returns immediately with no sessions") { t in
        let start = Date()
        PTYSession.terminateAllBlocking(grace: 0.6, timeout: 3)
        t.expect(Date().timeIntervalSince(start) < 0.5, "does not wait when idle")
    }

    return s
}
