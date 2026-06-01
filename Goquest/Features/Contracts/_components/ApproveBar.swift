import SwiftUI

struct ApproveBar: View {
    let isBusy: Bool
    let onApprove: () -> Void
    let onAbort: () -> Void

    @State private var showAbortConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This contract requires your approval", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            HStack(spacing: 12) {
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isBusy)

                Button(role: .destructive) {
                    showAbortConfirm = true
                } label: {
                    Label("Abort", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
            if isBusy { ProgressView() }
        }
        .padding()
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .confirmationDialog("Abort this contract? This stops the workflow.",
                             isPresented: $showAbortConfirm, titleVisibility: .visible) {
            Button("Abort", role: .destructive, action: onAbort)
            Button("Cancel", role: .cancel) {}
        }
    }
}
