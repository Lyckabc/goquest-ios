import SwiftUI

struct PriorityBadge: View {
    let priority: String
    var color: Color {
        switch priority {
        case "urgent": return .red
        case "high":   return .orange
        case "low":    return .gray
        default:       return .blue
        }
    }
    var body: some View {
        Text(priority.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(color.opacity(0.85))
            .cornerRadius(4)
    }
}

struct StatusBadge: View {
    let status: String
    var color: Color {
        switch status {
        case "completed": return .green
        case "cancelled", "failed": return .gray
        case "in_progress": return .blue
        case "assigned": return .indigo
        default: return .secondary
        }
    }
    var body: some View {
        Text(status.replacingOccurrences(of: "_", with: " "))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}

struct RiskTierBadge: View {
    let tier: String
    var color: Color {
        switch tier {
        case "critical": return .red
        case "high":     return .orange
        case "medium":   return .blue
        case "low":      return .gray
        default:         return .secondary   // unknown tier from a newer server
        }
    }
    var body: some View {
        Label(tier.uppercased(), systemImage: "shield.lefthalf.filled")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}
