import Testing
@testable import NetScopeCore

@Test func wifiSummaryReportsUnavailableWhenDetailsAreWithheld() {
    let summary = WiFiHealthProbe.summary(rssi: 0, noise: 0, transmitRateMbps: 0, ssid: nil)

    #expect(summary.contains("unavailable"))
}

@Test func wifiSummaryReportsWeakSignal() {
    let summary = WiFiHealthProbe.summary(rssi: -82, noise: -95, transmitRateMbps: 400, ssid: "Office")

    #expect(summary == "Wi-Fi signal is weak.")
}

@Test func wifiSummaryReportsLowSignalToNoiseMargin() {
    let summary = WiFiHealthProbe.summary(rssi: -65, noise: -84, transmitRateMbps: 400, ssid: "Office")

    #expect(summary == "Wi-Fi signal-to-noise margin is low.")
}

@Test func wifiSummaryReportsLowLinkRate() {
    let summary = WiFiHealthProbe.summary(rssi: -60, noise: -95, transmitRateMbps: 72, ssid: "Office")

    #expect(summary == "Wi-Fi link rate is low.")
}
