import Foundation

public struct ObservationSession: Sendable {
    public private(set) var state: ObservationState

    private var history: SnapshotHistory
    private var baseline: TrafficBaseline
    private let statusPolicy: StatusPolicy
    private var latestAppObservation: NetworkSnapshot?

    public init(
        baseline: TrafficBaseline = TrafficBaseline(),
        history: SnapshotHistory = SnapshotHistory(),
        statusPolicy: StatusPolicy = StatusPolicy()
    ) {
        self.history = history
        self.baseline = baseline
        self.statusPolicy = statusPolicy
        self.state = ObservationState(learnedBaselineAppCount: baseline.learnedAppCount)
    }

    public var latestAppObservationForPathCheck: NetworkSnapshot? {
        latestAppObservation
    }

    public var baselineForPersistence: TrafficBaseline {
        baseline
    }

    public mutating func applyInteractiveObservationSnapshot(_ snapshot: NetworkSnapshot) {
        _ = applyAppObservationSnapshot(snapshot, recordsBaseline: false)
    }

    @discardableResult
    public mutating func applyRollingAppCounterSnapshot(_ snapshot: NetworkSnapshot) -> Bool {
        applyAppObservationSnapshot(snapshot, recordsBaseline: true)
    }

    public mutating func applyPathCheckSnapshot(_ snapshot: NetworkSnapshot) {
        history.record(snapshot)
        let nextCorrelation = history.correlation()
        let nextBaselineAssessment = snapshot.appEvidenceSource.isFreshlySampled
            ? baseline.assess(apps: snapshot.apps, at: snapshot.capturedAt)
            : state.baselineAssessment

        state.lastPathCheck = snapshot
        state.snapshot = snapshot
        state.correlation = nextCorrelation
        state.baselineAssessment = nextBaselineAssessment
        state.trafficTrend = history.trafficTrend()
        updateStatus(correlation: nextCorrelation, now: snapshot.capturedAt)
    }

    public mutating func clearBaseline() {
        baseline = TrafficBaseline()
        state.baselineAssessment = nil
        state.learnedBaselineAppCount = 0
    }

    private mutating func applyAppObservationSnapshot(
        _ snapshot: NetworkSnapshot,
        recordsBaseline: Bool
    ) -> Bool {
        history.record(snapshot)
        let nextCorrelation = history.correlation()
        let nextBaselineAssessment = baseline.assess(apps: snapshot.apps, at: snapshot.capturedAt)
        let baselineChanged = recordsBaseline
            ? baseline.record(apps: snapshot.apps, at: snapshot.capturedAt)
            : false

        latestAppObservation = snapshot
        state.snapshot = snapshot
        state.correlation = nextCorrelation
        state.baselineAssessment = nextBaselineAssessment
        state.learnedBaselineAppCount = baseline.learnedAppCount
        state.trafficTrend = history.trafficTrend()
        if recordsBaseline {
            state.lastRollingSampleAt = snapshot.capturedAt
        }
        updateStatus(correlation: nextCorrelation, now: snapshot.capturedAt)

        return baselineChanged
    }

    private mutating func updateStatus(correlation: RecentCorrelation?, now: Date) {
        let evaluation = statusPolicy.evaluate(
            latestAppObservation: latestAppObservation,
            latestPathCheck: state.lastPathCheck,
            correlation: correlation,
            now: now
        )
        state.effectiveConfidence = evaluation.effectiveConfidence
        state.status = evaluation.status
    }
}
