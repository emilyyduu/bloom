import SwiftUI

// The two ways a Bloom account signs in or signs up: a phone number
// verified by SMS, or an email and password. Shared by LogInView and
// SignUpView, which otherwise only differ in which fields they collect.
enum AuthMethod: String, CaseIterable {
    case phone = "Phone"
    case email = "Email"
}

// The segmented control LogInView and SignUpView both use to choose
// between AuthMethod cases.
struct AuthMethodPicker: View {
    @Binding var method: AuthMethod

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The segmented style truncates "Phone"/"Email" at accessibility
        // sizes, so it becomes a menu instead; the binding is unchanged
        // either way, so the current choice is never lost.
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Method", selection: $method) {
                ForEach(AuthMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Method", selection: $method) {
                ForEach(AuthMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

// The inline red footnote LogInView, SignUpView and PhoneVerificationView
// all show under their form when a request fails.
struct FormErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message).foregroundStyle(Theme.Colors.error).textStyle(.caption)
        }
    }
}

// The inline error on Sign Up, Log In and code entry. A warning icon
// goes with the text so red isn't the only signal. It reads to VoiceOver
// as just the message, and callers add their own identifier.
struct AuthErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
                Text(message)
            }
            .textStyle(.caption)
            .foregroundStyle(Theme.Colors.error)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
        }
    }
}

// Runs an async action while toggling a submission flag and capturing
// any thrown error's description. Shared by LogInView, SignUpView and
// PhoneVerificationView, which all talk to AuthService the same way:
// show a spinner, then either move on or show an inline error.
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
