import Foundation
import Testing
@testable import NetScopeMenuBar
import NetScopeCore

@MainActor
@Test func rollingSampleProjectsObservationStateThroughModelAccessors() async {
    let runner = SuccessfulNettopRunner()
    let model = MenuBarModel(
        snapshotService: SnapshotService(sampler: NettopSampler(runner: runner)),
        baselineStore: nil
    )

    var result: RollingSampleResult?
    model.recordRollingAppCounterSample { outcome in
        result = outcome
    }

    await waitUntil { result != nil }

    #expect(result == .sampled)
    #expect(model.snapshot?.kind == .rollingAppCounters)
    #expect(model.snapshot == model.state.snapshot)
    #expect(model.lastPathCheck == model.state.lastPathCheck)
    #expect(model.correlation == model.state.correlation)
    #expect(model.status == model.state.status)
    #expect(model.effectiveConfidence == model.state.effectiveConfidence)
    #expect(model.baselineAssessment == model.state.baselineAssessment)
    #expect(model.learnedBaselineAppCount == model.state.learnedBaselineAppCount)
    #expect(model.trafficTrend == model.state.trafficTrend)
    #expect(model.lastRollingSampleAt == model.state.lastRollingSampleAt)
}

@MainActor
@Test func failedRollingSampleClearsInFlightGuardForNextAttempt() async {
    let model = MenuBarModel(
        snapshotService: SnapshotService(sampler: NettopSampler(runner: FailingNettopRunner())),
        baselineStore: nil
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
    #expect(model.learnedBaselineAppCount == 0)
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
    func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        CommandResult(exitCode: 0, stdout: """
        ,bytes_in,bytes_out,re-tx,
        codex.42,40000,12000,0,
        Safari.43,12000,4000,0,
        """, stderr: "")
    }
}

private struct FailingNettopRunner: CommandRunning, Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        throw CommandRunnerError.timedOut(executable: executable, timeoutSeconds: 10)
    }
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
