import Foundation

public struct SnapshotService: Sendable {
    private let sampler: NettopSampler
    private let pingProbe: PingProbe
    private let pathProbe: NetworkPathProbe
    private let wifiProbe: WiFiHealthProbe
    private let diagnosisEngine: DiagnosisEngine

    public init(
        sampler: NettopSampler = NettopSampler(),
        pingProbe: PingProbe = PingProbe(),
        pathProbe: NetworkPathProbe = NetworkPathProbe(),
        wifiProbe: WiFiHealthProbe = WiFiHealthProbe(),
        diagnosisEngine: DiagnosisEngine = DiagnosisEngine()
    ) {
        self.sampler = sampler
        self.pingProbe = pingProbe
        self.pathProbe = pathProbe
        self.wifiProbe = wifiProbe
        self.diagnosisEngine = diagnosisEngine
    }

    public func captureFullCheck(at date: Date = Date()) throws -> NetworkSnapshot {
        let apps = try sampler.sample()
        let ping = try? pingProbe.probe()
        let wifi = wifiProbe.probe(privacyMode: .linkMetricsOnly)
        let diagnosis = diagnosisEngine.diagnose(evidence: DiagnosisEvidence(apps: apps, ping: ping, wifi: wifi))
        let observationID = UUID()

        return NetworkSnapshot(
            capturedAt: date,
            kind: .interactive,
            diagnosis: diagnosis,
            apps: apps,
            appEvidenceCapturedAt: date,
            appEvidenceSource: .freshlySampled,
            appObservationID: observationID,
            ping: ping,
            wifi: wifi
        )
    }

    public func captureInteractiveObservation(at date: Date = Date()) throws -> NetworkSnapshot {
        let apps = try sampler.sample()
        let wifi = wifiProbe.probe(privacyMode: .linkMetricsOnly)
        let diagnosis = diagnosisEngine.diagnose(evidence: DiagnosisEvidence(apps: apps, wifi: wifi))
        let observationID = UUID()

        return NetworkSnapshot(
            capturedAt: date,
            kind: .interactive,
            diagnosis: diagnosis,
            apps: apps,
            appEvidenceCapturedAt: date,
            appEvidenceSource: .freshlySampled,
            appObservationID: observationID,
            ping: nil,
            wifi: wifi
        )
    }

    public func captureRollingAppCounters(at date: Date = Date()) throws -> NetworkSnapshot {
        let apps = try sampler.sample()
        let diagnosis = diagnosisEngine.diagnose(evidence: DiagnosisEvidence(apps: apps))
        let observationID = UUID()

        return NetworkSnapshot(
            capturedAt: date,
            kind: .rollingAppCounters,
            diagnosis: diagnosis,
            apps: apps,
            appEvidenceCapturedAt: date,
            appEvidenceSource: .freshlySampled,
            appObservationID: observationID,
            ping: nil
        )
    }

    public func checkNetworkPath(currentAppSnapshot: NetworkSnapshot?, at date: Date = Date()) -> NetworkSnapshot {
        let appEvidence = Self.appEvidence(from: currentAppSnapshot, at: date)
        let pathCheck = pathProbe.probe()
        let ping = pathCheck.publicPing
        let wifi = wifiProbe.probe(privacyMode: .linkMetricsOnly)
        let diagnosis = diagnosisEngine.diagnose(
            evidence: DiagnosisEvidence(
                apps: appEvidence.apps,
                appEvidenceSource: appEvidence.source,
                ping: ping,
                pathCheck: pathCheck,
                wifi: wifi
            )
        )

        return NetworkSnapshot(
            capturedAt: date,
            kind: .pathCheck,
            diagnosis: diagnosis,
            apps: appEvidence.apps,
            appEvidenceCapturedAt: appEvidence.capturedAt,
            appEvidenceSource: appEvidence.source,
            appObservationID: appEvidence.observationID,
            ping: ping,
            pathCheck: pathCheck,
            wifi: wifi
        )
    }

    private static func appEvidence(from snapshot: NetworkSnapshot?, at date: Date) -> (
        apps: [AppTraffic],
        capturedAt: Date?,
        source: AppEvidenceSource,
        observationID: UUID?
    ) {
        guard let snapshot,
              snapshot.appEvidenceSource.isFreshlySampled,
              let appEvidenceCapturedAt = snapshot.appEvidenceCapturedAt,
              let appObservationID = snapshot.appObservationID,
              date.timeIntervalSince(appEvidenceCapturedAt) <= PowerBudget.maximumReusableAppEvidenceAgeSeconds else {
            return ([], nil, .unavailable, nil)
        }

        return (
            snapshot.apps,
            appEvidenceCapturedAt,
            .reusedFromSnapshot(appEvidenceCapturedAt),
            appObservationID
        )
    }
}
