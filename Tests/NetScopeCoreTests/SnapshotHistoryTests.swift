import Foundation
import Testing
@testable import NetScopeCore

@Test func keepsOnlyBoundedRecentSnapshots() {
    let now = Date(timeIntervalSince1970: 10_000)
    var history = SnapshotHistory(maximumAgeSeconds: 120, maximumSamples: 3)

    for index in 0..<5 {
        history.record(snapshot(at: now.addingTimeInterval(Double(index * 30)), appName: "App\(index)"))
    }

    #expect(history.recentSnapshots.count == 3)
    #expect(history.recentSnapshots.first?.diagnosis.topApps.first?.displayName == "App2")
}

@Test func reportsCorrelationWhenSameAppRepeatedlyDominates() {
    let now = Date(timeIntervalSince1970: 20_000)
    var history = SnapshotHistory(maximumAgeSeconds: 1_800, maximumSamples: 30)

    history.record(snapshot(at: now, appName: "Dropbox"))
    history.record(snapshot(at: now.addingTimeInterval(60), appName: "Slack", confidence: .low))
    history.record(snapshot(at: now.addingTimeInterval(120), appName: "Dropbox"))

    let correlation = history.correlation()

    #expect(correlation?.appName == "Dropbox")
    #expect(correlation?.sampleCount == 2)
}

@Test func pathCheckWithReusedAppsDoesNotCreateNewAppCorrelation() {
    let now = Date(timeIntervalSince1970: 25_000)
    let observationID = UUID()
    var history = SnapshotHistory(maximumAgeSeconds: 1_800, maximumSamples: 30)

    history.record(snapshot(at: now, appName: "Dropbox", appObservationID: observationID))
    history.record(snapshot(
        at: now.addingTimeInterval(30),
        appName: "Dropbox",
        kind: .pathCheck,
        appEvidenceSource: .reusedFromSnapshot(now),
        appObservationID: observationID
    ))

    #expect(history.correlation() == nil)
}

@Test func returnsBoundedTrafficTrendFromRecentSnapshots() {
    let now = Date(timeIntervalSince1970: 30_000)
    var history = SnapshotHistory(maximumAgeSeconds: 1_800, maximumSamples: 30)

    for index in 0..<4 {
        history.record(snapshot(
            at: now.addingTimeInterval(Double(index * 60)),
            appName: "App\(index)",
            bytesInPerSecond: index * 10_000,
            bytesOutPerSecond: index * 20_000
        ))
    }

    let trend = history.trafficTrend(limit: 3)

    #expect(trend.count == 3)
    #expect(trend.map(\.bytesInPerSecond) == [10_000, 20_000, 30_000])
    #expect(trend.map(\.bytesOutPerSecond) == [20_000, 40_000, 60_000])
}

private func snapshot(
    at date: Date,
    appName: String,
    confidence: Confidence = .medium,
    bytesInPerSecond: Int = 1_000_000,
    bytesOutPerSecond: Int = 1_000_000,
    kind: SnapshotKind = .rollingAppCounters,
    appEvidenceSource: AppEvidenceSource = .freshlySampled,
    appObservationID: UUID = UUID()
) -> NetworkSnapshot {
    let app = AppTraffic(
        displayName: appName,
        pid: 100,
        bytesInPerSecond: bytesInPerSecond,
        bytesOutPerSecond: bytesOutPerSecond,
        retransmitsPerSecond: 0
    )
    let diagnosis = Diagnosis(
        kind: .dominantApp(appName: appName),
        title: "\(appName) is the dominant network app",
        confidence: confidence,
        reasons: [],
        topApps: [app]
    )

    return NetworkSnapshot(
        capturedAt: date,
        kind: kind,
        diagnosis: diagnosis,
        apps: [app],
        appEvidenceCapturedAt: date,
        appEvidenceSource: appEvidenceSource,
        appObservationID: appObservationID,
        ping: nil
    )
}
