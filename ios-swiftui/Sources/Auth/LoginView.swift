import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appState: AppState

    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(spacing: 6) {
                    Text("Goldenmole Dashboard")
                        .font(.title.bold())
                    Text("เข้าสู่ระบบเพื่อดูภาพรวม")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField("ชื่อผู้ใช้", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                    SecureField("รหัสผ่าน", text: $password)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("เข้าสู่ระบบ").bold()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#0D98A5"))
                .disabled(isSubmitting || username.isEmpty || password.isEmpty)

                Spacer()
            }
            .padding(24)
        }
    }

    private func submit() async {
        isSubmitting = true
        errorText = nil
        do {
            try await auth.login(username: username, password: password)
            await appState.loadInitial()
        } catch {
            errorText = error.localizedDescription
        }
        isSubmitting = false
    }
}
