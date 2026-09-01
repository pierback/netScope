import Foundation

public struct DiagnosisEngine: Sendable {
    public init() {}

    public func diagnose(evidence: DiagnosisEvidence) -> Diagnosis {
        let apps = evidence.apps
        let ping = evidence.pathCheck?.publicPing ?? evidence.ping
        let topApps = Array(apps
            .sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }
            .prefix(5))

        let totalIn = apps.totalIncomingBytesPerSecond()
        let totalOut = apps.totalOutgoingBytesPerSecond()
        let total = totalIn + totalOut
        let pingReason = ping.map(describePing)
        let pathReason = evidence.pathCheck?.summary
        let wifiReason = evidence.wifi?.summary
        let appClassifier = AppTrafficClassifier()
        let activeNetworkPathApp = topApps.first {
            appClassifier.isNetworkPathApp($0.displayName)
        }
        let canUseAppPressure = evidence.appEvidenceSource.isFreshlySampled

        guard let top = topApps.first else {
            if let pathDiagnosis = diagnosePath(
                pathCheck: evidence.pathCheck,
                topApps: topApps,
                topReason: nil,
                trafficReason: "No fresh TCP app counters were available for this check."
            ) {
                return pathDiagnosis
            }

            if let wifiDiagnosis = diagnoseWiFi(wifi: evidence.wifi, topApps: topApps) {
                return wifiDiagnosis
            }

            return Diagnosis(
                kind: .noObservedPressure,
                title: "No active TCP app traffic observed",
                confidence: ping?.indicatesPathProblem == true ? .medium : .low,
                reasons: compact([
                    "nettop did not report meaningful TCP per-process traffic in this short sample.",
                    pingReason,
                    pathReason,
                    wifiReason,
                ]),
                topApps: []
            )
        }

        let topShare = total == 0 ? 0 : Double(top.totalBytesPerSecond) / Double(total)
        let uploadShare = totalOut == 0 ? 0 : Double(top.bytesOutPerSecond) / Double(totalOut)
        let downloadShare = totalIn == 0 ? 0 : Double(top.bytesInPerSecond) / Double(totalIn)
        let trafficReason = "Observed \(TrafficFormatting.bitsPerSecond(total)) total TCP app traffic across sampled apps."
        let topReason = "\(top.displayName) is using \(TrafficFormatting.appTraffic(top))."

        if canUseAppPressure, top.bytesOutPerSecond >= 512 * 1024 && uploadShare >= 0.55 {
            return Diagnosis(
                kind: .appUploadPressure(appName: top.displayName),
                title: "\(top.displayName) is likely causing upload pressure",
                confidence: uploadShare >= 0.75 ? .high : .medium,
                reasons: compact([
                    topReason,
                    "\(top.displayName) accounts for \(TrafficFormatting.percent(uploadShare)) of current upload traffic.",
                    trafficReason,
                    pingReason,
                    pathReason,
                    wifiReason,
                ]),
                topApps: topApps
            )
        }

        if canUseAppPressure, top.bytesInPerSecond >= 1_000_000 && downloadShare >= 0.65 {
            return Diagnosis(
                kind: .appDownloadPressure(appName: top.displayName),
                title: "\(top.displayName) is using most download bandwidth",
                confidence: downloadShare >= 0.80 ? .high : .medium,
                reasons: compact([
                    topReason,
                    "\(top.displayName) accounts for \(TrafficFormatting.percent(downloadShare)) of current download traffic.",
                    trafficReason,
                    pingReason,
                    pathReason,
                    wifiReason,
                ]),
                topApps: topApps
            )
        }

        if canUseAppPressure, top.totalBytesPerSecond >= 1_000_000 && topShare >= 0.70 {
            return Diagnosis(
                kind: .dominantApp(appName: top.displayName),
                title: "\(top.displayName) is the dominant network app",
                confidence: .medium,
                reasons: compact([
                    topReason,
                    "\(top.displayName) accounts for \(TrafficFormatting.percent(topShare)) of all sampled app traffic.",
                    trafficReason,
                    pingReason,
                    pathReason,
                    wifiReason,
                ]),
                topApps: topApps
            )
        }

        if canUseAppPressure, ping?.indicatesPathProblem == true, let activeNetworkPathApp {
            return Diagnosis(
                kind: .infrastructurePathApp(appName: activeNetworkPathApp.displayName),
                title: "\(activeNetworkPathApp.displayName) may be adding network latency",
                confidence: .medium,
                reasons: compact([
                    "\(activeNetworkPathApp.displayName) looks like a VPN, proxy, or network security app and is active in the sample.",
                    pingReason,
                    pathReason,
                    wifiReason,
                    "\(top.displayName) is the top current network process at \(TrafficFormatting.appTraffic(top)).",
                    trafficReason,
                ]),
                topApps: topApps
            )
        }

        if let pathDiagnosis = diagnosePath(
            pathCheck: evidence.pathCheck,
            topApps: topApps,
            topReason: topReason,
            trafficReason: trafficReason
        ) {
            return pathDiagnosis
        }

        if let wifiDiagnosis = diagnoseWiFi(wifi: evidence.wifi, topApps: topApps) {
            return wifiDiagnosis
        }

        if ping?.indicatesPathProblem == true {
            return Diagnosis(
                kind: .internetPath,
                title: "Network path looks slow or unstable; no single app stands out",
                confidence: .medium,
                reasons: compact([
                    topReason,
                    "The top app only accounts for \(TrafficFormatting.percent(topShare)) of sampled traffic.",
                    pingReason,
                    pathReason,
                    wifiReason,
                    trafficReason,
                ]),
                topApps: topApps
            )
        }

        return Diagnosis(
            kind: .noObservedPressure,
            title: "No TCP app traffic crossed pressure thresholds",
            confidence: .low,
            reasons: compact([
                topReason,
                "No app crossed the current TCP upload/download pressure thresholds in this short sample.",
                pingReason,
                pathReason,
                wifiReason,
                trafficReason,
            ]),
            topApps: topApps
        )
    }

    private func diagnosePath(
        pathCheck: NetworkPathCheck?,
        topApps: [AppTraffic],
        topReason: String?,
        trafficReason: String
    ) -> Diagnosis? {
        guard let pathCheck else {
            return nil
        }

        switch pathCheck.scope {
        case .localNetwork:
            return Diagnosis(
                kind: .localNetwork,
                title: "Local network path looks slow or unreachable",
                confidence: .medium,
                reasons: compact([
                    pathCheck.summary,
                    pathCheck.gatewayPing.map(describePing),
                    topReason,
                    trafficReason,
                ]),
                topApps: topApps
            )
        case .internetPath:
            return Diagnosis(
                kind: .internetPath,
                title: "Internet path looks slow beyond the gateway",
                confidence: .medium,
                reasons: compact([
                    pathCheck.summary,
                    pathCheck.gatewayPing.map(describePing),
                    pathCheck.publicPing.map(describePing),
                    topReason,
                    trafficReason,
                ]),
                topApps: topApps
            )
        case .dns:
            return Diagnosis(
                kind: .dns,
                title: "DNS lookup looks slow or failing",
                confidence: .medium,
                reasons: compact([
                    pathCheck.summary,
                    pathCheck.publicPing.map(describePing),
                    describeDNS(pathCheck.dnsLookup),
                    topReason,
                    trafficReason,
                ]),
                topApps: topApps
            )
        case .reachable, .unknown:
            return nil
        }
    }

    private func diagnoseWiFi(wifi: WiFiHealth?, topApps: [AppTraffic]) -> Diagnosis? {
        guard let wifi else {
            return nil
        }

        switch wifi.concern {
        case .weakSignal, .lowSignalToNoiseMargin, .lowLinkRate:
            break
        case .detailsUnavailable, .none:
            return nil
        }

        return Diagnosis(
            kind: .wifi,
            title: wifi.summary,
            confidence: .medium,
            reasons: [wifi.summary],
            topApps: topApps
        )
    }

    private func describePing(_ ping: PingResult) -> String {
        let average = ping.averageMilliseconds.map { "\(TrafficFormatting.decimal($0)) ms avg" } ?? "no average latency"
        return "Ping to \(ping.host): \(average), \(TrafficFormatting.decimal(ping.packetLossPercent))% packet loss."
    }

    private func describeDNS(_ result: DNSLookupResult?) -> String? {
        guard let result else {
            return "DNS lookup did not return a result."
        }

        if let elapsed = result.elapsedMilliseconds {
            return "DNS lookup for \(result.domain): \(result.succeeded ? "succeeded" : "failed") in \(TrafficFormatting.decimal(elapsed)) ms."
        }

        return "DNS lookup for \(result.domain): \(result.succeeded ? "succeeded" : "failed")."
    }

    private func compact(_ values: [String?]) -> [String] {
        values.compactMap { $0 }
    }
}
