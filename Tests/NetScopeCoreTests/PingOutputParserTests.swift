import Foundation
import Testing
@testable import NetScopeCore

@Test func parsesMacOSPingSummary() throws {
    let output = """
    PING 1.1.1.1 (1.1.1.1): 56 data bytes

    --- 1.1.1.1 ping statistics ---
    3 packets transmitted, 3 packets received, 0.0% packet loss
    round-trip min/avg/max/stddev = 17.352/19.055/21.333/1.667 ms
    """

    let result = try PingOutputParser.parse(output, host: "1.1.1.1")

    #expect(result.transmitted == 3)
    #expect(result.received == 3)
    #expect(result.packetLossPercent == 0)
    #expect(result.averageMilliseconds == 19.055)
}

@Test func probeParsesPacketLossWhenPingExitsNonZero() throws {
    let output = """
    PING 1.1.1.1 (1.1.1.1): 56 data bytes

    --- 1.1.1.1 ping statistics ---
    2 packets transmitted, 0 packets received, 100.0% packet loss
    """
    let probe = PingProbe(runner: StaticPingRunner(result: CommandResult(exitCode: 2, stdout: output, stderr: "")))

    let result = try probe.probe(host: "1.1.1.1")

    #expect(result.transmitted == 2)
    #expect(result.received == 0)
    #expect(result.packetLossPercent == 100)
    #expect(result.averageMilliseconds == nil)
}

@Test func pathProblemThresholdsAreInclusiveAndHandleMissingLatency() {
    #expect(ping(loss: 5, average: nil).indicatesPathProblem)
    #expect(ping(loss: 0, average: 150).indicatesPathProblem)
    #expect(!ping(loss: 4.999, average: 149.999).indicatesPathProblem)
    #expect(!ping(loss: 0, average: nil).indicatesPathProblem)
}

private func ping(loss: Double, average: Double?) -> PingResult {
    PingResult(
        host: "1.1.1.1",
        transmitted: 2,
        received: loss == 100 ? 0 : 2,
        packetLossPercent: loss,
        averageMilliseconds: average
    )
}

private struct StaticPingRunner: CommandRunning {
    let result: CommandResult

    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        result
    }
}
