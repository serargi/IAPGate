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

    /// Locates the `gcloud` executable. A GUI app launched from Finder
    /// does NOT inherit the user's shell PATH, so we can't rely on the
    /// environment. We try, in order:
    ///   1. a set of well-known install locations,
    ///   2. the user's login shell PATH (sourcing their shell config),
    /// and return the first hit that is actually executable.
    public static func findGcloud() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        // Well-known locations across the common install methods:
        // Homebrew (Apple Silicon / Intel), the official interactive
        // installer (per-user and system), and manual unpacks.
        let candidates = [
            "/opt/homebrew/bin/gcloud",
            "/opt/homebrew/share/google-cloud-sdk/bin/gcloud",
            "/usr/local/bin/gcloud",
            "/usr/local/share/google-cloud-sdk/bin/gcloud",
            "/usr/local/google-cloud-sdk/bin/gcloud",
            "/usr/local/share/google/google-cloud-sdk/bin/gcloud",
            "\(home)/google-cloud-sdk/bin/gcloud",
            "\(home)/.google-cloud-sdk/bin/gcloud",
            "\(home)/Downloads/google-cloud-sdk/bin/gcloud",
            "\(home)/Applications/google-cloud-sdk/bin/gcloud",
            "/opt/google-cloud-sdk/bin/gcloud"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }

        // Fall back to the user's login shell. We source both the login
        // and interactive config, because gcloud's own installer often
        // appends its PATH line to ~/.zshrc (interactive), which a plain
        // login shell (`-l`) would not load.
        if let fromShell = gcloudFromLoginShell(), fm.isExecutableFile(atPath: fromShell) {
            return fromShell
        }
        return nil
    }

    /// Asks the user's default login shell where gcloud is, loading the
    /// shell's configuration so a PATH added in .zshrc/.bashrc is seen.
    private static func gcloudFromLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // `-i -l -c`: interactive + login, so both .zprofile and .zshrc
        // (or .bash_profile and .bashrc) are sourced before we ask.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: shell)
        probe.arguments = ["-ilc", "command -v gcloud"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = Pipe()
        do {
            try probe.run()
            probe.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // `command -v` can print a shell builtin/alias; only accept a
            // real path.
            if path.hasPrefix("/"), !path.isEmpty { return path }
        } catch { /* ignore and fall through */ }
        return nil
    }
}
