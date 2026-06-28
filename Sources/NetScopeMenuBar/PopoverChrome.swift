import SwiftUI

extension PopoverView {
    func sectionDivider(theme: NetScopePopoverTheme) -> some View {
        Rectangle()
            .fill(theme.divider)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
    func emptyState(theme: NetScopePopoverTheme) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.isLoading ? "Sampling current activity" : "Waiting for app counters")
                .font(NetScopeFont.semibold(14))
                .foregroundStyle(theme.primaryText)
            Text(model.isLoading ? "Checking latency and packet loss now." : "NetScope will keep the menu light while counters become available.")
                .font(NetScopeFont.medium(12.5))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(theme: theme, cornerRadius: 18)
    }

    func warningNotice(_ message: String, theme: NetScopePopoverTheme) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.warning)
                .frame(width: 14)
                .padding(.top, 1)
            Text(message)
                .font(NetScopeFont.medium(11.25))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
    }
    func footer(theme: NetScopePopoverTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onClearBaseline()
            } label: {
                actionRow(
                    icon: "trash",
                    title: "Clear Learned Baseline",
                    accessory: "",
                    theme: theme
                )
            }

            Button(role: .destructive) {
                onQuit()
            } label: {
                actionRow(
                    icon: "power",
                    title: "Quit NetScope",
                    accessory: "⌘Q",
                    theme: theme
                )
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.plain)
    }

    func actionRow(
        icon: String,
        title: String,
        accessory: String,
        theme: NetScopePopoverTheme
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 16)

            Text(title)
                .font(NetScopeFont.medium(12.5))
                .foregroundStyle(theme.primaryText)

            Spacer()

            Text(accessory)
                .font(NetScopeFont.medium(11))
                .foregroundStyle(theme.tertiaryText)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 7)
    }
}
