import Foundation
import Testing
@testable import NetScopeMenuBar
import NetScopeCore

@MainActor
@Test func rollingSamplePublishesObservationState() async {
    let runner = SuccessfulNettopRunner()
    let model = MenuBarModel(
        snapshotService: SnapshotService(sampler: NettopSampler(runner: runner)),
        baselineStore: EmptyBaselineStore()
    )

    var result: RollingSampleResult?
    model.recordRollingAppCounterSample { outcome in
        result = outcome
    }

    await waitUntil { result != nil }

    #expect(result == .sampled)
    #expect(model.state.snapshot?.kind == .rollingAppCounters)
    #expect(model.state.correlation == nil)
    #expect(model.state.learnedBaselineAppCount == 1)
    #expect(model.state.trafficTrend.count == 1)
    #expect(model.state.lastRollingSampleAt != nil)
}

@MainActor
@Test func failedRollingSampleClearsInFlightGuardForNextAttempt() async {
    let model = MenuBarModel(
        snapshotService: SnapshotService(sampler: NettopSampler(runner: FailingNettopRunner())),
        baselineStore: EmptyBaselineStore()
    )

    var firstResult: RollingSampleResult?
    model.recordRollingAppCounterSample { outcome in
        firstResult = outcome
    }

    await waitUntil { firstResult != nil }

    var secondResult: RollingSampleResult?
    model.recordRollingAppCounterSample { outcome in
        secondResult = outcome
    }

    await waitUntil { secondResult != nil }

    #expect(firstResult == .failed)
    #expect(secondResult == .failed)
    #expect(model.rollingWarning == "App counters unavailable. Keeping the last observed counters.")
}

@MainActor
@Test func initWarnsWhenDefaultBaselineStoreCannotBeCreated() {
    let model = MenuBarModel(
        baselineStoreFactory: {
            throw TrafficBaselineStoreError.applicationSupportUnavailable
        }
    )

    #expect(model.baselineWarning == "Could not enable learned baseline.")
    #expect(model.state.learnedBaselineAppCount == 0)
}

@MainActor
@Test func learnedBaselineSavesOffMainThread() async {
    let store = RecordingBaselineStore()
    let model = MenuBarModel(
        snapshotService: SnapshotService(sampler: NettopSampler(runner: SuccessfulNettopRunner())),
        baselineStore: store
    )

    var result: RollingSampleResult?
    model.recordRollingAppCounterSample { outcome in
        result = outcome
    }

    await waitUntil { result != nil && store.saveCallCount == 1 }

    #expect(result == .sampled)
    #expect(store.saveCallCount == 1)
    #expect(store.lastSaveWasOnMainThread == false)
    #expect(model.baselineWarning == nil)
}

@MainActor
@Test func pathCheckQueuesBehindInFlightRollingSample() async {
    let runner = PathCheckCommandRunner(
        nettopResults: [.success()],
        nettopDelaySeconds: 0.05
    )
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let model = MenuBarModel(snapshotService: service, baselineStore: EmptyBaselineStore())

    var rollingResult: RollingSampleResult?
    model.recordRollingAppCounterSample { outcome in
        rollingResult = outcome
    }
    model.checkNetworkPath()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        rollingResult != nil && model.state.lastPathCheck != nil
    }

    #expect(rollingResult == .sampled)
    #expect(model.state.lastPathCheck?.kind == .pathCheck)
    #expect(model.state.lastPathCheck?.apps.isEmpty == false)

    switch model.state.lastPathCheck?.appEvidenceSource {
    case .reusedFromSnapshot:
        break
    default:
        Issue.record("Expected queued path check to reuse the just-finished app observation.")
    }

    #expect(runner.executables == ["/usr/bin/nettop", "/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@MainActor
@Test func refreshCurrentDiagnosisCapturesFreshAppsBeforePathCheck() async {
    let runner = PathCheckCommandRunner(
        nettopResults: [.success()],
        nettopDelaySeconds: 0.05
    )
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let model = MenuBarModel(snapshotService: service, baselineStore: EmptyBaselineStore())

    model.refreshCurrentDiagnosis()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        model.state.lastPathCheck != nil
    }

    #expect(model.state.snapshot?.kind == .pathCheck)
    #expect(model.state.lastPathCheck?.apps.isEmpty == false)

    switch model.state.lastPathCheck?.appEvidenceSource {
    case .reusedFromSnapshot:
        break
    default:
        Issue.record("Expected refresh to reuse the fresh app observation for the path check.")
    }

    #expect(runner.executables == ["/usr/bin/nettop", "/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@MainActor
@Test func refreshCurrentDiagnosisStillRunsPathCheckWhenAppSamplingFails() async {
    let runner = PathCheckCommandRunner(nettopResults: [.timedOut])
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let model = MenuBarModel(snapshotService: service, baselineStore: EmptyBaselineStore())

    model.refreshCurrentDiagnosis()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        model.state.lastPathCheck != nil
    }

    #expect(model.rollingWarning == "App counters unavailable. Keeping the last observed counters.")
    #expect(model.state.snapshot?.kind == .pathCheck)

    switch model.state.lastPathCheck?.appEvidenceSource {
    case .unavailable:
        break
    default:
        Issue.record("Expected refresh path check to continue without app evidence after nettop failure.")
    }

    #expect(runner.executables == ["/usr/bin/nettop", "/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@MainActor
@Test func refreshCurrentDiagnosisWaitsForFreshObservationInsteadOfReusingOlderSnapshot() async {
    let runner = PathCheckCommandRunner(
        nettopResults: [
            .success(stdout: """
            ,bytes_in,bytes_out,re-tx,
            oldapp.42,20000,8000,0,
            """),
            .success(stdout: """
            ,bytes_in,bytes_out,re-tx,
            newapp.43,64000,16000,0,
            """)
        ],
        nettopDelaySeconds: 0.05
    )
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let model = MenuBarModel(snapshotService: service, baselineStore: EmptyBaselineStore())

    model.observeCurrentActivity()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        model.state.snapshot?.kind == .interactive
    }

    let previousObservationID = model.state.snapshot?.appObservationID
    #expect(model.state.snapshot?.apps.map(\.displayName) == ["oldapp"])

    model.refreshCurrentDiagnosis()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        guard let lastPathCheck = model.state.lastPathCheck else {
            return false
        }

        return lastPathCheck.appObservationID != previousObservationID
    }

    #expect(model.state.lastPathCheck?.apps.map(\.displayName) == ["newapp"])
    #expect(model.state.lastPathCheck?.appObservationID != previousObservationID)
    #expect(runner.executables == ["/usr/bin/nettop", "/usr/bin/nettop", "/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@MainActor
@Test func successfulRefreshClearsPreviousAppCounterWarning() async {
    let runner = PathCheckCommandRunner(
        nettopResults: [
            .timedOut,
            .success()
        ]
    )
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let model = MenuBarModel(snapshotService: service, baselineStore: EmptyBaselineStore())

    model.observeCurrentActivity()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        model.rollingWarning != nil
    }

    model.refreshCurrentDiagnosis()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        model.state.lastPathCheck != nil
    }

    #expect(model.rollingWarning == nil)
    #expect(model.state.lastPathCheck?.apps.isEmpty == false)
    #expect(runner.executables == ["/usr/bin/nettop", "/usr/bin/nettop", "/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@MainActor
@Test func refreshCurrentDiagnosisWhileObservationIsInFlightClearsPreviousWarning() async {
    let runner = PathCheckCommandRunner(
        nettopResults: [
            .timedOut,
            .success()
        ],
        nettopDelaySeconds: 0.05
    )
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let model = MenuBarModel(snapshotService: service, baselineStore: EmptyBaselineStore())

    model.observeCurrentActivity()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        model.rollingWarning != nil
    }

    model.observeCurrentActivity()
    model.refreshCurrentDiagnosis()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        model.state.lastPathCheck != nil
    }

    #expect(model.rollingWarning == nil)
    #expect(model.state.lastPathCheck?.apps.isEmpty == false)
    #expect(runner.executables == ["/usr/bin/nettop", "/usr/bin/nettop", "/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@MainActor
@Test func refreshCurrentDiagnosisDoesNotPersistBaselineTwice() async {
    let store = RecordingBaselineStore()
    let runner = PathCheckCommandRunner(
        nettopResults: [
            .success(),
            .success()
        ]
    )
    let service = SnapshotService(
        sampler: NettopSampler(runner: runner),
        pingProbe: PingProbe(runner: runner),
        pathProbe: NetworkPathProbe(runner: runner)
    )
    let model = MenuBarModel(snapshotService: service, baselineStore: store)

    var rollingResult: RollingSampleResult?
    model.recordRollingAppCounterSample { outcome in
        rollingResult = outcome
    }

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        rollingResult != nil && store.saveCallCount == 1
    }

    model.refreshCurrentDiagnosis()

    await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        model.state.lastPathCheck != nil
    }

    try? await Task.sleep(for: .milliseconds(100))

    #expect(rollingResult == .sampled)
    #expect(store.saveCallCount == 1)
    #expect(runner.executables == ["/usr/bin/nettop", "/usr/bin/nettop", "/sbin/route", "/sbin/ping", "/sbin/ping", "/usr/bin/dig"])
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 200_000_000,
    condition: @MainActor @Sendable () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !condition() && DispatchTime.now().uptimeNanoseconds < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private struct SuccessfulNettopRunner: CommandRunning, Sendable {
    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        CommandResult(exitCode: 0, stdout: """
        ,bytes_in,bytes_out,re-tx,
        codex.42,40000,12000,0,
        Safari.43,12000,4000,0,
        """, stderr: "")
    }
}

private struct FailingNettopRunner: CommandRunning, Sendable {
    func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval) throws -> CommandResult {
        throw CommandRunnerError.timedOut(executable: executable, timeoutSeconds: 10)
    }
}

private enum NettopResult: Sendable {
    case success(stdout: String = PathCheckCommandRunner.defaultNettopStdout)
    case timedOut
}

private final class PathCheckCommandRunner: CommandRunning, @unchecked Sendable {
    static let defaultNettopStdout = """
    ,bytes_in,bytes_out,re-tx,
    codex.42,40000,12000,0,
    Safari.43,12000,4000,0,
    """

    private let lock = NSLock()
    private var pendingNettopResults: [NettopResult]
    private var recordedExecutables: [String] = []
    private let nettopDelaySeconds: TimeInterval

    init(
        nettopResults: [NettopResult],
        nettopDelaySeconds: TimeInterval = 0
    ) {
        self.pendingNettopResults = nettopResults
        self.nettopDelaySeconds = nettopDelaySeconds
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

        if executable == "/usr/bin/nettop" {
            if nettopDelaySeconds > 0 {
                Thread.sleep(forTimeInterval: nettopDelaySeconds)
            }

            let nextResult = lock.withLock {
                if pendingNettopResults.isEmpty {
                    return NettopResult.success()
                }

                return pendingNettopResults.removeFirst()
            }

            switch nextResult {
            case let .success(stdout):
                return CommandResult(exitCode: 0, stdout: stdout, stderr: "")
            case .timedOut:
                throw CommandRunnerError.timedOut(executable: executable, timeoutSeconds: timeoutSeconds)
            }
        }

        if executable == "/sbin/ping" {
            let host = arguments.last ?? "1.1.1.1"
            return CommandResult(exitCode: 0, stdout: """
            PING \(host) (\(host)): 56 data bytes

            --- \(host) ping statistics ---
            2 packets transmitted, 2 packets received, 0.0% packet loss
            round-trip min/avg/max/stddev = 8.100/8.500/8.900/0.400 ms
            """, stderr: "")
        }

        if executable == "/sbin/route" {
            return CommandResult(exitCode: 0, stdout: """
               route to: default
            destination: default
                gateway: 192.168.1.1
              interface: en0
            """, stderr: "")
        }

        if executable == "/usr/bin/dig" {
            return CommandResult(exitCode: 0, stdout: "17.253.144.10\n", stderr: "")
        }

        return CommandResult(exitCode: 127, stdout: "", stderr: "unexpected executable")
    }
}

private struct EmptyBaselineStore: TrafficBaselineStoring, Sendable {
    func load() throws -> TrafficBaseline {
        TrafficBaseline()
    }

    func save(_ baseline: TrafficBaseline) throws {}

    func clear() throws {}
}

private final class RecordingBaselineStore: TrafficBaselineStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSaveCallCount = 0
    private var recordedLastSaveWasOnMainThread = true

    var saveCallCount: Int {
        lock.withLock {
            recordedSaveCallCount
        }
    }

    var lastSaveWasOnMainThread: Bool {
        lock.withLock {
            recordedLastSaveWasOnMainThread
        }
    }

    func load() throws -> TrafficBaseline {
        TrafficBaseline()
    }

    func save(_ baseline: TrafficBaseline) throws {
        lock.withLock {
            recordedSaveCallCount += 1
            recordedLastSaveWasOnMainThread = Thread.isMainThread
        }
    }

    func clear() throws {}
}
