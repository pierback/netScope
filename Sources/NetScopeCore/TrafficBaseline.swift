import Foundation

public struct TrafficBaseline: Codable, Equatable, Sendable {
    public private(set) var recordsByAppName: [String: TrafficBaselineRecord]
    public let maximumAgeSeconds: TimeInterval
    public let maximumApps: Int

    public init(
        recordsByAppName: [String: TrafficBaselineRecord] = [:],
        maximumAgeSeconds: TimeInterval = PowerBudget.maximumBaselineAgeSeconds,
        maximumApps: Int = PowerBudget.maximumBaselineApps
    ) {
        self.recordsByAppName = recordsByAppName
        self.maximumAgeSeconds = maximumAgeSeconds
        self.maximumApps = maximumApps
    }

    public var learnedAppCount: Int {
        recordsByAppName.count
    }

    public var maximumSampleCount: Int {
        recordsByAppName.values.map(\.sampleCount).max() ?? 0
    }

    @discardableResult
    public mutating func record(apps: [AppTraffic], at date: Date = Date()) -> Bool {
        let before = self

        for app in apps where app.totalBytesPerSecond >= PowerBudget.baselineMinimumComparableBytesPerSecond {
            let key = Self.normalizedName(app.displayName)
            let existing = recordsByAppName[key]
            recordsByAppName[key] = TrafficBaselineRecord(
                displayName: existing?.displayName ?? app.displayName,
                sampleCount: (existing?.sampleCount ?? 0) + 1,
                averageBytesInPerSecond: nextAverage(
                    currentAverage: existing?.averageBytesInPerSecond ?? 0,
                    sampleCount: existing?.sampleCount ?? 0,
                    nextValue: app.bytesInPerSecond
                ),
                averageBytesOutPerSecond: nextAverage(
                    currentAverage: existing?.averageBytesOutPerSecond ?? 0,
                    sampleCount: existing?.sampleCount ?? 0,
                    nextValue: app.bytesOutPerSecond
                ),
                peakBytesInPerSecond: max(existing?.peakBytesInPerSecond ?? 0, app.bytesInPerSecond),
                peakBytesOutPerSecond: max(existing?.peakBytesOutPerSecond ?? 0, app.bytesOutPerSecond),
                firstSeenAt: existing?.firstSeenAt ?? date,
                lastSeenAt: date
            )
        }

        prune(now: date)
        return self != before
    }

    public mutating func prune(now: Date = Date()) {
        let oldestAllowed = now.addingTimeInterval(-maximumAgeSeconds)
        recordsByAppName = recordsByAppName.filter { _, record in
            record.lastSeenAt >= oldestAllowed
        }

        if recordsByAppName.count > maximumApps {
            let kept = recordsByAppName.values
                .sorted {
                    if $0.lastSeenAt == $1.lastSeenAt {
                        return $0.sampleCount > $1.sampleCount
                    }
                    return $0.lastSeenAt > $1.lastSeenAt
                }
                .prefix(maximumApps)

            recordsByAppName = Dictionary(uniqueKeysWithValues: kept.map { (Self.normalizedName($0.displayName), $0) })
        }
    }

    public func assess(apps: [AppTraffic], at date: Date = Date()) -> TrafficBaselineAssessment {
        let activeApps = apps
            .filter { $0.totalBytesPerSecond >= PowerBudget.baselineMinimumComparableBytesPerSecond }
            .sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }

        guard maximumSampleCount >= PowerBudget.minimumBaselineSamplesForComparison else {
            return TrafficBaselineAssessment(
                state: .learning,
                summary: "Learning local baseline (\(maximumSampleCount)/\(PowerBudget.minimumBaselineSamplesForComparison) samples).",
                findings: []
            )
        }

        var findings: [TrafficBaselineFinding] = []
        for app in activeApps {
            let key = Self.normalizedName(app.displayName)
            guard let record = recordsByAppName[key] else {
                findings.append(.newActiveApp(appName: app.displayName, currentBytesPerSecond: app.totalBytesPerSecond))
                continue
            }

            guard record.sampleCount >= PowerBudget.minimumBaselineSamplesForComparison else {
                continue
            }

            let usualTotal = max(record.averageBytesInPerSecond + record.averageBytesOutPerSecond, 1)
            let multiplier = Double(app.totalBytesPerSecond) / Double(usualTotal)
            if multiplier >= PowerBudget.baselineUnusualTrafficMultiplier {
                findings.append(.aboveUsual(
                    appName: app.displayName,
                    multiplier: multiplier,
                    currentBytesPerSecond: app.totalBytesPerSecond,
                    usualBytesPerSecond: usualTotal
                ))
            }
        }

        let limitedFindings = Array(findings.prefix(3))
        let summary: String
        if let first = limitedFindings.first {
            summary = first.summary
        } else {
            summary = "Current app traffic is close to learned local baseline."
        }

        return TrafficBaselineAssessment(
            state: limitedFindings.isEmpty ? .normal : .changed,
            summary: summary,
            findings: limitedFindings
        )
    }

    public static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func nextAverage(currentAverage: Int, sampleCount: Int, nextValue: Int) -> Int {
        guard sampleCount > 0 else {
            return nextValue
        }

        let total = Int64(currentAverage) * Int64(sampleCount) + Int64(nextValue)
        return Int(total / Int64(sampleCount + 1))
    }
}

public struct TrafficBaselineRecord: Codable, Equatable, Sendable {
    public let displayName: String
    public let sampleCount: Int
    public let averageBytesInPerSecond: Int
    public let averageBytesOutPerSecond: Int
    public let peakBytesInPerSecond: Int
    public let peakBytesOutPerSecond: Int
    public let firstSeenAt: Date
    public let lastSeenAt: Date

    public init(
        displayName: String,
        sampleCount: Int,
        averageBytesInPerSecond: Int,
        averageBytesOutPerSecond: Int,
        peakBytesInPerSecond: Int,
        peakBytesOutPerSecond: Int,
        firstSeenAt: Date,
        lastSeenAt: Date
    ) {
        self.displayName = displayName
        self.sampleCount = sampleCount
        self.averageBytesInPerSecond = averageBytesInPerSecond
        self.averageBytesOutPerSecond = averageBytesOutPerSecond
        self.peakBytesInPerSecond = peakBytesInPerSecond
        self.peakBytesOutPerSecond = peakBytesOutPerSecond
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct TrafficBaselineAssessment: Equatable, Sendable {
    public let state: TrafficBaselineState
    public let summary: String
    public let findings: [TrafficBaselineFinding]

    public init(state: TrafficBaselineState, summary: String, findings: [TrafficBaselineFinding]) {
        self.state = state
        self.summary = summary
        self.findings = findings
    }
}

public enum TrafficBaselineState: Equatable, Sendable {
    case learning
    case normal
    case changed
}

public enum TrafficBaselineFinding: Equatable, Sendable {
    case aboveUsual(appName: String, multiplier: Double, currentBytesPerSecond: Int, usualBytesPerSecond: Int)
    case newActiveApp(appName: String, currentBytesPerSecond: Int)

    public var summary: String {
        switch self {
        case let .aboveUsual(appName, multiplier, currentBytesPerSecond, usualBytesPerSecond):
            return "\(appName) is \(TrafficFormatting.baselineMultiplier(multiplier)) above usual (\(TrafficFormatting.bitsPerSecond(currentBytesPerSecond)) now vs \(TrafficFormatting.bitsPerSecond(usualBytesPerSecond)) learned)."
        case let .newActiveApp(appName, currentBytesPerSecond):
            return "\(appName) is newly active at \(TrafficFormatting.bitsPerSecond(currentBytesPerSecond))."
        }
    }
}
