import Foundation
import Testing
@testable import NetScopeCore

@Test func recentCorrelationDoesNotRaiseNoPressureDiagnosis() {
    let diagnosis = Diagnosis(
        kind: .noObservedPressure,
        title: "No TCP app traffic crossed pressure thresholds",
        confidence: .low,
        reasons: [],
        topApps: []
    )
    let correlation = RecentCorrelation(
        appName: "Dropbox",
        sampleCount: 2,
        reason: "Dropbox appeared as the top pressure app in 2 recent snapshots."
    )

    let policy = StatusPolicy()

    #expect(policy.effectiveConfidence(for: diagnosis, correlation: correlation) == .low)
}

@Test func recentCorrelationRaisesMatchingAppPressureDiagnosis() {
    let app = AppTraffic(
        displayName: "Dropbox",
        pid: 99,
        bytesInPerSecond: 100_000,
        bytesOutPerSecond: 900_000,
        retransmitsPerSecond: 0
    )
    let diagnosis = Diagnosis(
        kind: .appUploadPressure(appName: "Dropbox"),
        title: "Dropbox is likely causing upload pressure",
        confidence: .medium,
        reasons: [],
        topApps: [app]
    )
    let correlation = RecentCorrelation(
        appName: "Dropbox",
        sampleCount: 2,
        reason: "Dropbox appeared as the top pressure app in 2 recent snapshots."
    )

    let policy = StatusPolicy()

    #expect(policy.effectiveConfidence(for: diagnosis, correlation: correlation) == .high)
}

@Test func recentCorrelationDoesNotRaiseDifferentCurrentApp() {
    let diagnosis = Diagnosis(
        kind: .appUploadPressure(appName: "Dropbox"),
        title: "Dropbox is likely causing upload pressure",
        confidence: .medium,
        reasons: [],
        topApps: []
    )
    let correlation = RecentCorrelation(
        appName: "iCloud",
        sampleCount: 2,
        reason: "iCloud appeared as the top pressure app in 2 recent snapshots."
    )

    let policy = StatusPolicy()

    #expect(policy.effectiveConfidence(for: diagnosis, correlation: correlation) == .medium)
}

@Test func rollingSampleDoesNotClearRecentDNSPathStatus() {
    let now = Date(timeIntervalSince1970: 50_000)
    let appSnapshot = snapshot(
        at: now.addingTimeInterval(60),
        kind: .rollingAppCounters,
        diagnosis: Diagnosis(
            kind: .noObservedPressure,
            title: "No pressure",
            confidence: .low,
            reasons: [],
            topApps: []
        )
    )
    let pathSnapshot = snapshot(
        at: now,
        kind: .pathCheck,
        diagnosis: Diagnosis(
            kind: .dns,
            title: "DNS lookup looks slow or failing",
            confidence: .medium,
            reasons: [],
            topApps: []
        )
    )

    let policy = StatusPolicy()

    #expect(policy.evaluate(
        latestAppObservation: appSnapshot,
        latestPathCheck: pathSnapshot,
        correlation: nil,
        now: now.addingTimeInterval(60)
    ).status == .possiblePressure)
}

@Test func rollingSampleDoesNotClearRecentInternetPathStatus() {
    let now = Date(timeIntervalSince1970: 60_000)
    let appSnapshot = snapshot(
        at: now.addingTimeInterval(60),
        kind: .rollingAppCounters,
        diagnosis: Diagnosis(
            kind: .noObservedPressure,
            title: "No pressure",
            confidence: .low,
            reasons: [],
            topApps: []
        )
    )
    let pathSnapshot = snapshot(
        at: now,
        kind: .pathCheck,
        diagnosis: Diagnosis(
            kind: .internetPath,
            title: "Internet path looks slow beyond the gateway",
            confidence: .medium,
            reasons: [],
            topApps: []
        )
    )

    let policy = StatusPolicy()

    #expect(policy.evaluate(
        latestAppObservation: appSnapshot,
        latestPathCheck: pathSnapshot,
        correlation: nil,
        now: now.addingTimeInterval(60)
    ).status == .possiblePressure)
}

@Test func expiredPathCheckDoesNotDriveStatusWhenNoAppObservationExists() {
    let now = Date(timeIntervalSince1970: 70_000)
    let expiredPathSnapshot = snapshot(
        at: now.addingTimeInterval(-(PowerBudget.pathFindingStatusTTLSeconds + 1)),
        kind: .pathCheck,
        diagnosis: Diagnosis(
            kind: .dns,
            title: "DNS lookup looks slow or failing",
            confidence: .medium,
            reasons: [],
            topApps: []
        )
    )

    let policy = StatusPolicy()

    #expect(policy.evaluate(
        latestAppObservation: nil,
        latestPathCheck: expiredPathSnapshot,
        correlation: nil,
        now: now
    ).status == .normal)
}

@Test func expiredPathCheckFallsBackToLatestAppObservation() {
    let now = Date(timeIntervalSince1970: 80_000)
    let appSnapshot = snapshot(
        at: now.addingTimeInterval(-60),
        kind: .rollingAppCounters,
        diagnosis: Diagnosis(
            kind: .noObservedPressure,
            title: "No pressure",
            confidence: .low,
            reasons: [],
            topApps: []
        )
    )
    let expiredPathSnapshot = snapshot(
        at: now.addingTimeInterval(-(PowerBudget.pathFindingStatusTTLSeconds + 1)),
        kind: .pathCheck,
        diagnosis: Diagnosis(
            kind: .internetPath,
            title: "Internet path looks slow beyond the gateway",
            confidence: .medium,
            reasons: [],
            topApps: []
        )
    )

    let policy = StatusPolicy()

    #expect(policy.evaluate(
        latestAppObservation: appSnapshot,
        latestPathCheck: expiredPathSnapshot,
        correlation: nil,
        now: now
    ).status == .normal)
}

private func snapshot(at date: Date, kind: SnapshotKind, diagnosis: Diagnosis) -> NetworkSnapshot {
    NetworkSnapshot(
        capturedAt: date,
        kind: kind,
        diagnosis: diagnosis,
        apps: diagnosis.topApps,
        appEvidenceCapturedAt: kind == .pathCheck ? nil : date,
        appEvidenceSource: kind == .pathCheck ? .unavailable : .freshlySampled,
        appObservationID: kind == .pathCheck ? nil : UUID(),
        ping: nil
    )
}
