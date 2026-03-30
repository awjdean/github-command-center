import SwiftUI

struct MenuBarIconView: View {
    let healthStatus: AppState.HealthStatus
    let prCount: Int

    // Shape-based icons — macOS renders menu bar images as templates (monochrome),
    // so we use distinct SF Symbol shapes to convey state without relying on color.
    private var symbolName: String {
        switch healthStatus {
        case .green: return "checkmark.circle"
        case .yellow: return "exclamationmark.triangle"
        case .red: return "xmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .imageScale(.medium)
            if prCount > 0 {
                Text("\(prCount)")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
    }
}

#Preview("Green Empty") {
    MenuBarIconView(healthStatus: .green, prCount: 0)
        .padding()
}

#Preview("Green Count") {
    MenuBarIconView(healthStatus: .green, prCount: 3)
        .padding()
}

#Preview("Yellow Empty") {
    MenuBarIconView(healthStatus: .yellow, prCount: 0)
        .padding()
}

#Preview("Yellow Count") {
    MenuBarIconView(healthStatus: .yellow, prCount: 2)
        .padding()
}

#Preview("Red Empty") {
    MenuBarIconView(healthStatus: .red, prCount: 0)
        .padding()
}

#Preview("Red Count") {
    MenuBarIconView(healthStatus: .red, prCount: 5)
        .padding()
}
