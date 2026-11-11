import Foundation
import CloudGateCore

/// Windows credentials returned by a password reset.
///
/// The password is intentionally **not** `Codable` beyond decoding the
/// gcloud response, is never written to disk, never logged, and is held
/// only for as long as the UI shows it to the user who asked for it.
public struct WindowsCredentials: Sendable, Equatable, Identifiable {
    public var id: String { username }
    public let username: String
    public let password: String
    public let ipAddress: String?

    public init(username: String, password: String, ipAddress: String?) {
        self.username = username
        self.password = password
        self.ipAddress = ipAddress
    }
}

/// Creates or resets a Windows local user's password on a Compute
/// Engine instance, via `gcloud compute reset-windows-password`.
///
/// This **modifies the instance** (it writes to instance metadata so
/// the guest agent can set the account), so the caller must obtain
/// explicit user confirmation first — the project rules forbid changing
/// cloud resources without consent. Google also warns that resetting an
/// existing user's password can lose data encrypted with the old one.
public struct WindowsCredentialsService: Sendable {

    public init() {}

    public func resetPassword(
        target: IAPTarget,
        username: String
    ) async -> Result<WindowsCredentials, CloudGateError> {
        guard let gcloud = ConnectionManager.findGcloud() else {
            return .failure(.make(.unexpected,
                userMessage: "gcloud was not found. Install the Google Cloud SDK.",
                technicalDetail: "gcloud not found"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gcloud)
        process.arguments = [
            "compute", "reset-windows-password", target.instance,
            "--user=\(username)",
            "--zone=\(target.zone)",
            "--project=\(target.project)",
            "--format=json",
            "--quiet"           // we already confirmed with the user
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failure(.make(.unexpected,
                userMessage: "Could not run gcloud.",
                technicalDetail: "reset-windows-password launch failed"))
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // Surface gcloud's own message; it explains permission and
            // instance-state problems better than we could.
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failure(.make(.unexpected,
                userMessage: message.isEmpty
                    ? "No se pudieron generar las credenciales de Windows."
                    : message,
                technicalDetail: "reset-windows-password exit \(process.terminationStatus)"))
        }

        guard let creds = Self.parse(outData) else {
            return .failure(.make(.unexpected,
                userMessage: "The gcloud response could not be parsed.",
                technicalDetail: "reset-windows-password parse failed"))
        }
        return .success(creds)
    }

    /// Parses gcloud's JSON output. Pure, so it is unit-tested without
    /// touching gcloud or any VM.
    public static func parse(_ data: Data) -> WindowsCredentials? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        // gcloud may return a single object or a single-element array.
        let dict: [String: Any]?
        if let d = object as? [String: Any] {
            dict = d
        } else if let array = object as? [[String: Any]] {
            dict = array.first
        } else {
            dict = nil
        }
        guard let dict,
              let password = dict["password"] as? String,
              let username = dict["username"] as? String else {
            return nil
        }
        return WindowsCredentials(
            username: username,
            password: password,
            ipAddress: dict["ip_address"] as? String)
    }
}
