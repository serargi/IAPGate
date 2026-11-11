import Foundation
import CloudGateCore

/// Severity levels for structured logging.
public enum LogLevel: Int, Sendable, Comparable, CaseIterable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}

/// A single structured log entry. Messages are redacted at creation so
/// a secret can never be stored in the buffer even transiently.
public struct LogEntry: Sendable, Equatable {
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String

    public init(timestamp: Date, level: LogLevel, category: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

/// Destination for emitted log entries.
public protocol LogSink: Sendable {
    func write(_ entry: LogEntry)
}

/// Structured logger that redacts every message before it is emitted
/// or buffered. Verbose (`debug`) logging is opt-in via `minimumLevel`.
///
/// Redaction is applied centrally here so callers cannot accidentally
/// bypass it, and so the buffer used for diagnostic export is already
/// clean (see SECURITY.md, THREAT_MODEL threats 10/11).
public final class RedactingLogger: @unchecked Sendable {

    private let sink: LogSink
    private let minimumLevel: LogLevel
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        sink: LogSink,
        minimumLevel: LogLevel = .info,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sink = sink
        self.minimumLevel = minimumLevel
        self.now = now
    }

    public func log(
        _ level: LogLevel,
        category: String,
        _ message: @autoclosure () -> String
    ) {
        guard level >= minimumLevel else { return }
        let redacted = Redactor.redact(message())
        let entry = LogEntry(
            timestamp: now(),
            level: level,
            category: category,
            message: redacted
        )
        lock.lock()
        sink.write(entry)
        lock.unlock()
    }

    public func debug(_ category: String, _ message: @autoclosure () -> String) {
        log(.debug, category: category, message())
    }

    public func info(_ category: String, _ message: @autoclosure () -> String) {
        log(.info, category: category, message())
    }

    public func warning(_ category: String, _ message: @autoclosure () -> String) {
        log(.warning, category: category, message())
    }

    public func error(_ category: String, _ message: @autoclosure () -> String) {
        log(.error, category: category, message())
    }

    /// Logs a `CloudGateError`. Only the redacted technical detail is
    /// emitted; the user-facing message is logged at the chosen level.
    public func log(_ error: CloudGateError, category: String) {
        var text = "[\(error.kind.rawValue)] \(error.userMessage)"
        if let detail = error.technicalDetail {
            text += " | detail: \(detail)"
        }
        log(.error, category: category, text)
    }
}

/// An in-memory sink suitable for diagnostic export and for tests.
/// Because entries are already redacted, the buffer is safe to export.
public final class InMemoryLogSink: LogSink, @unchecked Sendable {
    private var entries: [LogEntry] = []
    private let lock = NSLock()

    public init() {}

    public func write(_ entry: LogEntry) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    public func snapshot() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
