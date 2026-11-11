import Foundation
import CloudGateCore

/// Builds the commands used to connect to VMs over IAP via gcloud.
///
/// This no longer launches an external terminal: it returns the
/// executable + argument vector so the app can run it inside its own
/// embedded terminal (PTY). gcloud handles key propagation, username
/// resolution, and the IAP tunnel; the interactive session — including
/// any gcloud reauth prompt — happens inside IAPGate.
public struct ConnectionManager: Sendable {

    public struct Command: Sendable, Equatable {
        public let executable: String
        public let arguments: [String]
    }

    public enum ConnectError: Error, Equatable { case gcloudNotFound }

    public init() {}

    /// SSH to a Linux VM: `gcloud compute ssh [user@]<vm>
    /// --tunnel-through-iap`.
    ///
    /// `username` matters: when a project does not use OS Login, gcloud
    /// falls back to metadata SSH keys and derives the Linux user from
    /// the **local macOS username**, which creates a different account
    /// than the one the Cloud Console uses. Passing the OS Login-style
    /// username (derived from the Google account email) keeps the
    /// identity consistent with the Console.
    ///
    /// `--verbosity=error` suppresses gcloud's animated progress tracker
    /// and informational warnings; the reauth prompt still appears (it
    /// goes through the PTY, not the logger).
    public func sshCommand(
        target: IAPTarget,
        username: String? = nil,
        remotePort: Int = 22
    ) -> Result<Command, CloudGateError> {
        guard let gcloud = Self.findGcloud() else { return .failure(Self.notFound) }
        let destination: String
        if let username, !username.isEmpty {
            destination = "\(username)@\(target.instance)"
        } else {
            destination = target.instance
        }
        var args = [
            "compute", "ssh", destination,
            "--zone=\(target.zone)",
            "--project=\(target.project)",
            "--tunnel-through-iap",
            "--verbosity=error"
        ]
        // Non-default SSH port: tell gcloud to forward IAP to that port
        // and tell ssh to use it.
        if remotePort != 22 {
            args.append("--ssh-flag=-p \(remotePort)")
        }
        return .success(Command(executable: gcloud, arguments: args))
    }

    /// Derives the Linux/OS Login-style username from a Google account
    /// email: the local part with non-alphanumeric characters replaced
    /// by underscores (e.g. "s.garcia@altostratus.es" -> "s_garcia").
    /// This matches what the Cloud Console's SSH-in-browser uses.
    public static func posixUsername(fromEmail email: String) -> String? {
        guard let at = email.firstIndex(of: "@") else { return nil }
        let local = String(email[email.startIndex..<at])
        guard !local.isEmpty else { return nil }
        let mapped = local.map { ch -> Character in
            ch.isLetter || ch.isNumber ? Character(ch.lowercased()) : "_"
        }
        return String(mapped)
    }

    /// RDP tunnel to a Windows VM: `gcloud compute start-iap-tunnel
    /// <vm> 3389 --local-host-port=localhost:<port> ...`. The app then
    /// opens the system RDP client at localhost:<port>.
    public func rdpTunnelCommand(
        target: IAPTarget,
        localPort: Int,
        remotePort: Int = 3389
    ) -> Result<Command, CloudGateError> {
        guard let gcloud = Self.findGcloud() else { return .failure(Self.notFound) }
        return .success(Command(executable: gcloud, arguments: [
            "compute", "start-iap-tunnel", target.instance, String(remotePort),
            "--local-host-port=localhost:\(localPort)",
            "--zone=\(target.zone)",
            "--project=\(target.project)",
            "--verbosity=error"
        ]))
    }

    private static var notFound: CloudGateError {
        .make(.unexpected,
            userMessage: "gcloud was not found. Install the Google Cloud SDK and run 'gcloud auth login'.",
            technicalDetail: "gcloud not found")
    }

    // MARK: - gcloud discovery

    public static func findGcloud() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gcloud",
            "/usr/local/bin/gcloud",
            "\(NSHomeDirectory())/google-cloud-sdk/bin/gcloud",
            "/usr/local/google-cloud-sdk/bin/gcloud"
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/bin/zsh")
        which.arguments = ["-lc", "command -v gcloud"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, fm.isExecutableFile(atPath: path) { return path }
        } catch { /* ignore */ }
        return nil
    }
}
