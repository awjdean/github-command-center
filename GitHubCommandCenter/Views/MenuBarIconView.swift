import SwiftUI

struct MenuBarIconView: View {
    let healthStatus: AppState.HealthStatus
    let prCount: Int
    let isLoading: Bool

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
            if isLoading {
                MenuBarLoadingIndicator()
            } else {
                Image(systemName: symbolName)
                    .imageScale(.medium)
                if prCount > 0 {
                    Text("\(prCount)")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
        }
    }
}

private struct MenuBarLoadingIndicator: View {
    @State private var tick = false

    let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .imageScale(.medium)
            .opacity(tick ? 1.0 : 0.35)
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 0.35)) {
                    tick.toggle()
                }
            }
    }
}

#Preview("Loading") {
    MenuBarIconView(healthStatus: .green, prCount: 0, isLoading: true)
        .padding()
}

#Preview("Green Empty") {
    MenuBarIconView(healthStatus: .green, prCount: 0, isLoading: false)
        .padding()
}

#Preview("Green Count") {
    MenuBarIconView(healthStatus: .green, prCount: 3, isLoading: false)
        .padding()
}

#Preview("Yellow Empty") {
    MenuBarIconView(healthStatus: .yellow, prCount: 0, isLoading: false)
        .padding()
}

#Preview("Yellow Count") {
    MenuBarIconView(healthStatus: .yellow, prCount: 2, isLoading: false)
        .padding()
}

#Preview("Red Empty") {
    MenuBarIconView(healthStatus: .red, prCount: 0, isLoading: false)
        .padding()
}

#Preview("Red Count") {
    MenuBarIconView(healthStatus: .red, prCount: 5, isLoading: false)
        .padding()
}
