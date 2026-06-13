import Foundation

public struct ClassifiedAppTraffic: Equatable, Sendable {
    public let app: AppTraffic
    public let role: AppTrafficRole

    public init(app: AppTraffic, role: AppTrafficRole) {
        self.app = app
        self.role = role
    }
}

public enum AppTrafficRole: String, Equatable, Sendable {
    case userApp
    case infrastructure
    case systemService
    case unknown

    public var label: String {
        switch self {
        case .userApp:
            return "User App"
        case .infrastructure:
            return "Infrastructure"
        case .systemService:
            return "System"
        case .unknown:
            return "Unknown"
        }
    }
}

public struct AppTrafficGroups: Equatable, Sendable {
    public let userApps: [ClassifiedAppTraffic]
    public let infrastructure: [ClassifiedAppTraffic]
    public let systemServices: [ClassifiedAppTraffic]
    public let unknown: [ClassifiedAppTraffic]

    public init(
        userApps: [ClassifiedAppTraffic],
        infrastructure: [ClassifiedAppTraffic],
        systemServices: [ClassifiedAppTraffic],
        unknown: [ClassifiedAppTraffic]
    ) {
        self.userApps = userApps
        self.infrastructure = infrastructure
        self.systemServices = systemServices
        self.unknown = unknown
    }
}

public struct AppTrafficClassifier: Sendable {
    public init() {}

    public func classify(_ apps: [AppTraffic]) -> [ClassifiedAppTraffic] {
        apps
            .sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }
            .map { ClassifiedAppTraffic(app: $0, role: role(for: $0.displayName)) }
    }

    public func groups(for apps: [AppTraffic], limitPerGroup: Int = 4) -> AppTrafficGroups {
        let classified = classify(apps)
        return AppTrafficGroups(
            userApps: limited(classified, role: .userApp, limit: limitPerGroup),
            infrastructure: limited(classified, role: .infrastructure, limit: limitPerGroup),
            systemServices: limited(classified, role: .systemService, limit: limitPerGroup),
            unknown: limited(classified, role: .unknown, limit: limitPerGroup)
        )
    }

    public func role(for displayName: String) -> AppTrafficRole {
        let name = normalized(displayName)

        if infrastructureMarkers.contains(where: { name.contains($0) }) {
            return .infrastructure
        }

        if systemServiceNames.contains(name) || systemServiceMarkers.contains(where: { name.contains($0) }) {
            return .systemService
        }

        if name.hasPrefix("com.") {
            return .unknown
        }

        return .userApp
    }

    private func limited(_ classified: [ClassifiedAppTraffic], role: AppTrafficRole, limit: Int) -> [ClassifiedAppTraffic] {
        Array(classified.filter { $0.role == role }.prefix(limit))
    }

    private func normalized(_ displayName: String) -> String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private let infrastructureMarkers = [
        "zscaler",
        "crowdstrike",
        "falcon",
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
        "little snitch",
        "littlesnitch",
        "jamf",
    ]

    private let systemServiceNames = [
        "mDNSResponder".lowercased(),
        "apsd",
        "cloudd",
        "sharingd",
        "rapportd",
        "trustd",
        "nsurlsessiond",
        "softwareupdated",
        "syspolicyd",
        "kernel_task",
    ]

    private let systemServiceMarkers = [
        "com.apple.",
        "systemuiserver",
        "networkserviceproxy",
        "neagent",
    ]
}
