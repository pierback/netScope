import Foundation

public struct SnapshotHistory: Equatable, Sendable {
    private var snapshots: [NetworkSnapshot]
    private let maximumAgeSeconds: TimeInterval
    private let maximumSamples: Int

    public init(
        snapshots: [NetworkSnapshot] = [],
        maximumAgeSeconds: TimeInterval = PowerBudget.maximumHistoryAgeSeconds,
        maximumSamples: Int = PowerBudget.maximumHistorySamples
    ) {
        self.snapshots = snapshots
        self.maximumAgeSeconds = maximumAgeSeconds
        self.maximumSamples = maximumSamples
    }

    public var recentSnapshots: [NetworkSnapshot] {
        snapshots
    }

    public mutating func record(_ snapshot: NetworkSnapshot) {
        snapshots.append(snapshot)
        prune(now: snapshot.capturedAt)
    }

    public mutating func prune(now: Date = Date()) {
        let oldestAllowed = now.addingTimeInterval(-maximumAgeSeconds)
        snapshots.removeAll { $0.capturedAt < oldestAllowed }

        if snapshots.count > maximumSamples {
            snapshots.removeFirst(snapshots.count - maximumSamples)
        }
    }

    public func correlation() -> RecentCorrelation? {
        var countsByApp: [String: Int] = [:]
        var seenObservationIDsByApp: [String: Set<UUID>] = [:]
        for snapshot in snapshots {
            guard snapshot.diagnosis.confidence != .low,
                  snapshot.diagnosis.kind.canUseAppCorrelation,
                  snapshot.appEvidenceSource.isFreshlySampled,
                  let appName = snapshot.diagnosis.kind.appName,
                  let appObservationID = snapshot.appObservationID else {
                continue
            }

            var seenObservationIDs = seenObservationIDsByApp[appName, default: []]
            guard seenObservationIDs.insert(appObservationID).inserted else {
                continue
            }

            seenObservationIDsByApp[appName] = seenObservationIDs
            countsByApp[appName, default: 0] += 1
        }

        guard let strongest = countsByApp.max(by: { $0.value < $1.value }),
              strongest.value >= 2 else {
            return nil
        }

        return RecentCorrelation(
            appName: strongest.key,
            sampleCount: strongest.value,
            reason: "\(strongest.key) appeared as the top pressure app in \(strongest.value) recent snapshots."
        )
    }

    public func trafficTrend(limit: Int = 10) -> [TrafficTrendPoint] {
        snapshots
            .filter { $0.appEvidenceSource.isFreshlySampled }
            .suffix(limit)
            .map { snapshot in
            TrafficTrendPoint(
                capturedAt: snapshot.capturedAt,
                bytesInPerSecond: snapshot.apps.totalIncomingBytesPerSecond(),
                bytesOutPerSecond: snapshot.apps.totalOutgoingBytesPerSecond()
            )
        }
    }
}
