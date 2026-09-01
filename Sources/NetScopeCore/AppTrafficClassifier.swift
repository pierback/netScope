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

        if isNetworkPathName(name) || Self.infrastructureServiceMarkers.contains(where: { name.contains($0) }) {
            return .infrastructure
        }

        if Self.systemServiceNames.contains(name) || Self.systemServiceMarkers.contains(where: { name.contains($0) }) {
            return .systemService
        }

        if name.hasPrefix("com.") {
            return .unknown
        }

        return .userApp
    }

    public func isNetworkPathApp(_ displayName: String) -> Bool {
        isNetworkPathName(normalized(displayName))
    }

    private func limited(_ classified: [ClassifiedAppTraffic], role: AppTrafficRole, limit: Int) -> [ClassifiedAppTraffic] {
        Array(classified.filter { $0.role == role }.prefix(limit))
    }

    private func normalized(_ displayName: String) -> String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isNetworkPathName(_ name: String) -> Bool {
        Self.networkPathMarkers.contains { name.contains($0) }
    }

    private static let networkPathMarkers = [
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
        "little snitch",
        "littlesnitch",
    ]

    private static let infrastructureServiceMarkers = [
        "crowdstrike",
        "falcon",
        "jamf",
    ]

    private static let systemServiceNames = [
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

    private static let systemServiceMarkers = [
        "com.apple.",
        "systemuiserver",
        "networkserviceproxy",
        "neagent",
    ]
}
