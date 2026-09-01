import Foundation
import Combine
import NetScopeCore

enum RollingSampleResult: Sendable {
    case sampled
    case skipped
    case failed
}

private enum ActiveOperation {
    case interactiveObservation
    case rollingSample
    case pathCheck
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
    private var activeOperation: ActiveOperation?
    private var hasQueuedPathCheck = false

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

    func observeCurrentActivity() {
        guard activeOperation == nil else {
            return
        }

        activeOperation = .interactiveObservation
        let service = snapshotService

        Task {
            defer {
                finishAppObservation()
            }

            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try service.captureInteractiveObservation()
                }.value

                observationSession.applyInteractiveObservationSnapshot(snapshot)
                state = observationSession.state
                rollingWarning = nil
            } catch {
                rollingWarning = "App counters unavailable. Keeping the last observed counters."
            }
        }
    }

    func refreshCurrentDiagnosis() {
        guard activeOperation == nil else {
            checkNetworkPath()
            return
        }

        hasQueuedPathCheck = true
        observeCurrentActivity()
    }

    func checkNetworkPath() {
        switch activeOperation {
        case .pathCheck:
            return
        case .interactiveObservation, .rollingSample:
            hasQueuedPathCheck = true
            return
        case nil:
            startPathCheck()
        }
    }

    func recordRollingAppCounterSample(completion: (@MainActor @Sendable (RollingSampleResult) -> Void)? = nil) {
        guard activeOperation == nil else {
            completion?(.skipped)
            return
        }

        activeOperation = .rollingSample
        let service = snapshotService

        Task {
            defer {
                finishAppObservation()
            }

            do {
                let rollingSnapshot = try await Task.detached(priority: .utility) {
                    try service.captureRollingAppCounters()
                }.value

                let baselineChanged = observationSession.applyRollingAppCounterSnapshot(rollingSnapshot)
                state = observationSession.state
                saveBaselineIfNeeded(baselineChanged)
                rollingWarning = nil
                completion?(.sampled)
            } catch {
                rollingWarning = "App counters unavailable. Keeping the last observed counters."
                completion?(.failed)
            }
        }
    }

    func clearBaseline() {
        observationSession.clearBaseline()
        state = observationSession.state
        baselineWarning = nil
        guard let baselinePersistence else {
            return
        }

        baselinePersistence.clear { [weak self] warning in
            self?.baselineWarning = warning
        }
    }

    private func startPathCheck() {
        guard activeOperation == nil else {
            return
        }

        activeOperation = .pathCheck
        isLoading = true
        let service = snapshotService

        Task {
            defer {
                finishPathCheck()
            }

            let currentAppObservation = observationSession.latestAppObservationForPathCheck
            let nextSnapshot = await Task.detached(priority: .utility) {
                service.checkNetworkPath(currentAppSnapshot: currentAppObservation)
            }.value

            observationSession.applyPathCheckSnapshot(nextSnapshot)
            state = observationSession.state
        }
    }

    private func finishAppObservation() {
        activeOperation = nil
        runQueuedPathCheckIfNeeded()
    }

    private func finishPathCheck() {
        isLoading = false
        activeOperation = nil
    }

    private func runQueuedPathCheckIfNeeded() {
        guard hasQueuedPathCheck, activeOperation == nil else {
            return
        }

        hasQueuedPathCheck = false
        startPathCheck()
    }

    private func saveBaselineIfNeeded(_ baselineChanged: Bool) {
        guard baselineChanged,
              let baselinePersistence else {
            return
        }

        let baseline = observationSession.baselineForPersistence
        baselinePersistence.save(baseline) { [weak self] warning in
            self?.baselineWarning = warning
        }
    }
}
