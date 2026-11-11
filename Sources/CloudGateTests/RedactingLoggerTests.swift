import TestKit
import CloudGateCore
import Diagnostics

func redactingLoggerSuite() -> TestSuite {
    let s = TestSuite("RedactingLogger")

    s.test("redacts secrets before buffering") { t in
        let sink = InMemoryLogSink()
        let logger = RedactingLogger(sink: sink, minimumLevel: .debug)
        logger.info("auth", "exchanged code, access_token=ya29.secret-value")

        let entries = sink.snapshot()
        t.expectEqual(entries.count, 1)
        if let message = entries.first?.message {
            t.expect(!message.contains("ya29.secret-value"))
            t.expect(message.contains(Redactor.placeholder))
        }
    }

    s.test("debug suppressed below minimum level") { t in
        let sink = InMemoryLogSink()
        let logger = RedactingLogger(sink: sink, minimumLevel: .info)
        logger.debug("net", "verbose detail")
        logger.info("net", "something happened")

        let entries = sink.snapshot()
        t.expectEqual(entries.count, 1)
        t.expectEqual(entries.first?.level, .info)
    }

    s.test("CloudGateError technical detail is redacted") { t in
        let sink = InMemoryLogSink()
        let logger = RedactingLogger(sink: sink, minimumLevel: .debug)
        let error = CloudGateError.make(
            .authenticationFailed,
            userMessage: "Sign-in failed",
            technicalDetail: "refresh_token=1//leaked-value")
        logger.log(error, category: "auth")

        if let message = sink.snapshot().first?.message {
            t.expect(!message.contains("1//leaked-value"))
            t.expect(message.contains("Sign-in failed"))
            t.expect(message.contains("authenticationFailed"))
        } else {
            t.expect(false, "no log entry")
        }
    }

    s.test("no log entry ever contains a raw bearer token") { t in
        let sink = InMemoryLogSink()
        let logger = RedactingLogger(sink: sink, minimumLevel: .debug)
        logger.warning("http", "request headers: Authorization: Bearer ya29.aaa.bbb")

        for entry in sink.snapshot() {
            t.expect(!entry.message.lowercased().contains("ya29"))
        }
    }

    return s
}
