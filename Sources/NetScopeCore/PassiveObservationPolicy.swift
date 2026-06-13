import Foundation

public struct PassiveObservationPolicy: Sendable {
    public init() {}

    public func nextInterval(consecutiveFailures: Int, isPowerConstrained: Bool) -> TimeInterval {
        let baseInterval = isPowerConstrained
            ? PowerBudget.powerConstrainedRollingAppCounterSampleSeconds
            : PowerBudget.rollingAppCounterSampleSeconds
        let boundedFailures = max(0, min(consecutiveFailures, 4))
        let multiplier = TimeInterval(1 << boundedFailures)

        return min(
            baseInterval * multiplier,
            PowerBudget.maximumRollingAppCounterBackoffSeconds
        )
    }

    public func timerTolerance(for interval: TimeInterval) -> TimeInterval {
        min(30, max(1, interval * 0.25))
    }
}
