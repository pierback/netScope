import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CommandResult
    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult
}

public extension CommandRunning {
    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        try run(executable, arguments: arguments)
    }
}

public enum CommandRunnerError: Error, CustomStringConvertible {
    case nonZeroExit(executable: String, exitCode: Int32, stderr: String)
    case timedOut(executable: String, timeoutSeconds: TimeInterval)

    public var description: String {
        switch self {
        case let .nonZeroExit(executable, exitCode, stderr):
            return "\(executable) exited with \(exitCode): \(stderr)"
        case let .timedOut(executable, timeoutSeconds):
            return "\(executable) exceeded \(timeoutSeconds) seconds and was stopped"
        }
    }
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        try run(executable, arguments: arguments, timeoutSeconds: PowerBudget.maximumCommandSeconds)
    }

    public func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        let process = Process()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("netscope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let stdoutURL = temporaryDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = temporaryDirectory.appendingPathComponent("stderr.txt")

        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stdoutURL.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stderrURL.path)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)

        defer {
            stdoutHandle.closeFile()
            stderrHandle.closeFile()
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            let terminateDeadline = Date().addingTimeInterval(PowerBudget.processTerminationGraceSeconds)
            while process.isRunning && Date() < terminateDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                #if canImport(Darwin)
                kill(process.processIdentifier, SIGKILL)
                #endif
                process.waitUntilExit()
            }

            throw CommandRunnerError.timedOut(
                executable: executable,
                timeoutSeconds: timeoutSeconds
            )
        }

        stdoutHandle.closeFile()
        stderrHandle.closeFile()

        let stdout = String(data: cappedData(contentsOf: stdoutURL), encoding: .utf8) ?? ""
        let stderr = String(data: cappedData(contentsOf: stderrURL), encoding: .utf8) ?? ""

        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func cappedData(contentsOf url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Data()
        }

        defer {
            try? handle.close()
        }

        return handle.readData(ofLength: PowerBudget.maximumCommandOutputBytes)
    }
}
