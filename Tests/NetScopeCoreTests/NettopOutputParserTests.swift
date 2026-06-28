import Foundation
import Testing
@testable import NetScopeCore

@Test func parsesLastDeltaSampleOnly() {
    let output = """
    ,bytes_in,bytes_out,re-tx,
    Dropbox.10,1000000,2000000,0,
    Safari.11,10,20,0,
    ,bytes_in,bytes_out,re-tx,
    Dropbox.10,512000,1024000,7,
    Safari.11,100,200,0,
    Idle.12,0,0,0,
    """

    let apps = NettopOutputParser.parseLastSample(output)

    #expect(apps == [
        AppTraffic(
            displayName: "Dropbox",
            pid: 10,
            bytesInPerSecond: 512000,
            bytesOutPerSecond: 1024000,
            retransmitsPerSecond: 7
        ),
        AppTraffic(
            displayName: "Safari",
            pid: 11,
            bytesInPerSecond: 100,
            bytesOutPerSecond: 200,
            retransmitsPerSecond: 0
        ),
    ])
}

@Test func samplerTreatsValidEmptySampleAsIdleTraffic() throws {
    let output = """
    ,bytes_in,bytes_out,re-tx,
    Idle.12,0,0,0,
    """
    let sampler = NettopSampler(runner: StaticNettopRunner(result: CommandResult(exitCode: 0, stdout: output, stderr: "")))

    let apps = try sampler.sample()

    #expect(apps == [])
}

@Test func samplerTreatsMissingHeaderAsMalformedOutput() {
    let sampler = NettopSampler(runner: StaticNettopRunner(result: CommandResult(exitCode: 0, stdout: "not csv", stderr: "")))

    #expect(throws: NettopError.self) {
        _ = try sampler.sample()
    }
}

@Test func nettopHeaderWithMalformedRowsIsNotReportedAsIdle() {
    let output = """
    ,bytes_in,bytes_out,re-tx,
    Dropbox.10,not-a-number,2000,0,
    Safari.11,1000,nope,0,
    """
    let sampler = NettopSampler(runner: StaticNettopRunner(result: CommandResult(exitCode: 0, stdout: output, stderr: "")))

    #expect(throws: NettopError.self) {
        _ = try sampler.sample()
    }
}

@Test func parserReportsMixedMalformedRowsWithoutDroppingValidApps() {
    let output = """
    ,bytes_in,bytes_out,re-tx,
    Dropbox.10,1000,2000,0,
    Safari.11,1000,nope,0,
    Idle.12,0,0,0,
    """

    let result = NettopOutputParser.parseLastSampleResult(output)

    #expect(result.apps.map(\.displayName) == ["Dropbox"])
    #expect(result.parsedRows == 1)
    #expect(result.ignoredZeroRows == 1)
    #expect(result.malformedRows == 1)
}

private struct StaticNettopRunner: CommandRunning {
    let result: CommandResult

    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        result
    }
}
