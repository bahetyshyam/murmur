import Foundation

/// Minimal assertion harness. Collects failures, prints a summary, and
/// exits non-zero on any failure. Used because Command Line Tools ships
/// neither XCTest nor a working swift-testing import path.
enum Harness {
    nonisolated(unsafe) static var failures: [(String, String)] = []
    nonisolated(unsafe) static var currentSuite = "<unknown>"
    nonisolated(unsafe) static var currentTest = "<unknown>"
    nonisolated(unsafe) static var totalTests = 0

    static func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        print("▸ \(name)")
        do {
            try body()
        } catch {
            record("suite threw: \(error)")
        }
    }

    static func test(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        totalTests += 1
        do {
            try body()
        } catch {
            record("threw: \(error)")
        }
    }

    static func asyncTest(_ name: String, _ body: () async throws -> Void) async {
        currentTest = name
        totalTests += 1
        do {
            try await body()
        } catch {
            record("threw: \(error)")
        }
    }

    static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if !condition() {
            let msg = message()
            record("expect failed\(msg.isEmpty ? "" : ": \(msg)") (\(file):\(line))")
        }
    }

    static func expectEqual<T: Equatable>(
        _ a: T, _ b: T,
        file: StaticString = #file, line: UInt = #line
    ) {
        if a != b {
            record("expected \(a) == \(b) (\(file):\(line))")
        }
    }

    static func expectThrows<E: Error & Equatable>(
        _ expected: E,
        _ body: () throws -> Void,
        file: StaticString = #file, line: UInt = #line
    ) {
        do {
            try body()
            record("expected throw of \(expected), got no throw (\(file):\(line))")
        } catch let e as E where e == expected {
            // ok
        } catch {
            record("expected \(expected), got \(error) (\(file):\(line))")
        }
    }

    static func expectThrowsAsync<E: Error & Equatable>(
        _ expected: E,
        _ body: () async throws -> Void,
        file: StaticString = #file, line: UInt = #line
    ) async {
        do {
            try await body()
            record("expected throw of \(expected), got no throw (\(file):\(line))")
        } catch let e as E where e == expected {
            // ok
        } catch {
            record("expected \(expected), got \(error) (\(file):\(line))")
        }
    }

    static func unwrap<T>(
        _ value: T?,
        file: StaticString = #file, line: UInt = #line
    ) throws -> T {
        guard let v = value else {
            record("expected non-nil (\(file):\(line))")
            throw HarnessError.unwrappedNil
        }
        return v
    }

    private static func record(_ detail: String) {
        let label = "\(currentSuite) / \(currentTest)"
        failures.append((label, detail))
        print("  ✗ \(currentTest) — \(detail)")
    }

    static func summary() -> Int32 {
        print("\n———")
        print("Ran \(totalTests) tests, \(failures.count) failure\(failures.count == 1 ? "" : "s")")
        if !failures.isEmpty {
            print("\nFailures:")
            for (label, detail) in failures {
                print("  \(label): \(detail)")
            }
            return 1
        }
        return 0
    }
}

enum HarnessError: Error { case unwrappedNil }
