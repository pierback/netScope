import Foundation
import Testing
@testable import NetScopeMenuBar
import NetScopeCore

@MainActor
@Test func skippedSamplesKeepBackgroundCadence() {
    let policy = PassiveObservationPolicy()
    let scheduler = RollingObservationScheduler(
        isPowerConstrained: { false },
        runSample: { _ in }
    )

    #expect(scheduler.nextInterval(after: .skipped) == policy.nextInterval(consecutiveFailures: 0, isPowerConstrained: false))
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

@MainActor
@Test func sampledSamplesResetBackoffToBaseCadence() {
    let policy = PassiveObservationPolicy()
    let scheduler = RollingObservationScheduler(
        observationPolicy: policy,
        isPowerConstrained: { false },
        runSample: { _ in }
    )

    _ = scheduler.nextInterval(after: .failed)

    #expect(scheduler.nextInterval(after: .sampled) == policy.nextInterval(consecutiveFailures: 0, isPowerConstrained: false))
}

@MainActor
@Test func powerConstrainedSamplesUsePowerBudgetCadence() {
    let policy = PassiveObservationPolicy()
    let scheduler = RollingObservationScheduler(
        observationPolicy: policy,
        isPowerConstrained: { true },
        runSample: { _ in }
    )

    #expect(scheduler.nextInterval(after: .sampled) == policy.nextInterval(consecutiveFailures: 0, isPowerConstrained: true))
}
