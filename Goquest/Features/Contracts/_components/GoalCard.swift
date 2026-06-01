import SwiftUI

struct GoalCard: View {
    let detail: ContractDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.summaryTitle ?? detail.goal ?? "(no goal)")
                .font(.headline)
            if let goal = detail.goal, goal != detail.summaryTitle {
                Text(goal)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            HStack(spacing: 8) {
                if let channel = detail.origin?.channel, !channel.isEmpty {
                    Label(channel, systemImage: "bubble.left.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let ws = detail.workspace, !ws.isEmpty {
                    Label(ws, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let reason = detail.abortReason, !reason.isEmpty {
                Text("Aborted: \(reason)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
