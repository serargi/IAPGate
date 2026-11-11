import Foundation
import Auth
import Transport

/// Runs the gcloud CLI for authentication.
///
/// Non-interactive commands (token, account, revoke) run via `Process`
/// and capture stdout. `gcloud auth login` is interactive: it opens the
/// browser and waits for the callback, so it is given a plain `Process`
/// too — gcloud handles the browser itself; no PTY is needed because
/// there is no password prompt in the browser-based flow.
public struct GcloudRunner: GcloudAuthProvider.Runner {

    private let gcloudPath: String

    public init?() {
        guard let path = ConnectionManager.findGcloud() else { return nil }
        self.gcloudPath = path
    }

    public func run(
        _ arguments: [String],
        interactive: Bool
    ) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gcloudPath)
                process.arguments = arguments

                let stdout = Pipe()
                process.standardOutput = stdout
                // For interactive login, let gcloud talk to the real
                // stderr (it prints progress / the URL there); for
                // non-interactive calls, capture and discard it.
                let stderr = Pipe()
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ("", 127))
                    return
                }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                _ = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, process.terminationStatus))
            }
        }
    }
}
