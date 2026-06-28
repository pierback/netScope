import Foundation
import Dispatch
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
    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult
}

public extension CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        try run(executable, arguments: arguments, timeoutSeconds: PowerBudget.maximumCommandSeconds)
    }
}

public enum CommandRunnerError: Error, CustomStringConvertible {
    case timedOut(executable: String, timeoutSeconds: TimeInterval)

    public var description: String {
        switch self {
        case let .timedOut(executable, timeoutSeconds):
            return "\(executable) exceeded \(timeoutSeconds) seconds and was stopped"
        }
    }
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = BoundedCommandOutput(limit: PowerBudget.maximumCommandOutputBytes)
        let stderrBuffer = BoundedCommandOutput(limit: PowerBudget.maximumCommandOutputBytes)
        let drainGroup = DispatchGroup()
        let terminationSemaphore = DispatchSemaphore(value: 0)
        let stdoutSource = try makeReadSource(
            from: stdoutPipe.fileHandleForReading,
            into: stdoutBuffer,
            drainGroup: drainGroup
        )
        let stderrSource = try makeReadSource(
            from: stderrPipe.fileHandleForReading,
            into: stderrBuffer,
            drainGroup: drainGroup
        )
        let readSources = [stdoutSource, stderrSource]

        defer {
            for source in readSources {
                source.cancel()
            }
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        try process.run()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        if terminationSemaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            // If the process exits right as the timeout elapses, the pending termination signal
            // makes the grace-period wait below return immediately and keeps this path bounded.
            terminate(process: process, terminationSemaphore: terminationSemaphore)
            drainGroup.wait()
            throw CommandRunnerError.timedOut(
                executable: executable,
                timeoutSeconds: timeoutSeconds
            )
        }

        drainGroup.wait()
        let stdout = stdoutBuffer.stringValue
        let stderr = stderrBuffer.stringValue
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func makeReadSource(
        from handle: FileHandle,
        into buffer: BoundedCommandOutput,
        drainGroup: DispatchGroup
    ) throws -> DispatchSourceRead {
        let fileDescriptor = handle.fileDescriptor
        try setNonBlocking(fileDescriptor: fileDescriptor)

        let queue = DispatchQueue(label: "netscope.command-runner.\(fileDescriptor)", qos: .utility)
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        drainGroup.enter()
        source.setEventHandler {
            var chunk = [UInt8](repeating: 0, count: 4_096)
            while true {
                let bytesRead = read(fileDescriptor, &chunk, chunk.count)
                if bytesRead > 0 {
                    buffer.append(Data(chunk.prefix(bytesRead)))
                    continue
                }

                if bytesRead == 0 {
                    source.cancel()
                    return
                }

                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }

                source.cancel()
                return
            }
        }
        source.setCancelHandler {
            drainGroup.leave()
        }
        source.resume()
        return source
    }

    private func setNonBlocking(fileDescriptor: Int32) throws {
        #if canImport(Darwin)
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags != -1 else {
            throw POSIXError(.EIO)
        }

        guard fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw POSIXError(.EIO)
        }
        #endif
    }

    private func terminate(process: Process, terminationSemaphore: DispatchSemaphore) {
        process.terminate()
        if terminationSemaphore.wait(timeout: .now() + PowerBudget.processTerminationGraceSeconds) == .timedOut {
            #if canImport(Darwin)
            kill(process.processIdentifier, SIGKILL)
            #endif
            process.waitUntilExit()
        }
    }
}

private final class BoundedCommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.withLock {
            let remaining = max(0, limit - data.count)
            guard remaining > 0 else {
                return
            }

            data.append(chunk.prefix(remaining))
        }
    }

    var stringValue: String {
        let capturedData = lock.withLock {
            data
        }
        return String(data: capturedData, encoding: .utf8) ?? ""
    }
}
