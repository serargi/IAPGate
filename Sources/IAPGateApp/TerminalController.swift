import Foundation
import Observation
import Transport

/// Backs an embedded terminal tab: runs a gcloud command in a PTY and
/// accumulates readable output. Keystrokes from the view are forwarded
/// to the PTY, so an interactive SSH session (and any reauth prompt)
/// happens inside the app.
@MainActor
@Observable
public final class TerminalController: Identifiable {
    public let id = UUID()
    public let title: String
    /// The VM this session belongs to, so an existing tab can be
    /// focused instead of opening a duplicate session.
    public let vmID: String

    /// Accumulated, ANSI-stripped text shown in the terminal view.
    public private(set) var output: String = ""
    public private(set) var finished = false
    public private(set) var exitCode: Int32?

    @ObservationIgnored private let pty = PTYSession()
    @ObservationIgnored private let emulator = TerminalEmulator()
    @ObservationIgnored private let executable: String
    @ObservationIgnored private let arguments: [String]

    /// Optional text to wait for in the output; `onReady` fires once
    /// when it appears. Used to launch the RDP client only after the
    /// tunnel reports it is listening.
    @ObservationIgnored public var readyMarker: String?
    @ObservationIgnored public var onReady: (@MainActor () -> Void)?
    @ObservationIgnored private var readyFired = false

    public init(title: String, vmID: String, executable: String, arguments: [String]) {
        self.title = title
        self.vmID = vmID
        self.executable = executable
        self.arguments = arguments
    }

    public func start() {
        // Tell gcloud not to animate its progress tracker, so the
        // embedded terminal doesn't fill with "Updating..." repeats.
        // (Prompts still work; only the spinner UX is disabled.)
        var env = ProcessInfo.processInfo.environment
        env["CLOUDSDK_CORE_INTERACTIVE_UX_STYLE"] = "OFF"

        pty.onOutput = { [weak self] data in
            guard let self else { return }
            let text = String(decoding: data, as: UTF8.self)
            // The emulator is stateful, so it renders the whole screen
            // correctly across chunk boundaries (prompts, spinners).
            let rendered = self.emulator.feed(text)
            Task { @MainActor in
                self.output = rendered
                // Fire the readiness hook once the marker shows up.
                if !self.readyFired, let marker = self.readyMarker,
                   rendered.contains(marker) {
                    self.readyFired = true
                    self.onReady?()
                }
            }
        }
        pty.onExit = { [weak self] code in
            guard let self else { return }
            let rendered = self.emulator.feed("\r\n[Session ended — exit code \(code)]\r\n")
            Task { @MainActor in
                self.finished = true
                self.exitCode = code
                self.output = rendered
            }
        }
        pty.start(executable: executable, arguments: arguments, environment: env)
    }

    /// Sends user-typed text (including a trailing newline on Return).
    public func send(_ text: String) {
        pty.send(Data(text.utf8))
    }

    public func terminate() {
        pty.terminate()
    }
}
