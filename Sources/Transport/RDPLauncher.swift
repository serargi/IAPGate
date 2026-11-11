import Foundation
import CloudGateCore

/// Opens the user's RDP client against the local IAP tunnel endpoint.
///
/// Uses a generated `.rdp` file rather than an `rdp://` URL: macOS RDP
/// clients (Microsoft Remote Desktop / Windows App) reliably open `.rdp`
/// documents, whereas the URL scheme is inconsistently handled.
///
/// Security: no password is ever written to the file (the client prompts
/// for credentials), so nothing secret touches disk. The file is written
/// with owner-only permissions and contains only the loopback endpoint.
public struct RDPLauncher: Sendable {

    public init() {}

    /// Writes a minimal .rdp document for `localhost:port` and opens it
    /// with the system default RDP client.
    public func open(localPort: Int, instanceName: String) -> Result<Void, CloudGateError> {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("iapgate-rdp", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Sanitise the name for use as a filename.
        let safeName = instanceName.map { ch -> Character in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" ? ch : "-"
        }
        let fileURL = dir.appendingPathComponent("\(String(safeName)).rdp")

        // "prompt for credentials" makes the client ask for the Windows
        // username/password instead of us handling any secret.
        let document = """
        full address:s:localhost:\(localPort)
        prompt for credentials:i:1
        administrative session:i:0
        screen mode id:i:2
        authentication level:i:0
        """

        do {
            try document.write(to: fileURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            return .failure(.make(.rdpConnectionFailed,
                userMessage: "Could not prepare the RDP connection file.",
                technicalDetail: "write .rdp failed"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [fileURL.path]
        do {
            try process.run()
            return .success(())
        } catch {
            return .failure(.make(.rdpClientNotInstalled,
                userMessage: "No RDP client found. Install Microsoft Remote Desktop from the App Store.",
                technicalDetail: "open .rdp failed"))
        }
    }
}
