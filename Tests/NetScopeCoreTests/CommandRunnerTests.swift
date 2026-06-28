import Foundation
import Testing
@testable import NetScopeCore

@Test func defaultRunUsesMaximumCommandTimeout() throws {
    let runner = TimeoutCapturingRunner()

    _ = try runner.run("/usr/bin/true", arguments: [])

    #expect(runner.recordedTimeout == PowerBudget.maximumCommandSeconds)
}

@Test func processCommandRunnerCapturesStdoutAndStderr() throws {
    let runner = ProcessCommandRunner()

    let result = try runner.run(
        "/bin/sh",
        arguments: ["-c", "printf 'hello'; printf 'warn' 1>&2"],
        timeoutSeconds: 5
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout == "hello")
    #expect(result.stderr == "warn")
}

@Test func processCommandRunnerReturnsNonZeroExitCodeWithoutThrowing() throws {
    let runner = ProcessCommandRunner()

    let result = try runner.run(
        "/bin/sh",
        arguments: ["-c", "printf warn 1>&2; exit 7"],
        timeoutSeconds: 5
    )

    #expect(result.exitCode == 7)
    #expect(result.stdout.isEmpty)
    #expect(result.stderr == "warn")
}

@Test func processCommandRunnerTimesOutLongRunningCommands() {
    let runner = ProcessCommandRunner()

    do {
        _ = try runner.run(
            "/bin/sh",
            arguments: ["-c", "sleep 1"],
            timeoutSeconds: 0.05
        )
        Issue.record("Expected ProcessCommandRunner to time out the long-running command.")
    } catch let error as CommandRunnerError {
        switch error {
        case let .timedOut(executable, timeoutSeconds):
            #expect(executable == "/bin/sh")
            #expect(timeoutSeconds == 0.05)
        }
    } catch {
        Issue.record("Expected CommandRunnerError, got \(error).")
    }
}

@Test func processCommandRunnerEscalatesPastIgnoredTerminateSignal() {
    let runner = ProcessCommandRunner()

    do {
        _ = try runner.run(
            "/bin/sh",
            arguments: ["-c", "trap '' TERM; sleep 1"],
            timeoutSeconds: 0.05
        )
        Issue.record("Expected ProcessCommandRunner to time out the SIGTERM-ignoring command.")
    } catch let error as CommandRunnerError {
        switch error {
        case let .timedOut(executable, timeoutSeconds):
            #expect(executable == "/bin/sh")
            #expect(timeoutSeconds == 0.05)
        }
    } catch {
        Issue.record("Expected CommandRunnerError, got \(error).")
    }
}

@Test func processCommandRunnerCapsCapturedOutputPerStream() throws {
    let runner = ProcessCommandRunner()
    let oversizedBytes = PowerBudget.maximumCommandOutputBytes + 1_024

    let result = try runner.run(
        "/bin/sh",
        arguments: [
            "-c",
            "head -c \(oversizedBytes) /dev/zero | tr '\\000' 'a'; head -c \(oversizedBytes) /dev/zero | tr '\\000' 'b' 1>&2",
        ],
        timeoutSeconds: 5
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout.utf8.count == PowerBudget.maximumCommandOutputBytes)
    #expect(result.stderr.utf8.count == PowerBudget.maximumCommandOutputBytes)
}

private final class TimeoutCapturingRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedTimeout: TimeInterval?

    var recordedTimeout: TimeInterval? {
        lock.withLock {
            capturedTimeout
        }
    }

    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        lock.withLock {
            capturedTimeout = timeoutSeconds
        }
        return CommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}
