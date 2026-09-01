import Foundation

public struct StatusPolicy: Sendable {
    public init() {}

    public func evaluate(
        latestAppObservation: NetworkSnapshot?,
        latestPathCheck: NetworkSnapshot?,
        correlation: RecentCorrelation?,
        now: Date = Date()
    ) -> (status: NetworkStatus, effectiveConfidence: Confidence) {
        guard let diagnosis = selectedDiagnosis(
            latestAppObservation: latestAppObservation,
            latestPathCheck: latestPathCheck,
            correlation: correlation,
            now: now
        ) else {
            return (.normal, .low)
        }

        let confidence = effectiveConfidence(for: diagnosis, correlation: correlation)
        return (status(for: confidence), confidence)
    }

    public func effectiveConfidence(for diagnosis: Diagnosis, correlation: RecentCorrelation?) -> Confidence {
        guard let correlation,
              diagnosis.kind.canUseAppCorrelation,
              diagnosis.kind.appName == correlation.appName else {
            return diagnosis.confidence
        }

        switch diagnosis.confidence {
        case .high:
            return .high
        case .medium, .low:
            return .high
        }
    }

    private func selectedDiagnosis(
        latestAppObservation: NetworkSnapshot?,
        latestPathCheck: NetworkSnapshot?,
        correlation: RecentCorrelation?,
        now: Date
    ) -> Diagnosis? {
        if let appDiagnosis = latestAppObservation?.diagnosis,
           effectiveConfidence(for: appDiagnosis, correlation: correlation) == .high {
            return appDiagnosis
        }

        if let pathDiagnosis = activePathDiagnosis(latestPathCheck, now: now) {
            return pathDiagnosis
        }

        return latestAppObservation?.diagnosis
    }

    private func activePathDiagnosis(_ snapshot: NetworkSnapshot?, now: Date) -> Diagnosis? {
        guard let snapshot,
              snapshot.kind == .pathCheck,
              snapshot.capturedAt >= now.addingTimeInterval(-PowerBudget.pathFindingStatusTTLSeconds),
              snapshot.diagnosis.confidence != .low else {
            return nil
        }

        return snapshot.diagnosis
    }

    private func status(for confidence: Confidence) -> NetworkStatus {
        switch confidence {
        case .high:
            return .likelyIssue
        case .medium:
            return .possiblePressure
        case .low:
            return .normal
        }
    }
}
