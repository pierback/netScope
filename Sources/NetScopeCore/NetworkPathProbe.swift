import Foundation

public struct NetworkPathProbe: Sendable {
    private let runner: CommandRunning
    private let pingProbe: PingProbe
    private let publicHost: String
    private let dnsDomain: String
    private let maximumPathCheckSeconds: TimeInterval

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        publicHost: String = "1.1.1.1",
        dnsDomain: String = "apple.com",
        maximumPathCheckSeconds: TimeInterval = PowerBudget.maximumPathCheckSeconds
    ) {
        self.runner = runner
        self.pingProbe = PingProbe(runner: runner)
        self.publicHost = publicHost
        self.dnsDomain = dnsDomain
        self.maximumPathCheckSeconds = maximumPathCheckSeconds
    }

    public func probe() -> NetworkPathCheck {
        let deadline = Date().addingTimeInterval(maximumPathCheckSeconds)
        let gateway = defaultGateway(deadline: deadline)
        let gatewayPing = gateway.flatMap { gatewayAddress -> PingResult? in
            guard let timeout = remainingSeconds(until: deadline, cap: PowerBudget.pingCommandSeconds) else {
                return nil
            }

            return try? pingProbe.probe(host: gatewayAddress, timeoutSeconds: timeout)
        }
        let publicPing: PingResult?
        if let timeout = remainingSeconds(until: deadline, cap: PowerBudget.pingCommandSeconds) {
            publicPing = try? pingProbe.probe(host: publicHost, timeoutSeconds: timeout)
        } else {
            publicPing = nil
        }
        let dnsLookup = lookupDNS(domain: dnsDomain, deadline: deadline)
        let scope = classify(gatewayAddress: gateway, gatewayPing: gatewayPing, publicPing: publicPing, dnsLookup: dnsLookup)

        return NetworkPathCheck(
            gatewayAddress: gateway,
            gatewayPing: gatewayPing,
            publicPing: publicPing,
            dnsLookup: dnsLookup,
            scope: scope,
            summary: summary(for: scope, gatewayAddress: gateway, gatewayPing: gatewayPing, publicPing: publicPing, dnsLookup: dnsLookup)
        )
    }

    private func defaultGateway(deadline: Date) -> String? {
        guard let timeout = remainingSeconds(until: deadline, cap: PowerBudget.routeCommandSeconds),
              let result = try? runner.run(
                  "/sbin/route",
                  arguments: ["-n", "get", "default"],
                  timeoutSeconds: timeout
              ),
              result.exitCode == 0 else {
            return nil
        }

        return Self.parseGateway(from: result.stdout)
    }

    private func lookupDNS(domain: String, deadline: Date) -> DNSLookupResult? {
        guard let timeout = remainingSeconds(until: deadline, cap: PowerBudget.dnsCommandSeconds) else {
            return nil
        }

        let start = Date()
        let result = try? runner.run(
            "/usr/bin/dig",
            arguments: ["+time=2", "+tries=1", "+short", domain],
            timeoutSeconds: timeout
        )
        let elapsed = Date().timeIntervalSince(start) * 1_000
        let succeeded = result?.exitCode == 0 && !(result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return DNSLookupResult(
            domain: domain,
            succeeded: succeeded,
            elapsedMilliseconds: elapsed
        )
    }

    private func classify(
        gatewayAddress: String?,
        gatewayPing: PingResult?,
        publicPing: PingResult?,
        dnsLookup: DNSLookupResult?
    ) -> NetworkPathScope {
        let gatewayIsBad = gatewayPing.map(pingLooksBad) == true
        let gatewayIsGood = gatewayPing.map { !pingLooksBad($0) } == true
        let publicIsBad = publicPing.map(pingLooksBad) == true
        let publicIsGood = publicPing.map { !pingLooksBad($0) } == true
        let dnsIsBad = dnsLookup.map(dnsLooksBad) == true

        if gatewayAddress != nil && gatewayIsBad {
            return .localNetwork
        }

        if gatewayIsGood && publicIsBad {
            return .internetPath
        }

        if publicIsGood && dnsIsBad {
            return .dns
        }

        if publicIsGood && dnsLookup?.succeeded == true {
            return .reachable
        }

        return .unknown
    }

    private func summary(
        for scope: NetworkPathScope,
        gatewayAddress: String?,
        gatewayPing: PingResult?,
        publicPing: PingResult?,
        dnsLookup: DNSLookupResult?
    ) -> String {
        switch scope {
        case .localNetwork:
            return "Local gateway looks slow or unreachable."
        case .internetPath:
            return "Wi-Fi gateway responds, but the public internet path looks slow or lossy."
        case .dns:
            return "Ping path looks reachable, but DNS lookup is slow or failing."
        case .reachable:
            if gatewayAddress == nil || gatewayPing == nil {
                return "Public ping and DNS probes succeeded, but the local gateway could not be checked."
            }

            return "Tiny gateway, public ping, and DNS probes succeeded; this does not rule out intermittent or service-specific issues."
        case .unknown:
            return "Network path check could not isolate the fault."
        }
    }

    private func pingLooksBad(_ ping: PingResult) -> Bool {
        if ping.packetLossPercent >= 5 {
            return true
        }

        if let average = ping.averageMilliseconds, average >= 150 {
            return true
        }

        return false
    }

    private func dnsLooksBad(_ result: DNSLookupResult?) -> Bool {
        guard let result else {
            return true
        }

        if !result.succeeded {
            return true
        }

        if let elapsed = result.elapsedMilliseconds, elapsed >= 1_000 {
            return true
        }

        return false
    }

    private func remainingSeconds(until deadline: Date, cap: TimeInterval) -> TimeInterval? {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            return nil
        }

        return min(cap, remaining)
    }

    public static func parseGateway(from output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, parts[0] == "gateway", !parts[1].isEmpty else {
                continue
            }

            return parts[1]
        }

        return nil
    }
}
