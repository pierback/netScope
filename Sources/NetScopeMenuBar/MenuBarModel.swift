import Foundation
import Combine
import NetScopeCore

enum RollingSampleResult: Sendable {
    case sampled
    case skipped
    case failed
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published private(set) var snapshot: NetworkSnapshot?
    @Published private(set) var lastPathCheck: NetworkSnapshot?
    @Published private(set) var correlation: RecentCorrelation?
    @Published private(set) var status: NetworkStatus = .normal
    @Published private(set) var effectiveConfidence: Confidence = .low
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var rollingWarning: String?
    @Published private(set) var baselineAssessment: TrafficBaselineAssessment?
    @Published private(set) var baselineWarning: String?
    @Published private(set) var learnedBaselineAppCount = 0
    @Published private(set) var trafficTrend: [TrafficTrendPoint] = []
    @Published private(set) var lastRollingSampleAt: Date?

    private let snapshotService: SnapshotService
    private let baselineStore: TrafficBaselineStoring?
    private var observationSession: ObservationSession
    private var isRollingSampleInFlight = false

    init(
        snapshotService: SnapshotService = SnapshotService(),
        statusPolicy: StatusPolicy = StatusPolicy(),
        baselineStore: TrafficBaselineStoring? = MenuBarModel.makeDefaultBaselineStore()
    ) {
        self.snapshotService = snapshotService
        self.baselineStore = baselineStore
        do {
            let loadedBaseline = try baselineStore?.load() ?? TrafficBaseline()
            self.observationSession = ObservationSession(baseline: loadedBaseline, statusPolicy: statusPolicy)
        } catch {
            self.observationSession = ObservationSession(statusPolicy: statusPolicy)
            self.baselineWarning = "Could not read learned baseline."
        }
        apply(observationSession.state)
    }

    func refresh() {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil
        rollingWarning = nil
        let service = snapshotService

        Task {
            do {
                let currentAppObservation = observationSession.latestAppObservationForPathCheck
                let nextSnapshot = try await Task.detached(priority: .utility) {
                    try service.checkNetworkPath(currentAppSnapshot: currentAppObservation)
                }.value

                let update = observationSession.applyPathCheckSnapshot(nextSnapshot)
                apply(update.state)
                isLoading = false
            } catch {
                errorMessage = String(describing: error)
                isLoading = false
            }
        }
    }

    func recordRollingAppCounterSample(completion: (@MainActor @Sendable (RollingSampleResult) -> Void)? = nil) {
        guard !isLoading, !isRollingSampleInFlight else {
            completion?(.skipped)
            return
        }

        isRollingSampleInFlight = true
        let service = snapshotService

        Task {
            do {
                let rollingSnapshot = try await Task.detached(priority: .utility) {
                    try service.captureRollingAppCounters()
                }.value

                let update = observationSession.applyRollingAppCounterSnapshot(rollingSnapshot)
                apply(update.state)
                saveBaselineIfNeeded(update)
                rollingWarning = nil
                isRollingSampleInFlight = false
                completion?(.sampled)
            } catch {
                rollingWarning = "App counters unavailable. Keeping the last observed counters."
                isRollingSampleInFlight = false
                completion?(.failed)
            }
        }
    }

    func clearBaseline() {
        let update = observationSession.clearBaseline()
        apply(update.state)
        do {
            try baselineStore?.clear()
            baselineWarning = nil
        } catch {
            baselineWarning = "Could not clear learned baseline."
        }
    }

    private static func makeDefaultBaselineStore() -> TrafficBaselineStoring? {
        do {
            return try LocalTrafficBaselineStore()
        } catch {
            return nil
        }
    }

    private func apply(_ state: ObservationState) {
        snapshot = state.snapshot
        lastPathCheck = state.lastPathCheck
        correlation = state.correlation
        status = state.status
        effectiveConfidence = state.effectiveConfidence
        baselineAssessment = state.baselineAssessment
        learnedBaselineAppCount = state.learnedBaselineAppCount
        trafficTrend = state.trafficTrend
        lastRollingSampleAt = state.lastRollingSampleAt
    }

    private func saveBaselineIfNeeded(_ update: ObservationUpdate) {
        guard update.baselineChanged else {
            return
        }

        do {
            try baselineStore?.save(observationSession.baselineForPersistence)
            baselineWarning = nil
        } catch {
            baselineWarning = "Could not save learned baseline."
        }
    }
}
