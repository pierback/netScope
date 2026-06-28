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
                concern: nil,
                summary: "Wi-Fi interface is unavailable."
            )
        }

        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        let rate = interface.transmitRate()
        let channel = interface.wlanChannel()?.channelNumber
        let ssid = privacyMode == .includeNetworkName ? interface.ssid() : nil
        let concern = Self.concern(rssi: rssi, noise: noise, transmitRateMbps: rate, ssid: ssid)
        let summary = Self.summary(for: concern)

        return WiFiHealth(
            interfaceName: interface.interfaceName,
            ssid: ssid,
            rssi: rssi == 0 ? nil : rssi,
            noise: noise == 0 ? nil : noise,
            transmitRateMbps: rate <= 0 ? nil : rate,
            channel: channel == 0 ? nil : channel,
            concern: concern,
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
            concern: nil,
            summary: "Wi-Fi health is unavailable on this system."
        )
        #endif
    }

    public static func concern(rssi: Int, noise: Int, transmitRateMbps: Double, ssid: String?) -> WiFiConcern? {
        if rssi == 0 && noise == 0 && ssid == nil {
            return .detailsUnavailable
        }

        if rssi <= -80 {
            return .weakSignal
        }

        if noise != 0 && rssi - noise < 25 {
            return .lowSignalToNoiseMargin
        }

        if transmitRateMbps > 0 && transmitRateMbps < 100 {
            return .lowLinkRate
        }

        return nil
    }

    public static func summary(for concern: WiFiConcern?) -> String {
        switch concern {
        case .detailsUnavailable:
            return "Wi-Fi details unavailable; Location Services permission may be required."
        case .weakSignal:
            return "Wi-Fi signal is weak."
        case .lowSignalToNoiseMargin:
            return "Wi-Fi signal-to-noise margin is low."
        case .lowLinkRate:
            return "Wi-Fi link rate is low."
        case .none:
            return "Wi-Fi link looks usable."
        }
    }
}
