import SwiftUI

/// Signing up asks for phone or email first, then only shows the fields
/// for whichever one is picked, rather than presenting one long form.
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Method: String, CaseIterable {
        case phone = "Phone"
        case email = "Email"
    }

    @State private var method: Method = .phone
    @State private var username = ""
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var verificationID: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Method", selection: $method) {
                    ForEach(Method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Section("Username") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                }

                switch method {
                case .phone:
                    Section("Phone Number") {
                        TextField("+61 4xx xxx xxx", text: $phoneNumber)
                            .keyboardType(.phonePad)
                    }
                case .email:
                    Section("Email & Password") {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        SecureField("Password", text: $password)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Sign Up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(method == .phone ? "Send Code" : "Sign Up") { submit() }
                        .disabled(isSubmitting || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationDestination(item: $verificationID) { id in
                PhoneVerificationView(verificationID: id, username: username, isNewAccount: true)
            }
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                switch method {
                case .phone:
                    verificationID = try await AuthService.shared.startPhoneVerification(phoneNumber: phoneNumber)
                case .email:
                    try await AuthService.shared.signUpWithEmail(email: email, password: password)
                    try await AuthService.shared.createUserProfile(username: username, email: email, phoneNumber: nil)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview {
    SignUpView()
}
