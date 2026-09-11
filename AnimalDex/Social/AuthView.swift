import SwiftUI

/// Sign in / register, styled as a device panel rather than a stock form.
struct AuthView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private enum Mode { case signIn, register }
    @State private var mode: Mode = .signIn

    @State private var handle = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var validationMessage: String?

    private var normalizedHandle: String { handle.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var formError: String? {
        guard !normalizedHandle.isEmpty, !password.isEmpty else { return nil }

        let handleIsValid = (3...24).contains(normalizedHandle.count)
            && normalizedHandle.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        guard handleIsValid else {
            return "Handle must be 3–24 letters, numbers, or underscores."
        }

        guard mode == .register else { return nil }
        guard normalizedEmail.contains("@") else { return "Enter a valid email address." }
        guard password.count >= 10 else { return "Password must be at least 10 characters." }
        guard password == confirmPassword else { return "Passwords do not match." }
        guard normalizedDisplayName.isEmpty || normalizedDisplayName.count <= 40 else {
            return "Display name must be 40 characters or fewer."
        }
        return nil
    }

    private var canSubmit: Bool {
        !session.isBusy && !normalizedHandle.isEmpty && !password.isEmpty && formError == nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                form
                submitButton
                switcher
                if let message = formError ?? validationMessage ?? session.errorMessage {
                    Text(message.uppercased())
                        .font(Theme.screenText(10))
                        .foregroundStyle(Theme.phosphor)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .screenSurface(Theme.lcd, radius: 8)
                }
            }
            .padding(16)
        }
        .background(Theme.phosphorDim)
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            OrbMark(size: 56)
            Text(mode == .signIn ? "TRAINER SIGN IN" : "NEW TRAINER")
                .font(Theme.display(18))
                .tracking(1.6)
                .foregroundStyle(Theme.outline)
            Text("Sync catches, pin sightings, and compare dexes with friends.")
                .font(Theme.screenText(10))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.outline.opacity(0.7))
        }
        .padding(.vertical, 8)
    }

    private var form: some View {
        VStack(spacing: 10) {
            field("HANDLE", text: $handle, content: .username, identifier: "auth.handle")
            if mode == .register {
                field("DISPLAY NAME", text: $displayName, content: .name, identifier: "auth.displayName")
                field("EMAIL", text: $email, content: .emailAddress, keyboard: .emailAddress, identifier: "auth.email")
            }
            field("PASSWORD", text: $password, content: .password, secure: true, identifier: "auth.password")
            if mode == .register {
                field("CONFIRM PASSWORD", text: $confirmPassword, content: .password, secure: true, identifier: "auth.confirmPassword")
                Text("At least 10 characters. Handles use letters, numbers, and underscores.")
                    .font(Theme.display(9))
                    .foregroundStyle(Theme.outline.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .bevelPanel()
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        content: UITextContentType,
        keyboard: UIKeyboardType = .default,
        secure: Bool = false,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.display(9))
                .tracking(1.2)
                .foregroundStyle(Theme.outline.opacity(0.65))
            Group {
                if secure {
                    SecureField("", text: text).accessibilityIdentifier(identifier)
                } else {
                    TextField("", text: text).accessibilityIdentifier(identifier)
                }
            }
            .textContentType(content)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .font(Theme.screenText(13))
            .foregroundStyle(Theme.phosphor)
            .padding(9)
            .screenSurface(Theme.lcd, radius: 7)
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                guard let formError else {
                    validationMessage = nil
                    switch mode {
                    case .signIn:
                        await session.login(handle: normalizedHandle, password: password)
                    case .register:
                        await session.register(
                            handle: normalizedHandle,
                            email: normalizedEmail,
                            password: password,
                            displayName: normalizedDisplayName.isEmpty ? normalizedHandle : normalizedDisplayName
                        )
                    }
                    return
                }
                validationMessage = formError
                return
            }
        } label: {
            HStack(spacing: 8) {
                if session.isBusy { ProgressView().tint(.white) }
                Text(mode == .signIn ? "SIGN IN" : "CREATE TRAINER")
                    .font(Theme.display(15))
                    .tracking(1.6)
                    .outlinedText()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.shell))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("auth.submit")
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.55)
    }

    private var switcher: some View {
        Button {
            SoundBank.shared.play(.select)
            withAnimation { mode = mode == .signIn ? .register : .signIn }
            session.errorMessage = nil
            validationMessage = nil
            confirmPassword = ""
        } label: {
            Text(mode == .signIn ? "NEED AN ACCOUNT? REGISTER" : "ALREADY REGISTERED? SIGN IN")
                .font(Theme.display(11))
                .tracking(0.8)
                .foregroundStyle(Theme.lens)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("auth.switchMode")
    }
}
