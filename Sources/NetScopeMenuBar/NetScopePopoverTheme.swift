import SwiftUI

struct NetScopePopoverTheme {
    let background: Color
    let outerBorder: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let bodyText: Color
    let panelSurface: Color
    let panelBorder: Color
    let emphasizedPanelSurface: Color
    let emphasizedPanelBorder: Color
    let controlSurface: Color
    let controlBorder: Color
    let rail: Color
    let railBorder: Color
    let divider: Color
    let success: Color
    let warning: Color
    let danger: Color
    let neutralAccent: Color

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .light:
            background = Color(red: 0.95, green: 0.96, blue: 0.97)
            outerBorder = Color.black.opacity(0.08)
            primaryText = Color(red: 0.08, green: 0.09, blue: 0.11)
            secondaryText = Color(red: 0.38, green: 0.40, blue: 0.45)
            tertiaryText = Color(red: 0.58, green: 0.59, blue: 0.63)
            bodyText = Color(red: 0.18, green: 0.20, blue: 0.25)
            panelSurface = Color.white.opacity(0.52)
            panelBorder = Color.white.opacity(0.74)
            emphasizedPanelSurface = Color.white.opacity(0.66)
            emphasizedPanelBorder = Color.white.opacity(0.86)
            controlSurface = Color.white.opacity(0.68)
            controlBorder = Color.white.opacity(0.88)
            rail = Color.black.opacity(0.07)
            railBorder = Color.black.opacity(0.08)
            divider = Color.black.opacity(0.10)
            success = Color(red: 0.24, green: 0.62, blue: 0.48)
            warning = Color(red: 0.67, green: 0.48, blue: 0.20)
            danger = Color(red: 0.78, green: 0.24, blue: 0.25)
            neutralAccent = Color(red: 0.55, green: 0.58, blue: 0.62)
        default:
            background = Color(red: 0.11, green: 0.11, blue: 0.12)
            outerBorder = Color.white.opacity(0.07)
            primaryText = Color(red: 0.96, green: 0.96, blue: 0.97)
            secondaryText = Color(red: 0.68, green: 0.68, blue: 0.70)
            tertiaryText = Color(red: 0.39, green: 0.39, blue: 0.40)
            bodyText = Color(red: 0.90, green: 0.90, blue: 0.92)
            panelSurface = Color(red: 0.17, green: 0.17, blue: 0.18).opacity(0.58)
            panelBorder = Color.white.opacity(0.11)
            emphasizedPanelSurface = Color(red: 0.17, green: 0.17, blue: 0.18).opacity(0.66)
            emphasizedPanelBorder = Color.white.opacity(0.13)
            controlSurface = Color(red: 0.17, green: 0.17, blue: 0.18).opacity(0.72)
            controlBorder = Color.white.opacity(0.13)
            rail = Color(red: 0.23, green: 0.23, blue: 0.24).opacity(0.72)
            railBorder = Color.white.opacity(0.06)
            divider = Color.white.opacity(0.11)
            success = Color(red: 0.39, green: 0.82, blue: 0.64)
            warning = Color(red: 0.75, green: 0.55, blue: 0.23)
            danger = Color(red: 1.00, green: 0.45, blue: 0.43)
            neutralAccent = Color(red: 0.56, green: 0.56, blue: 0.58)
        }
    }
}
