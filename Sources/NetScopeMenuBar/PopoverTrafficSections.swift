import Foundation
import SwiftUI
import NetScopeCore

extension PopoverView {
    func evidence(_ snapshot: NetworkSnapshot, theme: NetScopePopoverTheme) -> some View {
        return VStack(alignment: .leading, spacing: 9) {
            Text("Evidence")
                .font(NetScopeFont.semibold(13))
                .foregroundStyle(theme.primaryText)

            ForEach(Array(snapshot.diagnosis.reasons.prefix(3).enumerated()), id: \.offset) { index, reason in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(evidenceAccent(index: index, theme: theme))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    Text(reason)
                        .font(NetScopeFont.medium(12.5))
                        .foregroundStyle(theme.bodyText)
                        .lineLimit(3)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
    func topApps(_ snapshot: NetworkSnapshot, theme: NetScopePopoverTheme) -> some View {
        let groups = AppTrafficClassifier().groups(for: snapshot.apps, limitPerGroup: 3)
        let maxTraffic = max(snapshot.apps.map(\.totalBytesPerSecond).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Observed Traffic")
                .font(NetScopeFont.semibold(13))
                .foregroundStyle(theme.primaryText)

            trafficGroup("User apps", apps: groups.userApps, maxTraffic: maxTraffic, theme: theme)
            trafficGroup("Infrastructure", apps: groups.infrastructure, maxTraffic: maxTraffic, theme: theme)
            trafficGroup("System", apps: groups.systemServices, maxTraffic: maxTraffic, theme: theme)
            trafficGroup("Unknown", apps: groups.unknown, maxTraffic: maxTraffic, theme: theme)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    func trafficGroup(
        _ title: String,
        apps: [ClassifiedAppTraffic],
        maxTraffic: Int,
        theme: NetScopePopoverTheme
    ) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(NetScopeFont.medium(10.5))
                    .foregroundStyle(theme.secondaryText)

                ForEach(Array(apps.enumerated()), id: \.offset) { index, classified in
                    appTrafficRow(
                        classified.app,
                        index: index + 1,
                        accent: title == "User apps" ? theme.success : theme.neutralAccent,
                        maxTraffic: maxTraffic,
                        theme: theme
                    )
                }
            }
        }
    }

    func appTrafficRow(
        _ app: AppTraffic,
        index: Int,
        accent: Color,
        maxTraffic: Int,
        theme: NetScopePopoverTheme
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(index)")
                .font(NetScopeFont.semibold(11))
                .monospacedDigit()
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 16, alignment: .trailing)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.displayName)
                        .font(NetScopeFont.semibold(12.5))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(compactAppTraffic(app))
                        .font(NetScopeFont.medium(10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.rail)
                            .overlay {
                                Capsule().stroke(theme.railBorder, lineWidth: 1)
                            }
                        Capsule()
                            .fill(accent)
                            .frame(width: max(6, proxy.size.width * progress(for: app, maxTraffic: maxTraffic)))
                    }
                }
                .frame(height: 5)
            }
            .padding(.bottom, 2)
        }
    }
    func compactAppTraffic(_ app: AppTraffic) -> String {
        TrafficFormatting.appTraffic(app, style: .compact)
    }

    func progress(for app: AppTraffic, maxTraffic: Int) -> Double {
        guard maxTraffic > 0 else {
            return 0
        }

        return min(1, max(0, Double(app.totalBytesPerSecond) / Double(maxTraffic)))
    }

    func evidenceAccent(index: Int, theme: NetScopePopoverTheme) -> Color {
        switch index {
        case 0:
            return theme.warning
        case 1:
            return theme.neutralAccent
        default:
            return theme.success
        }
    }
}
