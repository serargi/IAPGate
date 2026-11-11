import Foundation

/// Removes sensitive values from strings before they reach logs,
/// diagnostics exports, or crash reports.
///
/// This is a defense-in-depth layer. The primary defense is never
/// passing secrets into loggable strings in the first place; this
/// catches mistakes. It is intentionally conservative: it prefers to
/// over-redact rather than leak.
public enum Redactor {

    /// The placeholder substituted for any redacted span.
    public static let placeholder = "[REDACTED]"

    /// Patterns that indicate a secret. Matched case-insensitively.
    /// Each pattern captures the secret portion in group 1 so only the
    /// value is redacted, not the surrounding key.
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            // Authorization: Bearer <token>
            #"(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._\-]+"#,
            // "access_token": "...", access_token=...
            #"(?i)(access_token["\s:=]+)[A-Za-z0-9._\-]+"#,
            #"(?i)(refresh_token["\s:=]+)[A-Za-z0-9._\-]+"#,
            #"(?i)(id_token["\s:=]+)[A-Za-z0-9._\-]+"#,
            #"(?i)(client_secret["\s:=]+)[A-Za-z0-9._\-]+"#,
            #"(?i)(code_verifier["\s:=]+)[A-Za-z0-9._\-]+"#,
            // Generic password=... / "password": "..."
            #"(?i)(password["\s:=]+)[^\s",}]+"#,
            // Google OAuth access tokens (ya29....)
            #"(ya29\.)[A-Za-z0-9._\-]+"#,
            // PEM private key blocks
            #"(?s)(-----BEGIN [A-Z ]*PRIVATE KEY-----).*?(-----END [A-Z ]*PRIVATE KEY-----)"#
        ]
        return raw.compactMap {
            try? NSRegularExpression(pattern: $0)
        }
    }()

    /// Returns a copy of `input` with recognized secrets replaced by
    /// the placeholder. Preserves the key/label so logs remain useful.
    public static func redact(_ input: String) -> String {
        var result = input
        for regex in patterns {
            let range = NSRange(result.startIndex..., in: result)
            // Keep capture group 1 (the label), redact the rest.
            // For the PEM pattern we keep groups 1 and 2 (begin/end).
            let template = templateForRedaction(of: regex)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )
        }
        return result
    }

    private static func templateForRedaction(
        of regex: NSRegularExpression
    ) -> String {
        // The PEM pattern has two capture groups (begin + end markers);
        // everything in between is the secret.
        if regex.numberOfCaptureGroups >= 2 {
            return "$1\(placeholder)$2"
        }
        return "$1\(placeholder)"
    }
}
