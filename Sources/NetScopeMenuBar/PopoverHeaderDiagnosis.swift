import SwiftUI
import NetScopeCore

extension PopoverView {
    func header(theme: NetScopePopoverTheme) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NetScope")
                    .font(NetScopeFont.bold(15))
                Text(headerStatusText)
                    .font(NetScopeFont.regular(11))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            Group {
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    HeaderIconButton(
                        systemSymbolName: "arrow.clockwise",
                        tooltip: "Check network path",
                        onPress: {
                            model.checkNetworkPath()
                        }
                    )
                }
            }
            .frame(width: 26, height: 26)
            .background(theme.controlSurface, in: Circle())
            .overlay {
                Circle().stroke(theme.controlBorder, lineWidth: 1)
            }
            .help("Check network path")
        }
    }

    var headerStatusText: String {
        if model.isLoading {
            return "Checking network path..."
        }

        guard let snapshot = model.state.snapshot else {
            return "Rolling counters every 60s · ping on path check"
        }

        let timestamp = Self.headerTimeFormatter.string(from: snapshot.capturedAt)
        switch snapshot.kind {
        case .interactive:
            return "Updated \(timestamp) · app counters + Wi-Fi"
        case .pathCheck:
            return "Checked \(timestamp) · reused app counters"
        case .rollingAppCounters:
            return "Observed \(timestamp) · app counters only"
        }
    }

    func diagnosis(_ snapshot: NetworkSnapshot, theme: NetScopePopoverTheme) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(statusColor(theme: theme))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                Text(snapshot.diagnosis.title)
                    .font(NetScopeFont.semibold(13.5))
                    .lineLimit(2)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text(confidenceText(snapshot))
                Text("/")
                    .foregroundStyle(theme.tertiaryText)
                Text(sampleKindText(snapshot.kind))
            }
            .font(NetScopeFont.medium(11.25))
            .foregroundStyle(theme.secondaryText)

            if let correlation = applicableCorrelation(for: snapshot) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(correlation.reason)
                        .lineLimit(2)
                }
                .font(NetScopeFont.medium(11.25))
                .foregroundStyle(theme.warning)
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    func confidenceText(_ snapshot: NetworkSnapshot) -> String {
        if applicableCorrelation(for: snapshot) != nil && model.state.effectiveConfidence != snapshot.diagnosis.confidence {
            return "\(model.state.effectiveConfidence.rawValue.capitalized) confidence"
        }

        return "\(snapshot.diagnosis.confidence.rawValue.capitalized) confidence"
    }

    func applicableCorrelation(for snapshot: NetworkSnapshot) -> RecentCorrelation? {
        guard let correlation = model.state.correlation,
              snapshot.diagnosis.kind.canUseAppCorrelation,
              snapshot.diagnosis.kind.appName == correlation.appName else {
            return nil
        }

        return correlation
    }

    func sampleKindText(_ kind: SnapshotKind) -> String {
        switch kind {
        case .interactive:
            return "App + Wi-Fi"
        case .pathCheck:
            return "Path checked"
        case .rollingAppCounters:
            return "App counters only"
        }
    }
    func statusColor(theme: NetScopePopoverTheme) -> Color {
        switch model.state.status {
        case .normal:
            return theme.success
        case .possiblePressure:
            return theme.warning
        case .likelyIssue:
            return theme.danger
        }
    }
}
