import SwiftUI

extension Color {
    static let panelBackground  = Color(red: 0.176, green: 0.176, blue: 0.239)  // #2D2D3D
    static let panelSurface     = Color(red: 0.227, green: 0.227, blue: 0.290)  // #3A3A4A
    static let textPrimary      = Color(red: 1.000, green: 1.000, blue: 1.000)  // #FFFFFF
    static let textSecondary    = Color(red: 0.878, green: 0.878, blue: 0.878)  // #E0E0E0
    static let textTertiary     = Color(red: 0.545, green: 0.580, blue: 0.620)  // #8B949E
    static let textMuted        = Color(red: 0.400, green: 0.400, blue: 0.400)  // #666666
    static let linkBlue         = Color(red: 0.345, green: 0.651, blue: 1.000)  // #58A6FF
    static let statusGreen      = Color(red: 0.188, green: 0.631, blue: 0.306)  // #30A14E
    static let statusYellow     = Color(red: 0.831, green: 0.627, blue: 0.090)  // #D4A017
    static let statusRed        = Color(red: 0.878, green: 0.365, blue: 0.267)  // #E05D44
    static let statusGray       = Color(red: 0.333, green: 0.333, blue: 0.333)  // #555555
}

extension Font {
    static let panelTitle    = Font.system(size: 13, weight: .semibold)
    static let panelSubtitle = Font.system(size: 11, weight: .regular)
    static let sectionLabel  = Font.system(size: 10, weight: .semibold)
    static let prNumber      = Font.system(size: 11, weight: .semibold)
    static let prTitle       = Font.system(size: 12, weight: .regular)
    static let prRepo        = Font.system(size: 10, weight: .regular)
    static let footerText    = Font.system(size: 10, weight: .regular)
    static let tooltipLabel  = Font.system(size: 9, weight: .medium)
    static let tooltipDetail = Font.system(size: 10, weight: .regular)
}
