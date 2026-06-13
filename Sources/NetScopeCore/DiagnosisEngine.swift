import Foundation

public struct DiagnosisEngine: Sendable {
    public init() {}

    public func diagnose(evidence: DiagnosisEvidence) -> Diagnosis {
        let apps = evidence.apps
        let ping = evidence.pathCheck?.publicPing ?? evidence.ping
        let topApps = apps
            .sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }
            .prefix(5)
            .map { $0 }

        let totalIn = apps.reduce(0) { $0 + $1.bytesInPerSecond }
        let totalOut = apps.reduce(0) { $0 + $1.bytesOutPerSecond }
        let total = totalIn + totalOut
        let pingReason = ping.map(describePing)
        let pathReason = evidence.pathCheck?.summary
        let wifiReason = evidence.wifi?.summary
        let activeProxyApp = topApps.first(where: isProxyOrVPNApp)
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
                confidence: pingLooksBad(ping) ? .medium : .low,
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
        let trafficReason = "Observed \(formatBitsPerSecond(total)) total TCP app traffic across sampled apps."
        let topReason = "\(top.displayName) is using \(formatAppTraffic(top))."

        if canUseAppPressure, top.bytesOutPerSecond >= 512 * 1024 && uploadShare >= 0.55 {
            return Diagnosis(
                kind: .appUploadPressure(appName: top.displayName),
                title: "\(top.displayName) is likely causing upload pressure",
                confidence: uploadShare >= 0.75 ? .high : .medium,
                reasons: compact([
                    topReason,
                    "\(top.displayName) accounts for \(formatPercent(uploadShare)) of current upload traffic.",
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
                    "\(top.displayName) accounts for \(formatPercent(downloadShare)) of current download traffic.",
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
                    "\(top.displayName) accounts for \(formatPercent(topShare)) of all sampled app traffic.",
                    trafficReason,
                    pingReason,
                    pathReason,
                    wifiReason,
                ]),
                topApps: topApps
            )
        }

        if canUseAppPressure, pingLooksBad(ping), let activeProxyApp {
            return Diagnosis(
                kind: .infrastructurePathApp(appName: activeProxyApp.displayName),
                title: "\(activeProxyApp.displayName) may be adding network latency",
                confidence: .medium,
                reasons: compact([
                    "\(activeProxyApp.displayName) looks like a VPN, proxy, or network security app and is active in the sample.",
                    pingReason,
                    pathReason,
                    wifiReason,
                    "\(top.displayName) is the top current network process at \(formatAppTraffic(top)).",
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

        if pingLooksBad(ping) {
            return Diagnosis(
                kind: .internetPath,
                title: "Network path looks slow or unstable; no single app stands out",
                confidence: .medium,
                reasons: compact([
                    topReason,
                    "The top app only accounts for \(formatPercent(topShare)) of sampled traffic.",
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

        let summary = wifi.summary
        guard summary == "Wi-Fi signal is weak."
            || summary == "Wi-Fi signal-to-noise margin is low."
            || summary == "Wi-Fi link rate is low." else {
            return nil
        }

        return Diagnosis(
            kind: .wifi,
            title: summary,
            confidence: .medium,
            reasons: [summary],
            topApps: topApps
        )
    }

    private func describePing(_ ping: PingResult) -> String {
        let average = ping.averageMilliseconds.map { "\(formatNumber($0)) ms avg" } ?? "no average latency"
        return "Ping to \(ping.host): \(average), \(formatNumber(ping.packetLossPercent))% packet loss."
    }

    private func describeDNS(_ result: DNSLookupResult?) -> String? {
        guard let result else {
            return "DNS lookup did not return a result."
        }

        if let elapsed = result.elapsedMilliseconds {
            return "DNS lookup for \(result.domain): \(result.succeeded ? "succeeded" : "failed") in \(formatNumber(elapsed)) ms."
        }

        return "DNS lookup for \(result.domain): \(result.succeeded ? "succeeded" : "failed")."
    }

    private func pingLooksBad(_ ping: PingResult?) -> Bool {
        guard let ping else {
            return false
        }

        if ping.packetLossPercent >= 5 {
            return true
        }

        if let average = ping.averageMilliseconds, average >= 150 {
            return true
        }

        return false
    }

    private func isProxyOrVPNApp(_ app: AppTraffic) -> Bool {
        let name = app.displayName.lowercased()
        let markers = [
            "zscaler",
            "vpn",
            "tailscale",
            "wireguard",
            "proton",
            "nordvpn",
            "expressvpn",
            "openvpn",
            "globalprotect",
            "anyconnect",
            "cloudflare warp",
            "warp",
        ]

        return markers.contains { name.contains($0) }
    }

    private func compact(_ values: [String?]) -> [String] {
        values.compactMap { $0 }
    }
}

public func formatAppTraffic(_ app: AppTraffic) -> String {
    "\(formatBitsPerSecond(app.bytesInPerSecond)) down / \(formatBitsPerSecond(app.bytesOutPerSecond)) up"
}

public func formatBitsPerSecond(_ bytesPerSecond: Int) -> String {
    let bits = Double(bytesPerSecond) * 8
    if bits >= 1_000_000 {
        return "\(formatNumber(bits / 1_000_000)) Mbps"
    }

    if bits >= 1_000 {
        return "\(formatNumber(bits / 1_000)) Kbps"
    }

    return "\(Int(bits)) bps"
}

public func formatPercent(_ fraction: Double) -> String {
    "\(formatNumber(fraction * 100))%"
}

private func formatNumber(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = value < 10 ? 1 : 0
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}
