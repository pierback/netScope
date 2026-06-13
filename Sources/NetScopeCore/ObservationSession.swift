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

    @discardableResult
    public mutating func applyRollingAppCounterSnapshot(_ snapshot: NetworkSnapshot) -> ObservationUpdate {
        history.record(snapshot)
        let nextCorrelation = history.correlation()
        let nextBaselineAssessment = baseline.assess(apps: snapshot.apps, at: snapshot.capturedAt)
        let baselineChanged = baseline.record(apps: snapshot.apps, at: snapshot.capturedAt)

        latestAppObservation = snapshot
        state.snapshot = snapshot
        state.correlation = nextCorrelation
        state.baselineAssessment = nextBaselineAssessment
        state.learnedBaselineAppCount = baseline.learnedAppCount
        state.trafficTrend = history.trafficTrend()
        state.lastRollingSampleAt = snapshot.capturedAt
        updateStatus(correlation: nextCorrelation, now: snapshot.capturedAt)

        return ObservationUpdate(state: state, baselineChanged: baselineChanged)
    }

    @discardableResult
    public mutating func applyPathCheckSnapshot(_ snapshot: NetworkSnapshot) -> ObservationUpdate {
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

        return ObservationUpdate(state: state, baselineChanged: false)
    }

    @discardableResult
    public mutating func clearBaseline() -> ObservationUpdate {
        baseline = TrafficBaseline()
        state.baselineAssessment = nil
        state.learnedBaselineAppCount = 0

        return ObservationUpdate(state: state, baselineChanged: false)
    }

    private mutating func updateStatus(correlation: RecentCorrelation?, now: Date) {
        state.effectiveConfidence = statusPolicy.effectiveConfidence(
            latestAppObservation: latestAppObservation,
            latestPathCheck: state.lastPathCheck,
            correlation: correlation,
            now: now
        )
        state.status = statusPolicy.status(
            latestAppObservation: latestAppObservation,
            latestPathCheck: state.lastPathCheck,
            correlation: correlation,
            now: now
        )
    }
}
