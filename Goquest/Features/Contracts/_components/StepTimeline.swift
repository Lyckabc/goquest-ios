import SwiftUI

struct StepTimeline: View {
    let plan: ContractPlan?
    let ledger: [ContractLedgerEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan / Ledger").font(.headline)
            if let steps = plan?.steps, !steps.isEmpty {
                ForEach(steps) { step in
                    StepRow(step: step, ledger: ledgerEntry(for: step.stepId))
                }
            } else {
                Text("No plan yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ledgerEntry(for stepId: String) -> ContractLedgerEntry? {
        ledger.first(where: { $0.stepId == stepId })
    }
}

private struct StepRow: View {
    let step: ContractPlanStep
    let ledger: ContractLedgerEntry?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("\(step.stepId)  \(step.capability)")
                    .font(.callout)
                if let target = step.target {
                    Text("@ \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reason = ledger?.verdict?.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(ledger?.verdict?.passed == false ? .orange : .secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        let symbol: String
        let color: Color
        switch ledger?.status {
        case "ok":      symbol = "checkmark.circle.fill"; color = .green
        case "fail":    symbol = "xmark.circle.fill";     color = .red
        case "skipped": symbol = "minus.circle.fill";     color = .gray
        case .some:     symbol = "circle.dotted";         color = .blue
        case .none:     symbol = "circle";                color = .gray
        }
        return Image(systemName: symbol).foregroundStyle(color)
    }
}
