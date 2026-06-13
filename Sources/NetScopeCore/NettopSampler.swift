import Foundation

public enum NettopError: Error, CustomStringConvertible {
    case commandFailed(CommandResult)
    case malformedOutput(String)

    public var description: String {
        switch self {
        case let .commandFailed(result):
            return "nettop failed with \(result.exitCode): \(result.stderr)"
        case let .malformedOutput(output):
            return "nettop returned malformed output: \(output)"
        }
    }
}

public struct NettopSampler: Sendable {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func sample() throws -> [AppTraffic] {
        let result = try runner.run(
            "/usr/bin/nettop",
            arguments: [
                "-P",
                "-L", "\(PowerBudget.nettopSamples)",
                "-d",
                "-x",
                "-J", "bytes_in,bytes_out,re-tx",
                "-m", "tcp",
            ]
        )

        guard result.exitCode == 0 else {
            throw NettopError.commandFailed(result)
        }

        guard NettopOutputParser.containsSampleHeader(result.stdout) else {
            throw NettopError.malformedOutput(result.stdout)
        }

        let parseResult = NettopOutputParser.parseLastSampleResult(result.stdout)
        if parseResult.apps.isEmpty && parseResult.parsedRows == 0 && parseResult.malformedRows > 0 {
            throw NettopError.malformedOutput(result.stdout)
        }

        return parseResult.apps
    }
}

public struct NettopParseResult: Equatable, Sendable {
    public let apps: [AppTraffic]
    public let parsedRows: Int
    public let ignoredZeroRows: Int
    public let malformedRows: Int

    public init(apps: [AppTraffic], parsedRows: Int, ignoredZeroRows: Int, malformedRows: Int) {
        self.apps = apps
        self.parsedRows = parsedRows
        self.ignoredZeroRows = ignoredZeroRows
        self.malformedRows = malformedRows
    }
}

public enum NettopOutputParser {
    public static func containsSampleHeader(_ output: String) -> Bool {
        output
            .split(whereSeparator: \.isNewline)
            .contains { $0.hasPrefix(",bytes_in,bytes_out") }
    }

    public static func parseLastSample(_ output: String) -> [AppTraffic] {
        parseLastSampleResult(output).apps
    }

    public static func parseLastSampleResult(_ output: String) -> NettopParseResult {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let lastHeaderIndex = lines.lastIndex(where: { $0.hasPrefix(",bytes_in,bytes_out") }) else {
            return NettopParseResult(apps: [], parsedRows: 0, ignoredZeroRows: 0, malformedRows: 0)
        }

        var apps: [AppTraffic] = []
        var parsedRows = 0
        var ignoredZeroRows = 0
        var malformedRows = 0

        for line in lines[(lastHeaderIndex + 1)...] {
            switch parseProcessLine(line) {
            case let .app(app):
                apps.append(app)
                parsedRows += 1
            case .zeroTraffic:
                ignoredZeroRows += 1
            case .malformed:
                malformedRows += 1
            }
        }

        return NettopParseResult(
            apps: apps,
            parsedRows: parsedRows,
            ignoredZeroRows: ignoredZeroRows,
            malformedRows: malformedRows
        )
    }

    private static func parseProcessLine(_ line: String) -> ParsedNettopLine {
        let columns = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 4 else {
            return .malformed
        }

        let identity = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else {
            return .malformed
        }

        guard let bytesIn = Int(columns[1]),
              let bytesOut = Int(columns[2]),
              let retransmits = Int(columns[3]) else {
            return .malformed
        }

        guard bytesIn + bytesOut + retransmits > 0 else {
            return .zeroTraffic
        }

        let parsedIdentity = parseIdentity(identity)
        return .app(AppTraffic(
            displayName: parsedIdentity.name,
            pid: parsedIdentity.pid,
            bytesInPerSecond: bytesIn,
            bytesOutPerSecond: bytesOut,
            retransmitsPerSecond: retransmits
        ))
    }

    private static func parseIdentity(_ identity: String) -> (name: String, pid: Int?) {
        guard let dotIndex = identity.lastIndex(of: ".") else {
            return (identity, nil)
        }

        let pidCandidate = String(identity[identity.index(after: dotIndex)...])
        guard let pid = Int(pidCandidate) else {
            return (identity, nil)
        }

        let name = String(identity[..<dotIndex])
        return (name.isEmpty ? identity : name, pid)
    }

    private enum ParsedNettopLine {
        case app(AppTraffic)
        case zeroTraffic
        case malformed
    }
}
