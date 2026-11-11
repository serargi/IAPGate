import Foundation
import Darwin

/// Runs a child process attached to a pseudo-terminal (PTY), so
/// interactive programs like `gcloud` and `ssh` behave as if in a real
/// terminal: password prompts, colored output, and line editing work.
///
/// Output bytes are delivered via `onOutput`; call `send(_:)` to write
/// user keystrokes to the process. This backs the app's embedded
/// terminal, so the whole SSH session (including any gcloud reauth
/// prompt) happens inside IAPGate — no external Terminal.app.
public final class PTYSession: @unchecked Sendable {

    private var masterFD: Int32 = -1
    private var pid: pid_t = -1
    private let readQueue = DispatchQueue(label: "com.iapgate.pty.read")
    private var source: DispatchSourceRead?
    private let stateLock = NSLock()
    private var running = false

    /// Raw bytes from the process (stdout+stderr merged by the PTY).
    public var onOutput: (@Sendable (Data) -> Void)?
    /// Called when the process exits, with its status code.
    public var onExit: (@Sendable (Int32) -> Void)?

    public init() {
        PTYSession.register(self)
    }

    // MARK: - Global registry (cleanup on app exit)

    // Access is always guarded by `registryLock`, so this is safe.
    nonisolated(unsafe) private static var live: [Weak] = []
    private static let registryLock = NSLock()
    private final class Weak { weak var s: PTYSession?; init(_ s: PTYSession) { self.s = s } }

    private static func register(_ s: PTYSession) {
        registryLock.lock(); live.append(Weak(s)); registryLock.unlock()
    }

    /// Terminates every live PTY session. Call on app termination so no
    /// remote SSH/RDP session is left running when IAPGate quits.
    public static func terminateAll() {
        registryLock.lock(); let all = live.compactMap { $0.s }; registryLock.unlock()
        all.forEach { $0.terminate() }
    }

    /// Launches `executable` with `arguments` in a PTY of the given
    /// size. `environment` defaults to the current process environment.
    public func start(
        executable: String,
        arguments: [String],
        columns: UInt16 = 120,
        rows: UInt16 = 30,
        environment: [String: String]? = nil
    ) {
        var master: Int32 = 0
        var slave: Int32 = 0
        var win = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)

        guard openpty(&master, &slave, nil, nil, &win) == 0 else {
            onExit?(-1)
            return
        }
        self.masterFD = master

        // Use posix_spawn (fork() is unavailable in Swift). The slave
        // PTY fd becomes the child's stdin/stdout/stderr, and we set a
        // new session so the PTY is the controlling terminal.
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 0)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 1)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 2)
        posix_spawn_file_actions_addclose(&fileActions, slave)
        posix_spawn_file_actions_addclose(&fileActions, master)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        // POSIX_SPAWN_SETSID makes the child a session leader so the
        // PTY slave is its controlling terminal (needed for prompts)
        // AND creates a new process group. We then signal the whole
        // group on terminate() so gcloud's child ssh/tunnel processes
        // are killed too — no orphaned remote sessions.
        let flags = Int16(POSIX_SPAWN_SETSID)
        posix_spawnattr_setflags(&attr, flags)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let env = environment ?? ProcessInfo.processInfo.environment
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for p in argv where p != nil { free(p) }
            for p in envp where p != nil { free(p) }
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attr)
        }

        var childPID: pid_t = 0
        let rc = posix_spawn(&childPID, executable, &fileActions, &attr, argv, envp)
        close(slave)
        guard rc == 0 else {
            close(master); masterFD = -1
            onExit?(Int32(rc))
            return
        }

        self.pid = childPID
        stateLock.lock(); running = true; stateLock.unlock()
        startReading()
        reapAsync()
    }

    /// Writes user input (keystrokes) to the process.
    public func send(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { raw in
            _ = write(masterFD, raw.baseAddress, raw.count)
        }
    }

    /// Sends a terminal resize to the child.
    public func resize(columns: UInt16, rows: UInt16) {
        guard masterFD >= 0 else { return }
        var win = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &win)
    }

    /// Terminates the process group and closes the PTY.
    ///
    /// Signals the whole process group (negative pid) so gcloud's child
    /// `ssh`/tunnel processes are terminated too, which closes the
    /// remote session cleanly instead of leaving it dangling. SIGHUP
    /// first (ssh treats it as a hangup and tears down the session),
    /// then SIGKILL as a backstop for anything still alive.
    public func terminate() {
        stateLock.lock()
        let wasRunning = running
        running = false
        let group = pid
        stateLock.unlock()

        guard wasRunning, group > 0 else { return }

        // Resolve the child's real process group rather than assuming
        // pid == pgid: that only holds if the new-session flag took
        // effect. We signal the group so gcloud AND its child ssh /
        // tunnel processes are terminated, which closes the remote
        // session instead of leaving it dangling.
        let pgid = getpgid(group)

        // 1. Log out gracefully first. Killing the local ssh process
        //    does NOT immediately end the remote session: sshd keeps the
        //    shell alive until it notices the dropped TCP connection,
        //    which can take minutes. Sending "exit" makes the remote
        //    shell terminate, so sshd reaps the session right away.
        let fd = masterFD
        if fd >= 0 {
            let logout = "\u{03}\rexit\r"   // Ctrl-C to clear any input, then exit
            logout.withCString { ptr in
                _ = write(fd, ptr, strlen(ptr))
            }
        }

        // 2. Give the remote side a moment to act on the logout, then
        //    tear everything down locally.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.source?.cancel()
            if let self, self.masterFD >= 0 {
                close(self.masterFD)
                self.masterFD = -1
            }
            // Signal the group (and the child directly as a fallback).
            if pgid > 0 {
                kill(-pgid, SIGHUP)
                kill(-pgid, SIGTERM)
            }
            kill(group, SIGHUP)
            kill(group, SIGTERM)

            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if pgid > 0 { kill(-pgid, SIGKILL) }
                kill(group, SIGKILL)
            }
        }
    }

    // MARK: - Private

    private func startReading() {
        let fd = masterFD
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        src.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                self?.onOutput?(Data(buffer[0..<n]))
            } else {
                self?.source?.cancel()
            }
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.masterFD >= 0 { close(self.masterFD); self.masterFD = -1 }
        }
        self.source = src
        src.resume()
    }

    private func reapAsync() {
        let childPID = pid
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var status: Int32 = 0
            waitpid(childPID, &status, 0)
            self?.stateLock.lock(); self?.running = false; self?.stateLock.unlock()
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : status
            self?.onExit?(code)
        }
    }
}
