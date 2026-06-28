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
    @Published private(set) var state: ObservationState
    @Published private(set) var isLoading = false
    @Published private(set) var rollingWarning: String?
    @Published private(set) var baselineWarning: String?

    private let snapshotService: SnapshotService
    private let baselinePersistence: BaselinePersistenceController?
    private var observationSession: ObservationSession
    private var isRollingSampleInFlight = false

    init(
        snapshotService: SnapshotService = SnapshotService(),
        statusPolicy: StatusPolicy = StatusPolicy(),
        baselineStore: (any TrafficBaselineStoring)? = nil,
        baselineStoreFactory: @escaping BaselineStoreFactory = { try LocalTrafficBaselineStore() }
    ) {
        self.snapshotService = snapshotService
        let resolvedBaselineStore: (any TrafficBaselineStoring)?
        if let baselineStore {
            resolvedBaselineStore = baselineStore
        } else {
            do {
                resolvedBaselineStore = try baselineStoreFactory()
            } catch {
                resolvedBaselineStore = nil
                self.baselineWarning = "Could not enable learned baseline."
            }
        }
        self.baselinePersistence = resolvedBaselineStore.map { BaselinePersistenceController(store: $0) }
        do {
            let loadedBaseline = try resolvedBaselineStore?.load() ?? TrafficBaseline()
            self.observationSession = ObservationSession(baseline: loadedBaseline, statusPolicy: statusPolicy)
        } catch {
            self.observationSession = ObservationSession(statusPolicy: statusPolicy)
            self.baselineWarning = "Could not read learned baseline."
        }
        self.state = observationSession.state
    }

    var snapshot: NetworkSnapshot? {
        state.snapshot
    }

    var lastPathCheck: NetworkSnapshot? {
        state.lastPathCheck
    }

    var correlation: RecentCorrelation? {
        state.correlation
    }

    var status: NetworkStatus {
        state.status
    }

    var effectiveConfidence: Confidence {
        state.effectiveConfidence
    }

    var learnedBaselineAppCount: Int {
        state.learnedBaselineAppCount
    }

    var baselineAssessment: TrafficBaselineAssessment? {
        state.baselineAssessment
    }

    var trafficTrend: [TrafficTrendPoint] {
        state.trafficTrend
    }

    var lastRollingSampleAt: Date? {
        state.lastRollingSampleAt
    }

    func refresh() {
        guard !isLoading else {
            return
        }

        isLoading = true
        rollingWarning = nil
        let service = snapshotService

        Task {
            defer {
                isLoading = false
            }

            let currentAppObservation = observationSession.latestAppObservationForPathCheck
            let nextSnapshot = await Task.detached(priority: .utility) {
                service.checkNetworkPath(currentAppSnapshot: currentAppObservation)
            }.value

            let update = observationSession.applyPathCheckSnapshot(nextSnapshot)
            apply(update.state)
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
            defer {
                isRollingSampleInFlight = false
            }

            do {
                let rollingSnapshot = try await Task.detached(priority: .utility) {
                    try service.captureRollingAppCounters()
                }.value

                let update = observationSession.applyRollingAppCounterSnapshot(rollingSnapshot)
                apply(update.state)
                saveBaselineIfNeeded(update)
                rollingWarning = nil
                completion?(.sampled)
            } catch {
                rollingWarning = "App counters unavailable. Keeping the last observed counters."
                completion?(.failed)
            }
        }
    }

    func clearBaseline() {
        let update = observationSession.clearBaseline()
        apply(update.state)
        baselineWarning = nil
        guard let baselinePersistence else {
            return
        }

        baselinePersistence.clear { [weak self] warning in
            self?.baselineWarning = warning
        }
    }

    private func apply(_ state: ObservationState) {
        self.state = state
    }

    private func saveBaselineIfNeeded(_ update: ObservationUpdate) {
        guard update.baselineChanged,
              let baselinePersistence else {
            return
        }

        let baseline = observationSession.baselineForPersistence
        baselinePersistence.save(baseline) { [weak self] warning in
            self?.baselineWarning = warning
        }
    }
}
