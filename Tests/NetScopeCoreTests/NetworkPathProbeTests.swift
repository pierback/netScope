import Foundation
import Testing
@testable import NetScopeCore

@Test func parsesDefaultGatewayFromRouteOutput() {
    let output = """
       route to: default
    destination: default
           mask: default
        gateway: 192.168.1.1
      interface: en0
    """

    #expect(NetworkPathProbe.parseGateway(from: output) == "192.168.1.1")
}

@Test func pathProbeReportsReachableWhenGatewayPublicPingAndDNSWork() {
    let runner = PathCommandRunner(
        routeOutput: routeOutput(gateway: "192.168.1.1"),
        pingByHost: [
            "192.168.1.1": pingOutput(host: "192.168.1.1", loss: 0, avg: 4.2),
            "1.1.1.1": pingOutput(host: "1.1.1.1", loss: 0, avg: 18.5),
        ],
        dnsOutput: "17.253.144.10\n"
    )

    let check = NetworkPathProbe(runner: runner).probe()

    #expect(check.gatewayAddress == "192.168.1.1")
    #expect(check.gatewayPing?.averageMilliseconds == 4.2)
    #expect(check.publicPing?.averageMilliseconds == 18.5)
    #expect(check.dnsLookup?.succeeded == true)
    #expect(check.scope == .reachable)
    #expect(runner.executables == ["/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@Test func pathProbeClassifiesBadGatewayAsLocalNetwork() {
    let runner = PathCommandRunner(
        routeOutput: routeOutput(gateway: "192.168.1.1"),
        pingByHost: [
            "192.168.1.1": pingOutput(host: "192.168.1.1", loss: 50, avg: nil),
            "1.1.1.1": pingOutput(host: "1.1.1.1", loss: 0, avg: 20),
        ],
        dnsOutput: "17.253.144.10\n"
    )

    let check = NetworkPathProbe(runner: runner).probe()

    #expect(check.scope == .localNetwork)
}

@Test func pathProbeClassifiesGoodGatewayButBadPublicPingAsInternetPath() {
    let runner = PathCommandRunner(
        routeOutput: routeOutput(gateway: "192.168.1.1"),
        pingByHost: [
            "192.168.1.1": pingOutput(host: "192.168.1.1", loss: 0, avg: 4),
            "1.1.1.1": pingOutput(host: "1.1.1.1", loss: 0, avg: 240),
        ],
        dnsOutput: "17.253.144.10\n"
    )

    let check = NetworkPathProbe(runner: runner).probe()

    #expect(check.scope == .internetPath)
}

@Test func pathProbeClassifiesGoodPingButFailingDNSAsDNSIssue() {
    let runner = PathCommandRunner(
        routeOutput: routeOutput(gateway: "192.168.1.1"),
        pingByHost: [
            "192.168.1.1": pingOutput(host: "192.168.1.1", loss: 0, avg: 4),
            "1.1.1.1": pingOutput(host: "1.1.1.1", loss: 0, avg: 20),
        ],
        dnsOutput: ""
    )

    let check = NetworkPathProbe(runner: runner).probe()

    #expect(check.scope == .dns)
    #expect(check.dnsLookup?.succeeded == false)
}

@Test func reachablePathSummaryDoesNotClaimGatewayProbeWhenGatewayMissing() {
    let runner = PathCommandRunner(
        routeOutput: "route lookup failed\n",
        pingByHost: [
            "1.1.1.1": pingOutput(host: "1.1.1.1", loss: 0, avg: 18),
        ],
        dnsOutput: "17.253.144.10\n"
    )

    let check = NetworkPathProbe(runner: runner).probe()

    #expect(check.gatewayAddress == nil)
    #expect(check.gatewayPing == nil)
    #expect(check.scope == .reachable)
    #expect(check.summary == "Public ping and DNS probes succeeded, but the local gateway could not be checked.")
}

@Test func pathProbeSkipsLaterCommandsWhenDeadlineIsExhausted() {
    let runner = PathCommandRunner(
        routeOutput: routeOutput(gateway: "192.168.1.1"),
        pingByHost: [
            "192.168.1.1": pingOutput(host: "192.168.1.1", loss: 0, avg: 4),
            "1.1.1.1": pingOutput(host: "1.1.1.1", loss: 0, avg: 18),
        ],
        dnsOutput: "17.253.144.10\n",
        delayByExecutable: ["/sbin/route": 0.02]
    )

    let check = NetworkPathProbe(runner: runner, maximumPathCheckSeconds: 0.001).probe()

    #expect(check.gatewayAddress == "192.168.1.1")
    #expect(check.gatewayPing == nil)
    #expect(check.publicPing == nil)
    #expect(check.dnsLookup == nil)
    #expect(runner.executables == ["/sbin/route"])
}

@Test func skippedDNSDueToDeadlineDoesNotClassifyAsDNSFailure() {
    let runner = PathCommandRunner(
        routeOutput: routeOutput(gateway: "192.168.1.1"),
        pingByHost: [
            "192.168.1.1": pingOutput(host: "192.168.1.1", loss: 0, avg: 4),
            "1.1.1.1": pingOutput(host: "1.1.1.1", loss: 0, avg: 18),
        ],
        dnsOutput: "17.253.144.10\n",
        delayByHost: ["1.1.1.1": 0.2]
    )

    let check = NetworkPathProbe(runner: runner, maximumPathCheckSeconds: 0.15).probe()

    #expect(check.gatewayPing != nil)
    #expect(check.publicPing != nil)
    #expect(check.dnsLookup == nil)
    #expect(check.scope == .unknown)
    #expect(runner.executables == ["/sbin/route", "/sbin/ping", "/sbin/ping"])
}

@Test func missingGatewayAndBadPublicPingDoesNotClaimInternetPathBeyondGateway() {
    let runner = PathCommandRunner(
        routeOutput: "route lookup failed\n",
        pingByHost: [
            "1.1.1.1": pingOutput(host: "1.1.1.1", loss: 0, avg: 240),
        ],
        dnsOutput: "17.253.144.10\n"
    )

    let check = NetworkPathProbe(runner: runner).probe()

    #expect(check.gatewayAddress == nil)
    #expect(check.publicPing?.averageMilliseconds == 240)
    #expect(check.scope == .unknown)
    #expect(check.summary == "Network path check could not isolate the fault.")
}

private final class PathCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedExecutables: [String] = []
    private let routeOutput: String
    private let pingByHost: [String: String]
    private let dnsOutput: String
    private let delayByExecutable: [String: TimeInterval]
    private let delayByHost: [String: TimeInterval]

    init(
        routeOutput: String,
        pingByHost: [String: String],
        dnsOutput: String,
        delayByExecutable: [String: TimeInterval] = [:],
        delayByHost: [String: TimeInterval] = [:]
    ) {
        self.routeOutput = routeOutput
        self.pingByHost = pingByHost
        self.dnsOutput = dnsOutput
        self.delayByExecutable = delayByExecutable
        self.delayByHost = delayByHost
    }

    var executables: [String] {
        lock.withLock {
            recordedExecutables
        }
    }

    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        lock.withLock {
            recordedExecutables.append(executable)
        }

        if let delay = delayByExecutable[executable] {
            Thread.sleep(forTimeInterval: delay)
        }

        if executable == "/sbin/route" {
            return CommandResult(exitCode: 0, stdout: routeOutput, stderr: "")
        }

        if executable == "/sbin/ping" {
            let host = arguments.last ?? ""
            if let delay = delayByHost[host] {
                Thread.sleep(forTimeInterval: delay)
            }

            return CommandResult(exitCode: 0, stdout: pingByHost[host] ?? pingOutput(host: host, loss: 100, avg: nil), stderr: "")
        }

        if executable == "/usr/bin/dig" {
            return CommandResult(exitCode: 0, stdout: dnsOutput, stderr: "")
        }

        return CommandResult(exitCode: 127, stdout: "", stderr: "unexpected executable")
    }
}

private func routeOutput(gateway: String) -> String {
    """
       route to: default
    destination: default
        gateway: \(gateway)
      interface: en0
    """
}

private func pingOutput(host: String, loss: Double, avg: Double?) -> String {
    let timing = avg.map { "round-trip min/avg/max/stddev = \($0)/\($0)/\($0)/0.100 ms" } ?? ""
    let received = loss >= 100 ? 0 : 2
    return """
    PING \(host) (\(host)): 56 data bytes

    --- \(host) ping statistics ---
    2 packets transmitted, \(received) packets received, \(loss)% packet loss
    \(timing)
    """
}
