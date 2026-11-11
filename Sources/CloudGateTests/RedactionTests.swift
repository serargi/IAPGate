import TestKit
import CloudGateCore

func redactionSuite() -> TestSuite {
    let s = TestSuite("Redactor")

    s.test("redacts bearer token, keeps label") { t in
        let out = Redactor.redact("Authorization: Bearer ya29.aAbBcC-_123.xyz")
        t.expect(!out.contains("ya29"))
        t.expect(out.contains(Redactor.placeholder))
        t.expect(out.lowercased().contains("authorization"))
    }

    s.test("redacts access and refresh tokens") { t in
        let input = #"{"access_token":"abc.def-123","refresh_token":"1//zzzYYY"}"#
        let out = Redactor.redact(input)
        t.expect(!out.contains("abc.def-123"))
        t.expect(!out.contains("1//zzzYYY"))
        t.expect(out.contains("access_token"))
        t.expect(out.contains("refresh_token"))
    }

    s.test("redacts client secret and code verifier") { t in
        let out = Redactor.redact("client_secret=GOCSPXsupersecret code_verifier=abc123DEF")
        t.expect(!out.contains("GOCSPXsupersecret"))
        t.expect(!out.contains("abc123DEF"))
    }

    s.test("redacts password value") { t in
        let out = Redactor.redact(#"{"password":"hunter2!"}"#)
        t.expect(!out.contains("hunter2!"))
        t.expect(out.contains("password"))
    }

    s.test("redacts PEM private key body, keeps markers") { t in
        let input = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmU
        -----END OPENSSH PRIVATE KEY-----
        """
        let out = Redactor.redact(input)
        t.expect(!out.contains("b3BlbnNzaC1rZXktdjE"))
        t.expect(out.contains("BEGIN OPENSSH PRIVATE KEY"))
        t.expect(out.contains("END OPENSSH PRIVATE KEY"))
    }

    s.test("leaves non-sensitive text untouched") { t in
        let input = "Discovered 3 projects in organization example-org"
        t.expectEqual(Redactor.redact(input), input)
    }

    s.test("redacts raw google token without a label") { t in
        let out = Redactor.redact("value is ya29.a0ARrdaM-token-material here")
        t.expect(!out.contains("a0ARrdaM-token-material"))
    }

    return s
}
