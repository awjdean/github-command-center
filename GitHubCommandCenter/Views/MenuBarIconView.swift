import SwiftUI

struct MenuBarIconView: View {
    let healthStatus: AppState.HealthStatus
    let prCount: Int

    // Shape-based icons — macOS renders menu bar images as templates (monochrome),
    // so we use distinct SF Symbol shapes to convey state without relying on color.
    private var symbolName: String {
        switch healthStatus {
        case .green:  return "checkmark.circle"
        case .yellow: return "exclamationmark.triangle"
        case .red:    return "xmark.circle"
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
