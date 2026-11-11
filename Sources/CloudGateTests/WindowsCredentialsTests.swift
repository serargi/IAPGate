import Foundation
import TestKit
import Transport

func windowsCredentialsSuite() -> TestSuite {
    let s = TestSuite("WindowsCredentialsService")

    s.test("parses a single JSON object") { t in
        let json = """
        {"ip_address":"34.1.2.3","password":"Abc123!xyz","username":"s_garcia"}
        """
        let creds = WindowsCredentialsService.parse(Data(json.utf8))
        t.expectEqual(creds?.username, "s_garcia")
        t.expectEqual(creds?.password, "Abc123!xyz")
        t.expectEqual(creds?.ipAddress, "34.1.2.3")
    }

    s.test("parses a single-element array") { t in
        let json = #"[{"password":"p","username":"u"}]"#
        let creds = WindowsCredentialsService.parse(Data(json.utf8))
        t.expectEqual(creds?.username, "u")
        t.expectEqual(creds?.password, "p")
        t.expect(creds?.ipAddress == nil)
    }

    s.test("returns nil when required fields are missing") { t in
        t.expect(WindowsCredentialsService.parse(Data(#"{"username":"u"}"#.utf8)) == nil)
        t.expect(WindowsCredentialsService.parse(Data("not json".utf8)) == nil)
    }

    return s
}
