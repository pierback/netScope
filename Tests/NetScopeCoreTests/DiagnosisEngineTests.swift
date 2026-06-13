import Testing
@testable import NetScopeCore

@Test func flagsDominantUploadApp() {
    let apps = [
        AppTraffic(
            displayName: "iCloud Photos",
            pid: 42,
            bytesInPerSecond: 10_000,
            bytesOutPerSecond: 2_000_000,
            retransmitsPerSecond: 0
        ),
        AppTraffic(
            displayName: "Safari",
            pid: 43,
            bytesInPerSecond: 200_000,
            bytesOutPerSecond: 100_000,
            retransmitsPerSecond: 0
        ),
    ]

    let diagnosis = DiagnosisEngine().diagnose(evidence: DiagnosisEvidence(apps: apps))

    #expect(diagnosis.title == "iCloud Photos is likely causing upload pressure")
    #expect(diagnosis.kind == .appUploadPressure(appName: "iCloud Photos"))
    #expect(diagnosis.confidence == .high)
}

@Test func flagsDominantDownloadApp() {
    let apps = [
        AppTraffic(
            displayName: "Chrome",
            pid: 50,
            bytesInPerSecond: 5_000_000,
            bytesOutPerSecond: 20_000,
            retransmitsPerSecond: 0
        ),
        AppTraffic(
            displayName: "Mail",
            pid: 51,
            bytesInPerSecond: 200_000,
            bytesOutPerSecond: 20_000,
            retransmitsPerSecond: 0
        ),
    ]

    let diagnosis = DiagnosisEngine().diagnose(evidence: DiagnosisEvidence(apps: apps))

    #expect(diagnosis.title == "Chrome is using most download bandwidth")
    #expect(diagnosis.kind == .appDownloadPressure(appName: "Chrome"))
    #expect(diagnosis.confidence == .high)
}

@Test func reportsBadNetworkWhenNoAppDominates() {
    let apps = [
        AppTraffic(
            displayName: "Safari",
            pid: 43,
            bytesInPerSecond: 50_000,
            bytesOutPerSecond: 25_000,
            retransmitsPerSecond: 0
        ),
        AppTraffic(
            displayName: "Slack",
            pid: 44,
            bytesInPerSecond: 45_000,
            bytesOutPerSecond: 20_000,
            retransmitsPerSecond: 0
        ),
    ]
    let ping = PingResult(
        host: "1.1.1.1",
        transmitted: 3,
        received: 3,
        packetLossPercent: 0,
        averageMilliseconds: 230
    )

    let diagnosis = DiagnosisEngine().diagnose(evidence: DiagnosisEvidence(apps: apps, ping: ping))

    #expect(diagnosis.title == "Network path looks slow or unstable; no single app stands out")
    #expect(diagnosis.kind == .internetPath)
    #expect(diagnosis.confidence == .medium)
}

@Test func flagsActiveProxyWhenLatencyIsBad() {
    let apps = [
        AppTraffic(
            displayName: "com.zscaler.zsc",
            pid: 1249,
            bytesInPerSecond: 300_000,
            bytesOutPerSecond: 80_000,
            retransmitsPerSecond: 0
        ),
        AppTraffic(
            displayName: "Safari",
            pid: 43,
            bytesInPerSecond: 250_000,
            bytesOutPerSecond: 50_000,
            retransmitsPerSecond: 0
        ),
    ]
    let ping = PingResult(
        host: "1.1.1.1",
        transmitted: 2,
        received: 2,
        packetLossPercent: 0,
        averageMilliseconds: 220
    )

    let diagnosis = DiagnosisEngine().diagnose(evidence: DiagnosisEvidence(apps: apps, ping: ping))

    #expect(diagnosis.title == "com.zscaler.zsc may be adding network latency")
    #expect(diagnosis.kind == .infrastructurePathApp(appName: "com.zscaler.zsc"))
    #expect(diagnosis.confidence == .medium)
}

@Test func concreteProxyUploadPressureWinsOverInfrastructureLatencyLabel() {
    let apps = [
        AppTraffic(
            displayName: "com.zscaler.zsc",
            pid: 1249,
            bytesInPerSecond: 10_000,
            bytesOutPerSecond: 2_000_000,
            retransmitsPerSecond: 0
        ),
        AppTraffic(
            displayName: "Safari",
            pid: 43,
            bytesInPerSecond: 20_000,
            bytesOutPerSecond: 20_000,
            retransmitsPerSecond: 0
        ),
    ]
    let ping = PingResult(
        host: "1.1.1.1",
        transmitted: 2,
        received: 2,
        packetLossPercent: 0,
        averageMilliseconds: 220
    )

    let diagnosis = DiagnosisEngine().diagnose(evidence: DiagnosisEvidence(apps: apps, ping: ping))

    #expect(diagnosis.kind == .appUploadPressure(appName: "com.zscaler.zsc"))
    #expect(diagnosis.confidence == .high)
}

@Test func diagnosesDNSPathScopeFromFullEvidence() {
    let apps = [
        AppTraffic(
            displayName: "Safari",
            pid: 43,
            bytesInPerSecond: 50_000,
            bytesOutPerSecond: 10_000,
            retransmitsPerSecond: 0
        )
    ]
    let publicPing = PingResult(
        host: "1.1.1.1",
        transmitted: 2,
        received: 2,
        packetLossPercent: 0,
        averageMilliseconds: 20
    )
    let pathCheck = NetworkPathCheck(
        gatewayAddress: "192.168.1.1",
        gatewayPing: publicPing,
        publicPing: publicPing,
        dnsLookup: DNSLookupResult(domain: "apple.com", succeeded: false, elapsedMilliseconds: 500),
        scope: .dns,
        summary: "Ping path looks reachable, but DNS lookup is slow or failing."
    )

    let diagnosis = DiagnosisEngine().diagnose(evidence: DiagnosisEvidence(apps: apps, pathCheck: pathCheck))

    #expect(diagnosis.kind == .dns)
    #expect(diagnosis.title == "DNS lookup looks slow or failing")
    #expect(diagnosis.confidence == .medium)
}

@Test func highConfidenceUploadPressureWinsOverMediumPathIssue() {
    let apps = [
        AppTraffic(
            displayName: "Dropbox",
            pid: 55,
            bytesInPerSecond: 20_000,
            bytesOutPerSecond: 20_000_000,
            retransmitsPerSecond: 0
        )
    ]
    let badPublicPing = PingResult(
        host: "1.1.1.1",
        transmitted: 2,
        received: 2,
        packetLossPercent: 0,
        averageMilliseconds: 240
    )
    let pathCheck = NetworkPathCheck(
        gatewayAddress: "192.168.1.1",
        gatewayPing: PingResult(host: "192.168.1.1", transmitted: 2, received: 2, packetLossPercent: 0, averageMilliseconds: 5),
        publicPing: badPublicPing,
        dnsLookup: DNSLookupResult(domain: "apple.com", succeeded: true, elapsedMilliseconds: 20),
        scope: .internetPath,
        summary: "Wi-Fi gateway responds, but the public internet path looks slow or lossy."
    )

    let diagnosis = DiagnosisEngine().diagnose(
        evidence: DiagnosisEvidence(apps: apps, appEvidenceSource: .freshlySampled, pathCheck: pathCheck)
    )

    #expect(diagnosis.kind == .appUploadPressure(appName: "Dropbox"))
    #expect(diagnosis.confidence == .high)
}

@Test func weakWiFiDoesNotMaskHighConfidenceUploadPressure() {
    let apps = [
        AppTraffic(
            displayName: "Dropbox",
            pid: 55,
            bytesInPerSecond: 20_000,
            bytesOutPerSecond: 20_000_000,
            retransmitsPerSecond: 0
        )
    ]
    let wifi = WiFiHealth(
        interfaceName: "en0",
        ssid: nil,
        rssi: -82,
        noise: -90,
        transmitRateMbps: 400,
        channel: 11,
        summary: "Wi-Fi signal is weak."
    )

    let diagnosis = DiagnosisEngine().diagnose(
        evidence: DiagnosisEvidence(apps: apps, appEvidenceSource: .freshlySampled, wifi: wifi)
    )

    #expect(diagnosis.kind == .appUploadPressure(appName: "Dropbox"))
    #expect(diagnosis.confidence == .high)
}
