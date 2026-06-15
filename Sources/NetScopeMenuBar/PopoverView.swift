import Foundation
import SwiftUI
import NetScopeCore

struct PopoverView: View {
    @ObservedObject var model: MenuBarModel
    let onClearBaseline: () -> Void
    let onQuit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    static let headerTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        let theme = NetScopePopoverTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            header(theme: theme)
            sectionDivider(theme: theme)
                .padding(.top, 10)
                .padding(.bottom, 11)

            if let snapshot = model.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        diagnosis(snapshot, theme: theme)
                        if let rollingWarning = model.rollingWarning {
                            warningNotice(rollingWarning, theme: theme)
                        }
                        metrics(snapshot, theme: theme)
                        sectionDivider(theme: theme)
                        pathStatus(snapshot, theme: theme)
                        sectionDivider(theme: theme)
                        wifiHealth(snapshot, theme: theme)
                        sectionDivider(theme: theme)
                        trafficTrend(theme: theme)
                        sectionDivider(theme: theme)
                        baseline(snapshot, theme: theme)
                        sectionDivider(theme: theme)
                        evidence(snapshot, theme: theme)
                        sectionDivider(theme: theme)
                        topApps(snapshot, theme: theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hiddenAppKitScrollIndicators()
                }
                .scrollIndicators(.hidden)
            } else if let errorMessage = model.errorMessage {
                errorState(errorMessage, theme: theme)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    emptyState(theme: theme)
                    if let rollingWarning = model.rollingWarning {
                        warningNotice(rollingWarning, theme: theme)
                    }
                }
            }

            Spacer(minLength: 16)
            sectionDivider(theme: theme)
                .padding(.bottom, 7)
            footer(theme: theme)
        }
        .padding(18)
        .frame(width: 420, height: 680, alignment: .topLeading)
        .background(theme.background)
        .foregroundStyle(theme.primaryText)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.outerBorder, lineWidth: 1)
        }
    }
}
