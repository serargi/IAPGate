import Foundation

/// A minimal test harness used because this environment lacks XCTest
/// (no full Xcode) and the Swift Testing macro plugin does not load
/// reliably here. It intentionally has no dependencies and no macros.
///
/// Usage:
/// ```swift
/// let suite = TestSuite("MySuite")
/// suite.test("does a thing") { t in
///     t.expect(1 + 1 == 2)
/// }
/// // ... register more ...
/// exit(TestRunner.run([suite]))
/// ```
public final class TestContext {
    public private(set) var failures: [String] = []
    private let name: String

    init(_ name: String) { self.name = name }

    /// Records a failure if `condition` is false.
    public func expect(
        _ condition: Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if !condition {
            let loc = "\(shortFile(file)):\(line)"
            let msg = message()
            failures.append("expect failed at \(loc)\(msg.isEmpty ? "" : ": \(msg)")")
        }
    }

    public func expectEqual<T: Equatable>(
        _ a: T,
        _ b: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if a != b {
            let loc = "\(shortFile(file)):\(line)"
            failures.append("expectEqual failed at \(loc): \(a) != \(b)")
        }
    }

    /// Records a failure if `body` does NOT throw.
    public func expectThrows(
        _ body: () throws -> Void,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            try body()
            failures.append("expectThrows failed at \(shortFile(file)):\(line): no error thrown")
        } catch {
            // expected
        }
    }

    /// Records a failure unless `body` throws an error equal to `expected`.
    public func expectThrows<E: Error & Equatable>(
        _ expected: E,
        _ body: () throws -> Void,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            try body()
            failures.append("expectThrows failed at \(shortFile(file)):\(line): no error thrown")
        } catch let e as E where e == expected {
            // expected
        } catch {
            failures.append("expectThrows failed at \(shortFile(file)):\(line): got \(error), expected \(expected)")
        }
    }

    private func shortFile(_ file: StaticString) -> String {
        let s = "\(file)"
        return URL(fileURLWithPath: s).lastPathComponent
    }
}

public final class TestSuite {
    let name: String
    private var cases: [(String, (TestContext) async -> Void)] = []

    public init(_ name: String) { self.name = name }

    public func test(_ title: String, _ body: @escaping (TestContext) -> Void) {
        cases.append((title, { ctx in body(ctx) }))
    }

    /// Registers an async test case.
    public func test(
        _ title: String,
        _ body: @escaping (TestContext) async -> Void
    ) {
        cases.append((title, { ctx in await body(ctx) }))
    }

    func run() async -> (passed: Int, failed: Int) {
        var passed = 0, failed = 0
        print("◇ Suite \"\(name)\"")
        for (title, body) in cases {
            let ctx = TestContext(name)
            await body(ctx)
            if ctx.failures.isEmpty {
                passed += 1
                print("  ✔ \(title)")
            } else {
                failed += 1
                print("  ✘ \(title)")
                for f in ctx.failures { print("      \(f)") }
            }
        }
        return (passed, failed)
    }
}

public enum TestRunner {
    /// Runs all suites, prints a summary, and returns a process exit
    /// code (0 = all passed, 1 = at least one failure).
    public static func run(_ suites: [TestSuite]) async -> Int32 {
        var totalPassed = 0, totalFailed = 0
        for suite in suites {
            let (p, f) = await suite.run()
            totalPassed += p
            totalFailed += f
        }
        print("――――――――――――――――――――――――――――――――――――")
        print("Total: \(totalPassed + totalFailed) tests, \(totalPassed) passed, \(totalFailed) failed")
        return totalFailed == 0 ? 0 : 1
    }
}
