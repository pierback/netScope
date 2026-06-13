import Testing
@testable import NetScopeCore

@Test func defaultsProtectBatteryAndResponsiveness() {
    #expect(PowerBudget.allowsRollingAppCounterSampling == true)
    #expect(PowerBudget.allowsBackgroundActiveProbes == false)
    #expect(PowerBudget.nettopSamples == 2)
    #expect(PowerBudget.pingPackets <= 2)
    #expect(PowerBudget.maximumCommandSeconds <= 10)
    #expect(PowerBudget.initialObservationDelaySeconds >= 5)
    #expect(PowerBudget.foregroundObservationSampleSeconds >= 10)
    #expect(PowerBudget.rollingAppCounterSampleSeconds >= 60)
    #expect(PowerBudget.powerConstrainedRollingAppCounterSampleSeconds >= 5 * 60)
    #expect(PowerBudget.maximumRollingAppCounterBackoffSeconds >= PowerBudget.powerConstrainedRollingAppCounterSampleSeconds)
    #expect(PowerBudget.maximumHistoryAgeSeconds <= 30 * 60)
    #expect(PowerBudget.maximumHistorySamples <= 30)
    #expect(PowerBudget.maximumBaselineAgeSeconds <= 7 * 24 * 60 * 60)
    #expect(PowerBudget.maximumBaselineApps <= 100)
    #expect(PowerBudget.minimumBaselineSamplesForComparison >= 3)
    #expect(PowerBudget.baselineMinimumComparableBytesPerSecond >= 32 * 1024)
}

@Test func passiveObservationPolicyBacksOffAfterFailures() {
    let policy = PassiveObservationPolicy()

    #expect(policy.nextInterval(consecutiveFailures: 0, isPowerConstrained: false) == 60)
    #expect(policy.nextInterval(consecutiveFailures: 1, isPowerConstrained: false) == 120)
    #expect(policy.nextInterval(consecutiveFailures: 3, isPowerConstrained: false) == 480)
    #expect(policy.nextInterval(consecutiveFailures: 8, isPowerConstrained: false) == PowerBudget.maximumRollingAppCounterBackoffSeconds)
}

@Test func passiveObservationPolicySlowsDownWhenPowerConstrained() {
    let policy = PassiveObservationPolicy()

    #expect(policy.nextInterval(consecutiveFailures: 0, isPowerConstrained: true) == PowerBudget.powerConstrainedRollingAppCounterSampleSeconds)
    #expect(policy.nextInterval(consecutiveFailures: 2, isPowerConstrained: true) == PowerBudget.maximumRollingAppCounterBackoffSeconds)
}

@Test func passiveObservationTimerToleranceAllowsWakeupCoalescing() {
    let policy = PassiveObservationPolicy()

    #expect(policy.timerTolerance(for: 60) == 15)
    #expect(policy.timerTolerance(for: 300) == 30)
}
