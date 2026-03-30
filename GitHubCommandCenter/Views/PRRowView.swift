import SwiftUI

struct PRRowView: View {
    let pr: PRState
    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // PR number — styled as a link
                        Text("#\(pr.number)")
                            .font(.prNumber)
                            .foregroundColor(.linkBlue)
                            .underline()

                        // Role label (Your PR / Assigned / Review requested)
                        if !pr.displayRole.isEmpty {
                            Text(pr.displayRole)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.textMuted)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.panelSurface)
                                .cornerRadius(3)
                        }

                        Spacer()

                        // Draft badge
                        if pr.draftStatus == .draft {
                            Text("DRAFT")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.textMuted)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.textMuted.opacity(0.5), lineWidth: 0.5)
                                )
                        }
                    }

                    Text(pr.title)
                        .font(.prTitle)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Text(pr.repoFullName)
                            .font(.prRepo)
                            .foregroundColor(.textMuted)

                        Spacer()

                        // Three status dots: CI • Review • Merge
                        HStack(spacing: 5) {
                            StatusDotView(dimension: .ci, pr: pr)
                            StatusDotView(dimension: .review, pr: pr)
                            StatusDotView(dimension: .merge, pr: pr)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovered ? Color.panelSurface : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .accessibilityLabel("PR \(pr.number), \(pr.title), \(pr.repoFullName)")
    }
}
