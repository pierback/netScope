import Foundation

public enum PowerBudget {
    public static let nettopSamples = 2
    public static let pingPackets = 2
    public static let maximumCommandSeconds: TimeInterval = 10
    public static let routeCommandSeconds: TimeInterval = 1
    public static let pingCommandSeconds: TimeInterval = 3
    public static let dnsCommandSeconds: TimeInterval = 3
    public static let maximumPathCheckSeconds: TimeInterval = 9
    public static let processTerminationGraceSeconds: TimeInterval = 0.5
    public static let maximumCommandOutputBytes = 256 * 1024
    public static let initialObservationDelaySeconds: TimeInterval = 10
    public static let rollingAppCounterSampleSeconds: TimeInterval = 60
    public static let powerConstrainedRollingAppCounterSampleSeconds: TimeInterval = 5 * 60
    public static let maximumRollingAppCounterBackoffSeconds: TimeInterval = 10 * 60
    public static let maximumHistoryAgeSeconds: TimeInterval = 30 * 60
    public static let maximumHistorySamples = 30
    public static let pathFindingStatusTTLSeconds: TimeInterval = 10 * 60
    public static let maximumReusableAppEvidenceAgeSeconds: TimeInterval = 5 * 60
    public static let maximumBaselineAgeSeconds: TimeInterval = 7 * 24 * 60 * 60
    public static let maximumBaselineApps = 80
    public static let maximumBaselineFileBytes = 64 * 1024
    public static let minimumBaselineSamplesForComparison = 3
    public static let baselineUnusualTrafficMultiplier = 3.0
    public static let baselineMinimumComparableBytesPerSecond = 32 * 1024
}
