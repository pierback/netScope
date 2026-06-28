import Foundation

public struct AppTraffic: Equatable, Sendable {
    public let displayName: String
    public let pid: Int?
    public let bytesInPerSecond: Int
    public let bytesOutPerSecond: Int
    public let retransmitsPerSecond: Int

    public init(
        displayName: String,
        pid: Int?,
        bytesInPerSecond: Int,
        bytesOutPerSecond: Int,
        retransmitsPerSecond: Int
    ) {
        self.displayName = displayName
        self.pid = pid
        self.bytesInPerSecond = bytesInPerSecond
        self.bytesOutPerSecond = bytesOutPerSecond
        self.retransmitsPerSecond = retransmitsPerSecond
    }

    public var totalBytesPerSecond: Int {
        bytesInPerSecond + bytesOutPerSecond
    }
}

public struct PingResult: Equatable, Sendable {
    public let host: String
    public let transmitted: Int
    public let received: Int
    public let packetLossPercent: Double
    public let averageMilliseconds: Double?

    public init(
        host: String,
        transmitted: Int,
        received: Int,
        packetLossPercent: Double,
        averageMilliseconds: Double?
    ) {
        self.host = host
        self.transmitted = transmitted
        self.received = received
        self.packetLossPercent = packetLossPercent
        self.averageMilliseconds = averageMilliseconds
    }
}

public struct DNSLookupResult: Equatable, Sendable {
    public let domain: String
    public let succeeded: Bool
    public let elapsedMilliseconds: Double?

    public init(domain: String, succeeded: Bool, elapsedMilliseconds: Double?) {
        self.domain = domain
        self.succeeded = succeeded
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

public struct NetworkPathCheck: Equatable, Sendable {
    public let gatewayAddress: String?
    public let gatewayPing: PingResult?
    public let publicPing: PingResult?
    public let dnsLookup: DNSLookupResult?
    public let scope: NetworkPathScope
    public let summary: String

    public init(
        gatewayAddress: String?,
        gatewayPing: PingResult?,
        publicPing: PingResult?,
        dnsLookup: DNSLookupResult?,
        scope: NetworkPathScope,
        summary: String
    ) {
        self.gatewayAddress = gatewayAddress
        self.gatewayPing = gatewayPing
        self.publicPing = publicPing
        self.dnsLookup = dnsLookup
        self.scope = scope
        self.summary = summary
    }
}

public enum NetworkPathScope: String, Equatable, Sendable {
    case localNetwork
    case internetPath
    case dns
    case reachable
    case unknown
}

public enum WiFiConcern: Equatable, Sendable {
    case detailsUnavailable
    case weakSignal
    case lowSignalToNoiseMargin
    case lowLinkRate
}

public struct WiFiHealth: Equatable, Sendable {
    public let interfaceName: String?
    public let ssid: String?
    public let rssi: Int?
    public let noise: Int?
    public let transmitRateMbps: Double?
    public let channel: Int?
    public let concern: WiFiConcern?
    public let summary: String

    public init(
        interfaceName: String?,
        ssid: String?,
        rssi: Int?,
        noise: Int?,
        transmitRateMbps: Double?,
        channel: Int?,
        concern: WiFiConcern?,
        summary: String
    ) {
        self.interfaceName = interfaceName
        self.ssid = ssid
        self.rssi = rssi
        self.noise = noise
        self.transmitRateMbps = transmitRateMbps
        self.channel = channel
        self.concern = concern
        self.summary = summary
    }
}

public enum Confidence: String, Equatable, Sendable {
    case high
    case medium
    case low
}

public enum DiagnosisKind: Equatable, Sendable {
    case appUploadPressure(appName: String)
    case appDownloadPressure(appName: String)
    case dominantApp(appName: String)
    case infrastructurePathApp(appName: String)
    case localNetwork
    case internetPath
    case dns
    case wifi
    case noObservedPressure
    case inconclusive

    public var appName: String? {
        switch self {
        case let .appUploadPressure(appName),
             let .appDownloadPressure(appName),
             let .dominantApp(appName),
             let .infrastructurePathApp(appName):
            return appName
        case .localNetwork, .internetPath, .dns, .wifi, .noObservedPressure, .inconclusive:
            return nil
        }
    }

    public var canUseAppCorrelation: Bool {
        switch self {
        case .appUploadPressure, .appDownloadPressure, .dominantApp:
            return true
        case .infrastructurePathApp, .localNetwork, .internetPath, .dns, .wifi, .noObservedPressure, .inconclusive:
            return false
        }
    }
}

public struct Diagnosis: Equatable, Sendable {
    public let kind: DiagnosisKind
    public let title: String
    public let confidence: Confidence
    public let reasons: [String]
    public let topApps: [AppTraffic]

    public init(
        kind: DiagnosisKind,
        title: String,
        confidence: Confidence,
        reasons: [String],
        topApps: [AppTraffic]
    ) {
        self.kind = kind
        self.title = title
        self.confidence = confidence
        self.reasons = reasons
        self.topApps = topApps
    }
}

public struct DiagnosisEvidence: Equatable, Sendable {
    public let apps: [AppTraffic]
    public let appEvidenceSource: AppEvidenceSource
    public let ping: PingResult?
    public let pathCheck: NetworkPathCheck?
    public let wifi: WiFiHealth?

    public init(
        apps: [AppTraffic],
        appEvidenceSource: AppEvidenceSource = .freshlySampled,
        ping: PingResult? = nil,
        pathCheck: NetworkPathCheck? = nil,
        wifi: WiFiHealth? = nil
    ) {
        self.apps = apps
        self.appEvidenceSource = appEvidenceSource
        self.ping = ping
        self.pathCheck = pathCheck
        self.wifi = wifi
    }
}

public enum AppEvidenceSource: Equatable, Sendable {
    case freshlySampled
    case reusedFromSnapshot(Date)
    case unavailable

    public var isFreshlySampled: Bool {
        self == .freshlySampled
    }
}

public struct NetworkSnapshot: Equatable, Sendable {
    public let capturedAt: Date
    public let kind: SnapshotKind
    public let diagnosis: Diagnosis
    public let apps: [AppTraffic]
    public let appEvidenceCapturedAt: Date?
    public let appEvidenceSource: AppEvidenceSource
    public let appObservationID: UUID?
    public let ping: PingResult?
    public let pathCheck: NetworkPathCheck?
    public let wifi: WiFiHealth?

    public init(
        capturedAt: Date,
        kind: SnapshotKind,
        diagnosis: Diagnosis,
        apps: [AppTraffic],
        appEvidenceCapturedAt: Date?,
        appEvidenceSource: AppEvidenceSource,
        appObservationID: UUID?,
        ping: PingResult?,
        pathCheck: NetworkPathCheck? = nil,
        wifi: WiFiHealth? = nil
    ) {
        self.capturedAt = capturedAt
        self.kind = kind
        self.diagnosis = diagnosis
        self.apps = apps
        self.appEvidenceCapturedAt = appEvidenceCapturedAt
        self.appEvidenceSource = appEvidenceSource
        self.appObservationID = appObservationID
        self.ping = ping
        self.pathCheck = pathCheck
        self.wifi = wifi
    }
}

public enum SnapshotKind: String, Equatable, Sendable {
    case interactive
    case pathCheck
    case rollingAppCounters
}

public enum NetworkStatus: String, Equatable, Sendable {
    case normal
    case possiblePressure
    case likelyIssue
}

public struct RecentCorrelation: Equatable, Sendable {
    public let appName: String
    public let sampleCount: Int
    public let reason: String

    public init(appName: String, sampleCount: Int, reason: String) {
        self.appName = appName
        self.sampleCount = sampleCount
        self.reason = reason
    }
}

public struct TrafficTrendPoint: Equatable, Sendable {
    public let capturedAt: Date
    public let bytesInPerSecond: Int
    public let bytesOutPerSecond: Int

    public init(capturedAt: Date, bytesInPerSecond: Int, bytesOutPerSecond: Int) {
        self.capturedAt = capturedAt
        self.bytesInPerSecond = bytesInPerSecond
        self.bytesOutPerSecond = bytesOutPerSecond
    }

    public var totalBytesPerSecond: Int {
        bytesInPerSecond + bytesOutPerSecond
    }
}
