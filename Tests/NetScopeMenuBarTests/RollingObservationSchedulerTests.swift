import Foundation
import Testing
@testable import NetScopeMenuBar
import NetScopeCore

@MainActor
@Test func skippedForegroundSampleKeepsForegroundCadence() {
    let scheduler = RollingObservationScheduler(
        isPowerConstrained: { false },
        runSample: { _ in }
    )

    scheduler.setForegroundObservationActive(true)

    #expect(scheduler.nextInterval(after: .skipped) == PowerBudget.foregroundObservationSampleSeconds)
}

@MainActor
@Test func failedSamplesBackOffProgressively() {
    let policy = PassiveObservationPolicy()
    let scheduler = RollingObservationScheduler(
        observationPolicy: policy,
        isPowerConstrained: { false },
        runSample: { _ in }
    )

    #expect(scheduler.nextInterval(after: .failed) == policy.nextInterval(consecutiveFailures: 1, isPowerConstrained: false))
    #expect(scheduler.nextInterval(after: .failed) == policy.nextInterval(consecutiveFailures: 2, isPowerConstrained: false))
}
