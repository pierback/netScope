import SwiftUI
import NetScopeCore

extension PopoverView {
    func metrics(_ snapshot: NetworkSnapshot, theme: NetScopePopoverTheme) -> some View {
        HStack(alignment: .top, spacing: 0) {
            metricColumn(
                title: "Down",
                value: TrafficFormatting.bitsPerSecond(totalIncomingBytesPerSecond(snapshot)),
                subtitle: appEvidenceSubtitle(snapshot),
                accent: theme.warning,
                theme: theme
            )
            metricDivider(theme: theme)
            metricColumn(
                title: "Up",
                value: TrafficFormatting.bitsPerSecond(totalOutgoingBytesPerSecond(snapshot)),
                subtitle: appEvidenceSubtitle(snapshot),
                accent: theme.success,
                theme: theme
            )
            metricDivider(theme: theme)
            metricColumn(
                title: "Ping",
                value: pingValue(snapshot),
                subtitle: packetLossValue(snapshot),
                accent: theme.neutralAccent,
                theme: theme
            )
        }
        .padding(.vertical, 2)
    }

    func metricColumn(
        title: String,
        value: String,
        subtitle: String,
        accent: Color,
        theme: NetScopePopoverTheme
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(NetScopeFont.semibold(10.5))
                .foregroundStyle(theme.secondaryText)

            Text(value)
                .font(NetScopeFont.bold(15))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                Text(subtitle)
                    .font(NetScopeFont.semibold(9.5))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    func metricDivider(theme: NetScopePopoverTheme) -> some View {
        Rectangle()
            .fill(theme.divider)
            .frame(width: 1, height: 48)
            .padding(.horizontal, 12)
    }

    func pathStatus(_ snapshot: NetworkSnapshot, theme: NetScopePopoverTheme) -> some View {
        let check = model.lastPathCheck?.pathCheck ?? snapshot.pathCheck

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Path Check")
                    .font(NetScopeFont.semibold(13))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text(pathScopeLabel(check?.scope))
                    .font(NetScopeFont.medium(10.5))
                    .foregroundStyle(theme.tertiaryText)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: pathSymbol(check?.scope))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pathColor(check?.scope, theme: theme))
                    .frame(width: 14)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(check?.summary ?? "Click refresh to check gateway, public ping, and DNS.")
                        .font(NetScopeFont.medium(12.25))
                        .foregroundStyle(theme.bodyText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let check {
                        Text(pathDetails(check))
                            .font(NetScopeFont.medium(10.5))
                            .monospacedDigit()
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    func wifiHealth(_ snapshot: NetworkSnapshot, theme: NetScopePopoverTheme) -> some View {
        let wifi = snapshot.wifi

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Wi-Fi")
                    .font(NetScopeFont.semibold(13))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text(wifi?.interfaceName ?? "--")
                    .font(NetScopeFont.medium(10.5))
                    .foregroundStyle(theme.tertiaryText)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.neutralAccent)
                    .frame(width: 14)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(wifi?.summary ?? "Wi-Fi health is not sampled yet.")
                        .font(NetScopeFont.medium(12.25))
                        .foregroundStyle(theme.bodyText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(wifiDetails(wifi))
                        .font(NetScopeFont.medium(10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    func trafficTrend(theme: NetScopePopoverTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trend")
                    .font(NetScopeFont.semibold(13))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text("\(model.trafficTrend.count) samples")
                    .font(NetScopeFont.medium(10.5))
                    .monospacedDigit()
                    .foregroundStyle(theme.tertiaryText)
            }

            TrafficSparkline(points: model.trafficTrend, theme: theme)
                .frame(height: 34)
        }
        .padding(.vertical, 2)
    }

    func baseline(_ snapshot: NetworkSnapshot, theme: NetScopePopoverTheme) -> some View {
        let assessment = model.baselineAssessment
        let message = model.baselineWarning ?? assessment?.summary ?? "Learning local baseline."

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Learned Baseline")
                    .font(NetScopeFont.semibold(13))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text("\(model.learnedBaselineAppCount) apps")
                    .font(NetScopeFont.medium(10.5))
                    .monospacedDigit()
                    .foregroundStyle(theme.tertiaryText)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: baselineSymbol(assessment))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(baselineColor(assessment, theme: theme))
                    .frame(width: 14)
                    .padding(.top, 1)

                Text(message)
                    .font(NetScopeFont.medium(12.25))
                    .foregroundStyle(theme.bodyText)
                    .lineLimit(3)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
    func appEvidenceSubtitle(_ snapshot: NetworkSnapshot) -> String {
        switch snapshot.appEvidenceSource {
        case .freshlySampled:
            return "current"
        case .reusedFromSnapshot:
            return "reused"
        case .unavailable:
            return "unavailable"
        }
    }

    func baselineSymbol(_ assessment: TrafficBaselineAssessment?) -> String {
        if model.baselineWarning != nil {
            return "exclamationmark.triangle"
        }

        switch assessment?.state {
        case .changed:
            return "chart.line.uptrend.xyaxis"
        case .normal:
            return "checkmark.circle"
        case .learning, .none:
            return "clock"
        }
    }

    func baselineColor(_ assessment: TrafficBaselineAssessment?, theme: NetScopePopoverTheme) -> Color {
        if model.baselineWarning != nil {
            return theme.warning
        }

        switch assessment?.state {
        case .changed:
            return theme.warning
        case .normal:
            return theme.success
        case .learning, .none:
            return theme.neutralAccent
        }
    }
    func pathScopeLabel(_ scope: NetworkPathScope?) -> String {
        switch scope {
        case .localNetwork:
            return "Local"
        case .internetPath:
            return "Internet"
        case .dns:
            return "DNS"
        case .reachable:
            return "Reachable"
        case .unknown, .none:
            return "Not checked"
        }
    }

    func pathSymbol(_ scope: NetworkPathScope?) -> String {
        switch scope {
        case .reachable:
            return "checkmark.circle"
        case .localNetwork:
            return "wifi.exclamationmark"
        case .internetPath:
            return "network"
        case .dns:
            return "text.magnifyingglass"
        case .unknown, .none:
            return "questionmark.circle"
        }
    }

    func pathColor(_ scope: NetworkPathScope?, theme: NetScopePopoverTheme) -> Color {
        switch scope {
        case .reachable:
            return theme.success
        case .localNetwork, .internetPath, .dns:
            return theme.warning
        case .unknown, .none:
            return theme.neutralAccent
        }
    }

    func pathDetails(_ check: NetworkPathCheck) -> String {
        let gateway = check.gatewayPing.flatMap { $0.averageMilliseconds }.map { "\(TrafficFormatting.decimal($0))ms gw" } ?? "-- gw"
        let publicPing = check.publicPing.flatMap { $0.averageMilliseconds }.map { "\(TrafficFormatting.decimal($0))ms pub" } ?? "-- pub"
        let dns = check.dnsLookup?.elapsedMilliseconds.map { "\(TrafficFormatting.decimal($0))ms dns" } ?? "-- dns"
        return "\(gateway) / \(publicPing) / \(dns)"
    }

    func wifiDetails(_ wifi: WiFiHealth?) -> String {
        guard let wifi else {
            return "--"
        }

        let rssi = wifi.rssi.map { "\($0)dBm" } ?? "--dBm"
        let noise = wifi.noise.map { "\($0)dBm noise" } ?? "-- noise"
        let rate = wifi.transmitRateMbps.map { "\(TrafficFormatting.decimal($0))Mbps" } ?? "--Mbps"
        let channel = wifi.channel.map { "ch \($0)" } ?? "ch --"
        return "\(rssi) / \(noise) / \(rate) / \(channel)"
    }

    func totalIncomingBytesPerSecond(_ snapshot: NetworkSnapshot) -> Int {
        snapshot.apps.totalIncomingBytesPerSecond()
    }

    func totalOutgoingBytesPerSecond(_ snapshot: NetworkSnapshot) -> Int {
        snapshot.apps.totalOutgoingBytesPerSecond()
    }

    func pingValue(_ snapshot: NetworkSnapshot) -> String {
        guard let average = latestPing(snapshot)?.averageMilliseconds else {
            return "--"
        }

        return "\(TrafficFormatting.decimal(average)) ms"
    }

    func packetLossValue(_ snapshot: NetworkSnapshot) -> String {
        guard let packetLoss = latestPing(snapshot)?.packetLossPercent else {
            return "not sampled"
        }

        return "\(TrafficFormatting.decimal(packetLoss))% loss"
    }

    func latestPing(_ snapshot: NetworkSnapshot) -> PingResult? {
        model.lastPathCheck?.ping ?? snapshot.ping
    }
}
