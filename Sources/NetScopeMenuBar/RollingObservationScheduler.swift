import Foundation
import NetScopeCore

typealias RollingObservationCompletion = @MainActor @Sendable (RollingSampleResult) -> Void

@MainActor
final class RollingObservationScheduler {
    private let observationPolicy: PassiveObservationPolicy
    private let isPowerConstrained: () -> Bool
    private let runSample: (@escaping RollingObservationCompletion) -> Void

    private var timer: Timer?
    private var failureCount = 0

    init(
        observationPolicy: PassiveObservationPolicy = PassiveObservationPolicy(),
        isPowerConstrained: @escaping () -> Bool,
        runSample: @escaping (@escaping RollingObservationCompletion) -> Void
    ) {
        self.observationPolicy = observationPolicy
        self.isPowerConstrained = isPowerConstrained
        self.runSample = runSample
    }

    func start() {
        failureCount = 0
        schedule(after: PowerBudget.initialObservationDelaySeconds)
    }

    func stop() {
        cancelScheduledRun()
    }

    func runNow() {
        runSample { [weak self] result in
            guard let self else {
                return
            }

            schedule(after: nextInterval(after: result))
        }
    }

    func nextInterval(after result: RollingSampleResult) -> TimeInterval {
        switch result {
        case .sampled:
            failureCount = 0
        case .skipped:
            break
        case .failed:
            failureCount += 1
        }

        return intervalForCurrentState()
    }

    private func schedule(after interval: TimeInterval) {
        cancelScheduledRun()
        let nextTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runNow()
            }
        }
        nextTimer.tolerance = observationPolicy.timerTolerance(for: interval)
        timer = nextTimer
    }

    private func cancelScheduledRun() {
        timer?.invalidate()
        timer = nil
    }

    private func intervalForCurrentState() -> TimeInterval {
        observationPolicy.nextInterval(
            consecutiveFailures: failureCount,
            isPowerConstrained: isPowerConstrained()
        )
    }
}
