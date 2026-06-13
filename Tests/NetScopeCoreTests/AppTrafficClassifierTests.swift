import Testing
@testable import NetScopeCore

@Test func separatesUserAppsFromInfrastructureAndSystemServices() {
    let classifier = AppTrafficClassifier()
    let apps = [
        app("codex", total: 900_000),
        app("com.zscaler.zsc", total: 1_200_000),
        app("com.crowdstrike.falcon.Agent", total: 800_000),
        app("mDNSResponder", total: 300_000),
        app("com.vendor.background", total: 200_000),
    ]

    let groups = classifier.groups(for: apps)

    #expect(groups.userApps.map(\.app.displayName) == ["codex"])
    #expect(groups.infrastructure.map(\.app.displayName) == ["com.zscaler.zsc", "com.crowdstrike.falcon.Agent"])
    #expect(groups.systemServices.map(\.app.displayName) == ["mDNSResponder"])
    #expect(groups.unknown.map(\.app.displayName) == ["com.vendor.background"])
}

@Test func keepsGroupsSortedByTraffic() {
    let classifier = AppTrafficClassifier()
    let apps = [
        app("Safari", total: 10_000),
        app("codex", total: 50_000),
        app("Slack", total: 30_000),
    ]

    let groups = classifier.groups(for: apps)

    #expect(groups.userApps.map(\.app.displayName) == ["codex", "Slack", "Safari"])
}

private func app(_ name: String, total: Int) -> AppTraffic {
    AppTraffic(
        displayName: name,
        pid: 42,
        bytesInPerSecond: total,
        bytesOutPerSecond: 0,
        retransmitsPerSecond: 0
    )
}
