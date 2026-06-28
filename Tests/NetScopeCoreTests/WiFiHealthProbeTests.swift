import Testing
@testable import NetScopeCore

@Test func wifiSummaryReportsUnavailableWhenDetailsAreWithheld() {
    let concern = WiFiHealthProbe.concern(rssi: 0, noise: 0, transmitRateMbps: 0, ssid: nil)
    let summary = WiFiHealthProbe.summary(for: concern)

    #expect(concern == .detailsUnavailable)
    #expect(summary.contains("unavailable"))
}

@Test func wifiSummaryReportsWeakSignal() {
    let concern = WiFiHealthProbe.concern(rssi: -82, noise: -95, transmitRateMbps: 400, ssid: "Office")
    let summary = WiFiHealthProbe.summary(for: concern)

    #expect(concern == .weakSignal)
    #expect(summary.contains("weak"))
}

@Test func wifiSummaryReportsLowSignalToNoiseMargin() {
    let concern = WiFiHealthProbe.concern(rssi: -65, noise: -84, transmitRateMbps: 400, ssid: "Office")
    let summary = WiFiHealthProbe.summary(for: concern)

    #expect(concern == .lowSignalToNoiseMargin)
    #expect(summary.contains("signal-to-noise"))
}

@Test func wifiSummaryReportsLowLinkRate() {
    let concern = WiFiHealthProbe.concern(rssi: -60, noise: -95, transmitRateMbps: 72, ssid: "Office")
    let summary = WiFiHealthProbe.summary(for: concern)

    #expect(concern == .lowLinkRate)
    #expect(summary.contains("link rate"))
}

@Test func wifiSummaryReportsUsableLinkWhenNoConcernDetected() {
    let concern = WiFiHealthProbe.concern(rssi: -50, noise: -95, transmitRateMbps: 400, ssid: "Office")
    let summary = WiFiHealthProbe.summary(for: concern)

    #expect(concern == nil)
    #expect(summary.contains("usable"))
}

@Test func wifiConcernTreatsExactWeakSignalThresholdAsWeak() {
    let concern = WiFiHealthProbe.concern(rssi: -80, noise: -95, transmitRateMbps: 400, ssid: "Office")

    #expect(concern == .weakSignal)
}

@Test func wifiConcernKeepsExactSignalToNoiseBoundaryUsable() {
    let concern = WiFiHealthProbe.concern(rssi: -60, noise: -85, transmitRateMbps: 400, ssid: "Office")

    #expect(concern == nil)
}

@Test func wifiConcernKeepsExactLinkRateBoundaryUsable() {
    let concern = WiFiHealthProbe.concern(rssi: -60, noise: -95, transmitRateMbps: 100, ssid: "Office")

    #expect(concern == nil)
}
