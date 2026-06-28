import Foundation
import Testing
@testable import NetScopeCore

@Test func rollingSnapshotsDoNotRunPingProbe() throws {
    let runner = RecordingCommandRunner()
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )

    let snapshot = try service.captureRollingAppCounters()

    #expect(snapshot.kind == .rollingAppCounters)
    #expect(snapshot.ping == nil)
    #expect(runner.executables == ["/usr/bin/nettop"])
}

@Test func interactiveObservationsDoNotRunPingProbe() throws {
    let runner = RecordingCommandRunner()
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner)
    )

    let snapshot = try service.captureInteractiveObservation()

    #expect(snapshot.kind == .interactive)
    #expect(snapshot.ping == nil)
    #expect(snapshot.wifi != nil)
    #expect(runner.executables == ["/usr/bin/nettop"])
}

@Test func fullChecksRunPingProbe() throws {
    let runner = RecordingCommandRunner()
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner)
    )

    let snapshot = try service.captureFullCheck()

    #expect(snapshot.kind == .interactive)
    #expect(snapshot.ping?.host == "1.1.1.1")
    #expect(snapshot.wifi != nil)
    #expect(runner.executables == ["/usr/bin/nettop", "/sbin/ping"])
}

@Test func pathChecksReuseObservedAppsAndRunPathCheckOnly() throws {
    let runner = RecordingCommandRunner()
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let appObservationID = UUID()
    let apps = [
        AppTraffic(
            displayName: "codex",
            pid: 42,
            bytesInPerSecond: 1000,
            bytesOutPerSecond: 2000,
            retransmitsPerSecond: 0
        )
    ]
    let observedAt = Date(timeIntervalSince1970: 1_000)
    let appSnapshot = NetworkSnapshot(
        capturedAt: observedAt,
        kind: .rollingAppCounters,
        diagnosis: DiagnosisEngine().diagnose(evidence: DiagnosisEvidence(apps: apps)),
        apps: apps,
        appEvidenceCapturedAt: observedAt,
        appEvidenceSource: .freshlySampled,
        appObservationID: appObservationID,
        ping: nil
    )

    let snapshot = service.checkNetworkPath(
        currentAppSnapshot: appSnapshot,
        at: observedAt.addingTimeInterval(60)
    )

    #expect(snapshot.kind == .pathCheck)
    #expect(snapshot.apps == apps)
    #expect(snapshot.appEvidenceCapturedAt == appSnapshot.appEvidenceCapturedAt)
    #expect(snapshot.appEvidenceSource == .reusedFromSnapshot(observedAt))
    #expect(snapshot.appObservationID == appObservationID)
    #expect(snapshot.ping?.host == "1.1.1.1")
    #expect(snapshot.pathCheck?.gatewayAddress == "192.168.1.1")
    #expect(snapshot.pathCheck?.scope == .reachable)
    #expect(runner.executables == ["/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@Test func pathCheckWithNoPriorAppObservationMarksAppEvidenceUnavailable() throws {
    let runner = RecordingCommandRunner()
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )

    let snapshot = service.checkNetworkPath(currentAppSnapshot: nil)

    #expect(snapshot.kind == .pathCheck)
    #expect(snapshot.apps.isEmpty)
    #expect(snapshot.appEvidenceCapturedAt == nil)
    #expect(snapshot.appEvidenceSource == .unavailable)
    #expect(snapshot.appObservationID == nil)
    #expect(runner.executables == ["/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@Test func pathCheckDoesNotReuseStaleAppEvidence() throws {
    let runner = RecordingCommandRunner()
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let observedAt = Date(timeIntervalSince1970: 1_000)
    let checkAt = observedAt.addingTimeInterval(PowerBudget.maximumReusableAppEvidenceAgeSeconds + 1)
    let apps = [
        AppTraffic(
            displayName: "codex",
            pid: 42,
            bytesInPerSecond: 1000,
            bytesOutPerSecond: 2000,
            retransmitsPerSecond: 0
        )
    ]
    let appSnapshot = NetworkSnapshot(
        capturedAt: observedAt,
        kind: .rollingAppCounters,
        diagnosis: DiagnosisEngine().diagnose(evidence: DiagnosisEvidence(apps: apps)),
        apps: apps,
        appEvidenceCapturedAt: observedAt,
        appEvidenceSource: .freshlySampled,
        appObservationID: UUID(),
        ping: nil
    )

    let snapshot = service.checkNetworkPath(currentAppSnapshot: appSnapshot, at: checkAt)

    #expect(snapshot.apps.isEmpty)
    #expect(snapshot.appEvidenceCapturedAt == nil)
    #expect(snapshot.appEvidenceSource == .unavailable)
    #expect(snapshot.appObservationID == nil)
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedExecutables: [String] = []

    var executables: [String] {
        lock.withLock {
            recordedExecutables
        }
    }

    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        lock.withLock {
            recordedExecutables.append(executable)
        }

        if executable == "/usr/bin/nettop" {
            return CommandResult(exitCode: 0, stdout: nettopOutput, stderr: "")
        }

        if executable == "/sbin/ping" {
            let host = arguments.last ?? "1.1.1.1"
            return CommandResult(exitCode: 0, stdout: pingOutput(host: host), stderr: "")
        }

        if executable == "/sbin/route" {
            return CommandResult(exitCode: 0, stdout: routeOutput, stderr: "")
        }

        if executable == "/usr/bin/dig" {
            return CommandResult(exitCode: 0, stdout: "17.253.144.10\n", stderr: "")
        }

        return CommandResult(exitCode: 127, stdout: "", stderr: "unexpected executable")
    }

    private let nettopOutput = """
    ,bytes_in,bytes_out,re-tx,
    Safari.10,1000,2000,0,
    ,bytes_in,bytes_out,re-tx,
    Safari.10,1000000,1000000,0,
    """

    private let routeOutput = """
       route to: default
    destination: default
        gateway: 192.168.1.1
      interface: en0
    """

    private func pingOutput(host: String) -> String {
        """
    PING \(host) (\(host)): 56 data bytes

    --- \(host) ping statistics ---
    2 packets transmitted, 2 packets received, 0.0% packet loss
    round-trip min/avg/max/stddev = 8.100/8.500/8.900/0.400 ms
    """
    }
}
