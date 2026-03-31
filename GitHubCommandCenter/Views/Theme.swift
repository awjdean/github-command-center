import SwiftUI

enum Theme {
    enum Colors {
        static let panelBackground = Color(red: 0.176, green: 0.176, blue: 0.239)  // #2D2D3D
        static let panelSurface = Color(red: 0.227, green: 0.227, blue: 0.290)  // #3A3A4A
        static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)  // #FFFFFF
        static let textSecondary = Color(red: 0.878, green: 0.878, blue: 0.878)  // #E0E0E0
        static let textTertiary = Color(red: 0.545, green: 0.580, blue: 0.620)  // #8B949E
        static let textMuted = Color(red: 0.400, green: 0.400, blue: 0.400)  // #666666
        static let linkBlue = Color(red: 0.345, green: 0.651, blue: 1.000)  // #58A6FF
        static let statusGreen = Color(red: 0.188, green: 0.631, blue: 0.306)  // #30A14E
        static let statusYellow = Color(red: 0.831, green: 0.627, blue: 0.090)  // #D4A017
        static let statusRed = Color(red: 0.878, green: 0.365, blue: 0.267)  // #E05D44
        static let statusGray = Color(red: 0.333, green: 0.333, blue: 0.333)  // #555555
    }

    enum Spacing {
        static let hairline: CGFloat = 1
        static let micro: CGFloat = 2
        static let xxxs: CGFloat = 3
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 40
    }

    enum Fonts {
        static let panelTitle = Font.system(size: 15, weight: .semibold)
        static let panelSubtitle = Font.system(size: 13, weight: .regular)
        static let sectionLabel = Font.system(size: 12, weight: .semibold)
        static let prNumber = Font.system(size: 13, weight: .semibold)
        static let prTitle = Font.system(size: 14, weight: .regular)
        static let prRepo = Font.system(size: 12, weight: .regular)
        static let footerText = Font.system(size: 12, weight: .regular)
        static let tooltipLabel = Font.system(size: 11, weight: .medium)
        static let tooltipDetail = Font.system(size: 12, weight: .regular)
    }
}
