import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @State private var error: String?
    @State private var inFlight = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .frame(width: 72, height: 72)
                .foregroundStyle(.indigo)
            Text("Goquest")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("AI-agent ticket management")
                .foregroundStyle(.secondary)

            Spacer().frame(height: 40)

            Button {
                Task { await signIn() }
            } label: {
                if inFlight {
                    ProgressView().tint(.white)
                } else {
                    Text("Sign in with ZITADEL")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.horizontal, 32)
            .disabled(inFlight)

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(white: 0.95), .white], startPoint: .top, endPoint: .bottom))
    }

    private func signIn() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else {
            error = "Cannot present login UI"
            return
        }
        inFlight = true
        defer { inFlight = false }
        do {
            try await auth.login(presenting: root)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
