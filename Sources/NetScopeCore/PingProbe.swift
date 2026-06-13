import Foundation

public enum PingError: Error, CustomStringConvertible {
    case commandFailed(CommandResult)
    case unparsableOutput(String)

    public var description: String {
        switch self {
        case let .commandFailed(result):
            return "ping failed with \(result.exitCode): \(result.stderr)"
        case let .unparsableOutput(output):
            return "could not parse ping output: \(output)"
        }
    }
}

public struct PingProbe: Sendable {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func probe(host: String = "1.1.1.1") throws -> PingResult {
        try probe(host: host, timeoutSeconds: PowerBudget.pingCommandSeconds)
    }

    public func probe(host: String = "1.1.1.1", timeoutSeconds: TimeInterval) throws -> PingResult {
        let result = try runner.run(
            "/sbin/ping",
            arguments: ["-c", "\(PowerBudget.pingPackets)", "-n", "-q", host],
            timeoutSeconds: timeoutSeconds
        )

        do {
            return try PingOutputParser.parse(result.stdout, host: host)
        } catch {
            guard result.exitCode == 0 else {
                throw PingError.commandFailed(result)
            }

            throw error
        }
    }
}

public enum PingOutputParser {
    public static func parse(_ output: String, host: String) throws -> PingResult {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let packetLine = lines.first(where: { $0.contains("packets transmitted") }) else {
            throw PingError.unparsableOutput(output)
        }

        let packetRegex = try NSRegularExpression(
            pattern: #"(\d+) packets transmitted, (\d+) packets received, ([0-9.]+)% packet loss"#
        )
        let packetRange = NSRange(packetLine.startIndex..<packetLine.endIndex, in: packetLine)
        guard let packetMatch = packetRegex.firstMatch(in: packetLine, range: packetRange),
              let transmitted = Int(capture(1, in: packetLine, match: packetMatch)),
              let received = Int(capture(2, in: packetLine, match: packetMatch)),
              let loss = Double(capture(3, in: packetLine, match: packetMatch)) else {
            throw PingError.unparsableOutput(output)
        }

        let avg = try parseAverageMilliseconds(lines: lines)
        return PingResult(
            host: host,
            transmitted: transmitted,
            received: received,
            packetLossPercent: loss,
            averageMilliseconds: avg
        )
    }

    private static func parseAverageMilliseconds(lines: [String]) throws -> Double? {
        guard let timingLine = lines.first(where: { $0.contains("round-trip") || $0.contains("rtt") }) else {
            return nil
        }

        let parts = timingLine.split(separator: "=")
        guard parts.count == 2 else {
            return nil
        }

        let values = parts[1]
            .replacingOccurrences(of: " ms", with: "")
            .split(separator: "/")
        guard values.count >= 2 else {
            return nil
        }

        return Double(values[1])
    }

    private static func capture(_ index: Int, in string: String, match: NSTextCheckingResult) -> String {
        guard let range = Range(match.range(at: index), in: string) else {
            return ""
        }

        return String(string[range])
    }
}
