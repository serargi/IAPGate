import TestKit
import CloudGateCore

func cloudGateErrorSuite() -> TestSuite {
    let s = TestSuite("CloudGateError")

    s.test("transient kinds are retryable") { t in
        let e = CloudGateError.make(.networkTimeout, userMessage: "timed out")
        t.expect(e.isRetryable)
    }

    s.test("authorization failures are not retryable") { t in
        let e = CloudGateError.make(.iapPermissionDenied, userMessage: "no permission")
        t.expect(!e.isRetryable)
    }

    s.test("permanent auth failures excluded from retryableKinds") { t in
        let permanent: [CloudGateError.Kind] = [
            .authenticationFailed, .authorizationRevoked,
            .insufficientCloudPermissions, .iapPermissionDenied,
            .sshHostKeyChanged
        ]
        for kind in permanent {
            t.expect(!CloudGateError.retryableKinds.contains(kind), "\(kind) must not be retryable")
        }
    }

    return s
}
