import Foundation
import Testing
@testable import NetScopeCore

@Test func observationSessionInitialStateReflectsLoadedBaseline() {
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)
    baseline.record(apps: [app("codex", down: 40_000, up: 40_000)], at: Date(timeIntervalSince1970: 1_000))

    let session = ObservationSession(baseline: baseline)

    #expect(session.state.learnedBaselineAppCount == 1)
    #expect(session.state.status == .normal)
    #expect(session.state.effectiveConfidence == .low)
}

@Test func rollingSnapshotUpdatesObservationStateAndBaseline() {
    let now = Date(timeIntervalSince1970: 2_000)
    var session = ObservationSession()
    let snapshot = appSnapshot(at: now, appName: "codex", confidence: .medium)

    let update = session.applyRollingAppCounterSnapshot(snapshot)

    #expect(update.baselineChanged)
    #expect(update.state.snapshot == snapshot)
    #expect(update.state.lastRollingSampleAt == now)
    #expect(update.state.learnedBaselineAppCount == 1)
    #expect(update.state.trafficTrend.count == 1)
    #expect(update.state.status == .possiblePressure)
    #expect(session.latestAppObservationForPathCheck == snapshot)
    #expect(session.baselineForPersistence.learnedAppCount == 1)
}

@Test func repeatedRollingPressureRaisesCorrelationAndEffectiveConfidence() {
    let now = Date(timeIntervalSince1970: 3_000)
    var session = ObservationSession()

    session.applyRollingAppCounterSnapshot(appSnapshot(at: now, appName: "Dropbox", confidence: .medium))
    let update = session.applyRollingAppCounterSnapshot(appSnapshot(at: now.addingTimeInterval(60), appName: "Dropbox", confidence: .medium))

    #expect(update.state.correlation?.appName == "Dropbox")
    #expect(update.state.effectiveConfidence == .high)
    #expect(update.state.status == .likelyIssue)
}

@Test func interactiveObservationReusesBaselineWithoutRecordingRollingSample() {
    let now = Date(timeIntervalSince1970: 3_500)
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)
    baseline.record(apps: [app("codex", down: 40_000, up: 40_000)], at: now.addingTimeInterval(-60))
    var session = ObservationSession(baseline: baseline)

    let update = session.applyInteractiveObservationSnapshot(
        appSnapshot(
            at: now,
            appName: "codex",
            confidence: .low,
            kind: .interactive
        )
    )

    #expect(!update.baselineChanged)
    #expect(update.state.snapshot?.kind == .interactive)
    #expect(update.state.lastRollingSampleAt == nil)
    #expect(update.state.learnedBaselineAppCount == 1)
    #expect(session.latestAppObservationForPathCheck?.kind == .interactive)
    #expect(session.baselineForPersistence.learnedAppCount == 1)
}

@Test func pathCheckDoesNotOverwriteLatestAppObservationOrRecordBaseline() {
    let now = Date(timeIntervalSince1970: 4_000)
    var session = ObservationSession()
    let appObservation = appSnapshot(at: now, appName: "codex", confidence: .low)
    session.applyRollingAppCounterSnapshot(appObservation)

    let pathSnapshot = pathSnapshot(
        at: now.addingTimeInterval(30),
        diagnosis: Diagnosis(
            kind: .dns,
            title: "DNS lookup looks slow or failing",
            confidence: .medium,
            reasons: [],
            topApps: []
        )
    )
    let update = session.applyPathCheckSnapshot(pathSnapshot)

    #expect(!update.baselineChanged)
    #expect(update.state.snapshot == pathSnapshot)
    #expect(update.state.lastPathCheck == pathSnapshot)
    #expect(update.state.status == .possiblePressure)
    #expect(session.latestAppObservationForPathCheck == appObservation)
    #expect(session.baselineForPersistence.learnedAppCount == 1)
}

@Test func rollingSnapshotDoesNotClearRecentPathStatus() {
    let now = Date(timeIntervalSince1970: 5_000)
    var session = ObservationSession()
    let pathSnapshot = pathSnapshot(
        at: now,
        diagnosis: Diagnosis(
            kind: .internetPath,
            title: "Internet path looks slow beyond the gateway",
            confidence: .medium,
            reasons: [],
            topApps: []
        )
    )

    session.applyPathCheckSnapshot(pathSnapshot)
    let update = session.applyRollingAppCounterSnapshot(appSnapshot(
        at: now.addingTimeInterval(60),
        appName: "codex",
        confidence: .low,
        diagnosisKind: .noObservedPressure
    ))

    #expect(update.state.lastPathCheck == pathSnapshot)
    #expect(update.state.status == .possiblePressure)
}

@Test func pathCheckWithReusedAppEvidenceDoesNotCreateCorrelation() {
    let now = Date(timeIntervalSince1970: 6_000)
    let observationID = UUID()
    var session = ObservationSession()
    session.applyRollingAppCounterSnapshot(appSnapshot(
        at: now,
        appName: "Dropbox",
        confidence: .medium,
        appObservationID: observationID
    ))

    let reusedPathSnapshot = appSnapshot(
        at: now.addingTimeInterval(30),
        appName: "Dropbox",
        confidence: .medium,
        kind: .pathCheck,
        appEvidenceSource: .reusedFromSnapshot(now),
        appObservationID: observationID
    )
    let update = session.applyPathCheckSnapshot(reusedPathSnapshot)

    #expect(update.state.correlation == nil)
}

@Test func clearBaselineResetsBaselineStateOnly() {
    let now = Date(timeIntervalSince1970: 7_000)
    var session = ObservationSession()
    let snapshot = appSnapshot(at: now, appName: "codex", confidence: .medium)
    session.applyRollingAppCounterSnapshot(snapshot)

    let update = session.clearBaseline()

    #expect(!update.baselineChanged)
    #expect(update.state.snapshot == snapshot)
    #expect(update.state.baselineAssessment == nil)
    #expect(update.state.learnedBaselineAppCount == 0)
    #expect(session.baselineForPersistence.learnedAppCount == 0)
}

private func appSnapshot(
    at date: Date,
    appName: String,
    confidence: Confidence,
    diagnosisKind: DiagnosisKind? = nil,
    kind: SnapshotKind = .rollingAppCounters,
    appEvidenceSource: AppEvidenceSource = .freshlySampled,
    appObservationID: UUID = UUID()
) -> NetworkSnapshot {
    let app = app(appName, down: 120_000, up: 80_000)
    let resolvedKind = diagnosisKind ?? .dominantApp(appName: appName)
    let diagnosis = Diagnosis(
        kind: resolvedKind,
        title: "\(appName) network activity",
        confidence: confidence,
        reasons: [],
        topApps: resolvedKind == .noObservedPressure ? [] : [app]
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

private func pathSnapshot(at date: Date, diagnosis: Diagnosis) -> NetworkSnapshot {
    NetworkSnapshot(
        capturedAt: date,
        kind: .pathCheck,
        diagnosis: diagnosis,
        apps: [],
        appEvidenceCapturedAt: nil,
        appEvidenceSource: .unavailable,
        appObservationID: nil,
        ping: nil
    )
}

private func app(_ name: String, down: Int, up: Int) -> AppTraffic {
    AppTraffic(
        displayName: name,
        pid: 42,
        bytesInPerSecond: down,
        bytesOutPerSecond: up,
        retransmitsPerSecond: 0
    )
}
