import SwiftUI

/// The two ways a Bloom account signs in or signs up: a phone number
/// verified by SMS, or an email and password. Shared by LogInView and
/// SignUpView, which otherwise only differ in which fields they collect.
enum AuthMethod: String, CaseIterable {
    case phone = "Phone"
    case email = "Email"
}

/// The segmented control LogInView and SignUpView both use to choose
/// between AuthMethod cases.
struct AuthMethodPicker: View {
    @Binding var method: AuthMethod

    var body: some View {
        Picker("Method", selection: $method) {
            ForEach(AuthMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// The inline red footnote LogInView, SignUpView and PhoneVerificationView
/// all show under their form when a request fails.
struct FormErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message).foregroundStyle(.red).font(.footnote)
        }
    }
}

/// Runs an async action while toggling a submission flag and capturing
/// any thrown error's description. Shared by LogInView, SignUpView and
/// PhoneVerificationView, which all talk to AuthService the same way:
/// show a spinner, then either move on or show an inline error.
@MainActor
func performSubmission(
    isSubmitting: Binding<Bool>,
    errorMessage: Binding<String?>,
    action: @escaping () async throws -> Void
) {
    isSubmitting.wrappedValue = true
    errorMessage.wrappedValue = nil
    Task {
        do {
            try await action()
        } catch {
            errorMessage.wrappedValue = error.localizedDescription
        }
        isSubmitting.wrappedValue = false
    }
}
