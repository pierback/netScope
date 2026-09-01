import Foundation

public struct ObservationState: Equatable, Sendable {
    public var snapshot: NetworkSnapshot?
    public var lastPathCheck: NetworkSnapshot?
    public var correlation: RecentCorrelation?
    public var status: NetworkStatus
    public var effectiveConfidence: Confidence
    public var baselineAssessment: TrafficBaselineAssessment?
    public var learnedBaselineAppCount: Int
    public var trafficTrend: [TrafficTrendPoint]
    public var lastRollingSampleAt: Date?

    public init(
        snapshot: NetworkSnapshot? = nil,
        lastPathCheck: NetworkSnapshot? = nil,
        correlation: RecentCorrelation? = nil,
        status: NetworkStatus = .normal,
        effectiveConfidence: Confidence = .low,
        baselineAssessment: TrafficBaselineAssessment? = nil,
        learnedBaselineAppCount: Int = 0,
        trafficTrend: [TrafficTrendPoint] = [],
        lastRollingSampleAt: Date? = nil
    ) {
        self.snapshot = snapshot
        self.lastPathCheck = lastPathCheck
        self.correlation = correlation
        self.status = status
        self.effectiveConfidence = effectiveConfidence
        self.baselineAssessment = baselineAssessment
        self.learnedBaselineAppCount = learnedBaselineAppCount
        self.trafficTrend = trafficTrend
        self.lastRollingSampleAt = lastRollingSampleAt
    }
}
