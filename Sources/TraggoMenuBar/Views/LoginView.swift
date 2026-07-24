import SwiftUI

/// Inline login form shown in the popover when there's no valid session.
/// The password lives only in local @State — once we have a token it's cleared
/// and never persisted.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        // @Bindable lets us bind directly to the @Observable model's properties.
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 8) {
            Text("Log in to Traggo")
                .font(.headline)

            TextField("Server URL", text: $model.serverURL)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Log in", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(username.isEmpty || password.isEmpty || model.isBusy)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private func submit() {
        guard !username.isEmpty, !password.isEmpty else { return }
        Task {
            await model.login(username: username, password: password)
            password = ""   // never keep the password around
        }
    }
}
