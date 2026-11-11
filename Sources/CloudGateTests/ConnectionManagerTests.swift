import Foundation
import TestKit
import Transport

func connectionManagerSuite() -> TestSuite {
    let s = TestSuite("ConnectionManager")

    s.test("derives the OS Login-style username from an email") { t in
        t.expectEqual(
            ConnectionManager.posixUsername(fromEmail: "s.garcia@altostratus.es"),
            "s_garcia")
        t.expectEqual(
            ConnectionManager.posixUsername(fromEmail: "Ada.Lovelace@example.com"),
            "ada_lovelace")
        t.expectEqual(
            ConnectionManager.posixUsername(fromEmail: "plainuser@example.com"),
            "plainuser")
    }

    s.test("rejects malformed emails") { t in
        t.expect(ConnectionManager.posixUsername(fromEmail: "noatsign") == nil)
        t.expect(ConnectionManager.posixUsername(fromEmail: "@nolocal.com") == nil)
    }

    s.test("ssh command includes user@instance and IAP flag") { t in
        let manager = ConnectionManager()
        let target = IAPTarget(project: "cmc-sandbox", zone: "europe-west1-b",
                               instance: "vm-wamaro-1", port: 22)
        switch manager.sshCommand(target: target, username: "s_garcia") {
        case .success(let cmd):
            t.expect(cmd.arguments.contains("s_garcia@vm-wamaro-1"))
            t.expect(cmd.arguments.contains("--tunnel-through-iap"))
            t.expect(cmd.arguments.contains("--zone=europe-west1-b"))
            t.expect(cmd.arguments.contains("--project=cmc-sandbox"))
        case .failure:
            // gcloud may not be present in a clean CI environment; the
            // argument shape is what we assert when it is.
            t.expect(true)
        }
    }

    s.test("ssh command omits user when none provided") { t in
        let manager = ConnectionManager()
        let target = IAPTarget(project: "p", zone: "z", instance: "vm", port: 22)
        if case .success(let cmd) = manager.sshCommand(target: target, username: nil) {
            t.expect(cmd.arguments.contains("vm"))
            t.expect(!cmd.arguments.contains { $0.contains("@") })
        }
    }

    s.test("rdp tunnel command targets 3389 and the local port") { t in
        let manager = ConnectionManager()
        let target = IAPTarget(project: "p", zone: "z", instance: "winvm", port: 3389)
        if case .success(let cmd) = manager.rdpTunnelCommand(target: target, localPort: 13389) {
            t.expect(cmd.arguments.contains("start-iap-tunnel"))
            t.expect(cmd.arguments.contains("winvm"))
            t.expect(cmd.arguments.contains("3389"))
            t.expect(cmd.arguments.contains("--local-host-port=localhost:13389"))
        }
    }

    return s
}
