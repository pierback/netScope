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
    private var isForegroundObservationActive = false

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
        guard PowerBudget.allowsRollingAppCounterSampling else {
            return
        }

        failureCount = 0
        schedule(after: PowerBudget.initialObservationDelaySeconds)
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        pause()
    }

    func setForegroundObservationActive(_ isActive: Bool) {
        isForegroundObservationActive = isActive
    }

    func scheduleNext() {
        schedule()
    }

    func runNow() {
        guard PowerBudget.allowsRollingAppCounterSampling else {
            return
        }

        runSample { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .sampled:
                failureCount = 0
            case .skipped:
                break
            case .failed:
                failureCount += 1
            }

            schedule()
        }
    }

    private func schedule(after interval: TimeInterval? = nil) {
        guard PowerBudget.allowsRollingAppCounterSampling else {
            return
        }

        pause()
        let nextInterval = interval ?? nextObservationInterval
        let nextTimer = Timer.scheduledTimer(withTimeInterval: nextInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runNow()
            }
        }
        nextTimer.tolerance = observationPolicy.timerTolerance(for: nextInterval)
        timer = nextTimer
    }

    private var nextObservationInterval: TimeInterval {
        if isForegroundObservationActive && !isPowerConstrained() && failureCount == 0 {
            return PowerBudget.foregroundObservationSampleSeconds
        }

        return observationPolicy.nextInterval(
            consecutiveFailures: failureCount,
            isPowerConstrained: isPowerConstrained()
        )
    }
}
