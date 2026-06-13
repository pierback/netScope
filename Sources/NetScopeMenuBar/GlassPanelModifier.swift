import SwiftUI

struct GlassPanelModifier: ViewModifier {
    let theme: NetScopePopoverTheme
    let cornerRadius: CGFloat
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                emphasized ? theme.emphasizedPanelSurface : theme.panelSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(emphasized ? theme.emphasizedPanelBorder : theme.panelBorder, lineWidth: 1)
            }
    }
}

extension View {
    func glassPanel(
        theme: NetScopePopoverTheme,
        cornerRadius: CGFloat,
        emphasized: Bool = false
    ) -> some View {
        modifier(GlassPanelModifier(theme: theme, cornerRadius: cornerRadius, emphasized: emphasized))
    }
}
