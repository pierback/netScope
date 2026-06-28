import Testing
@testable import NetScopeCore

@Test func trafficFormattingUsesSharedLongAndCompactUnits() {
    #expect(TrafficFormatting.bitsPerSecond(125_000, style: .long) == "1 Mbps")
    #expect(TrafficFormatting.bitsPerSecond(125_000, style: .compact) == "1M")
    #expect(TrafficFormatting.bitsPerSecond(12_500, style: .long) == "100 Kbps")
    #expect(TrafficFormatting.bitsPerSecond(12_500, style: .compact) == "100K")
    #expect(TrafficFormatting.bitsPerSecond(100, style: .long) == "800 bps")
    #expect(TrafficFormatting.bitsPerSecond(100, style: .compact) == "800")
}

@Test func trafficFormattingSharesDecimalAndPercentRules() {
    #expect(TrafficFormatting.decimal(9.25) == "9.2")
    #expect(TrafficFormatting.decimal(12.25) == "12")
    #expect(TrafficFormatting.percent(0.552) == "55%")
    #expect(TrafficFormatting.baselineMultiplier(4.04) == "4.0x")
}

@Test func appTrafficTotalsSumAcrossApps() {
    let apps = [
        AppTraffic(displayName: "Safari", pid: 1, bytesInPerSecond: 40_000, bytesOutPerSecond: 10_000, retransmitsPerSecond: 0),
        AppTraffic(displayName: "Mail", pid: 2, bytesInPerSecond: 20_000, bytesOutPerSecond: 5_000, retransmitsPerSecond: 0),
    ]

    #expect(apps.totalIncomingBytesPerSecond() == 60_000)
    #expect(apps.totalOutgoingBytesPerSecond() == 15_000)
    #expect(TrafficFormatting.appTraffic(apps[0], style: .compact) == "320K dn / 80K up")
}
