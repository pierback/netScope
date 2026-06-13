import Foundation

#if canImport(CoreWLAN)
import CoreWLAN
#endif

public enum WiFiProbePrivacyMode: Equatable, Sendable {
    case linkMetricsOnly
    case includeNetworkName
}

public struct WiFiHealthProbe: Sendable {
    public init() {}

    public func probe(privacyMode: WiFiProbePrivacyMode = .includeNetworkName) -> WiFiHealth {
        #if canImport(CoreWLAN)
        guard let interface = CWWiFiClient.shared().interface() else {
            return WiFiHealth(
                interfaceName: nil,
                ssid: nil,
                rssi: nil,
                noise: nil,
                transmitRateMbps: nil,
                channel: nil,
                summary: "Wi-Fi interface is unavailable."
            )
        }

        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        let rate = interface.transmitRate()
        let channel = interface.wlanChannel()?.channelNumber
        let ssid = privacyMode == .includeNetworkName ? interface.ssid() : nil
        let summary = Self.summary(rssi: rssi, noise: noise, transmitRateMbps: rate, ssid: ssid)

        return WiFiHealth(
            interfaceName: interface.interfaceName,
            ssid: ssid,
            rssi: rssi == 0 ? nil : rssi,
            noise: noise == 0 ? nil : noise,
            transmitRateMbps: rate <= 0 ? nil : rate,
            channel: channel == 0 ? nil : channel,
            summary: summary
        )
        #else
        return WiFiHealth(
            interfaceName: nil,
            ssid: nil,
            rssi: nil,
            noise: nil,
            transmitRateMbps: nil,
            channel: nil,
            summary: "Wi-Fi health is unavailable on this system."
        )
        #endif
    }

    public static func summary(rssi: Int, noise: Int, transmitRateMbps: Double, ssid: String?) -> String {
        if rssi == 0 && noise == 0 && ssid == nil {
            return "Wi-Fi details unavailable; Location Services permission may be required."
        }

        if rssi <= -80 {
            return "Wi-Fi signal is weak."
        }

        if noise != 0 && rssi - noise < 25 {
            return "Wi-Fi signal-to-noise margin is low."
        }

        if transmitRateMbps > 0 && transmitRateMbps < 100 {
            return "Wi-Fi link rate is low."
        }

        return "Wi-Fi link looks usable."
    }
}
