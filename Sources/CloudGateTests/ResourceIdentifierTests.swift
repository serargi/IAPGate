import TestKit
import CloudGateCore

func resourceIdentifierSuite() -> TestSuite {
    let s = TestSuite("ResourceIdentifier")

    s.test("accepts valid project ID") { t in
        do {
            let id = try ResourceIdentifier(validating: "analog-figure-330721")
            t.expectEqual(id.rawValue, "analog-figure-330721")
        } catch {
            t.expect(false, "unexpected throw: \(error)")
        }
    }

    s.test("accepts zone and instance paths") { t in
        do {
            _ = try ResourceIdentifier(validating: "europe-west2-a")
            _ = try ResourceIdentifier(
                validating: "projects/p/zones/europe-west2-a/instances/prod-1")
        } catch {
            t.expect(false, "unexpected throw: \(error)")
        }
    }

    s.test("rejects empty") { t in
        t.expectThrows(ResourceIdentifier.ValidationError.empty) {
            _ = try ResourceIdentifier(validating: "")
        }
    }

    s.test("rejects shell metacharacters and whitespace") { t in
        let dangerous = [
            "prod-1; rm -rf /", "a$(whoami)", "a`id`", "a|b",
            "a&b", "a b", "a\"b", "a'b", "a\nb"
        ]
        for value in dangerous {
            t.expectThrows(ResourceIdentifier.ValidationError.illegalCharacters) {
                _ = try ResourceIdentifier(validating: value)
            }
        }
    }

    s.test("rejects overly long") { t in
        let long = String(repeating: "a", count: 513)
        t.expectThrows(ResourceIdentifier.ValidationError.tooLong(513)) {
            _ = try ResourceIdentifier(validating: long)
        }
    }

    return s
}
