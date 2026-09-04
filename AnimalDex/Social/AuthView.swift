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
    @State private var displayName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                form
                submitButton
                switcher
                if let message = session.errorMessage {
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
                Text("At least 10 characters.")
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
                switch mode {
                case .signIn:
                    await session.login(handle: handle, password: password)
                case .register:
                    await session.register(
                        handle: handle, email: email,
                        password: password,
                        displayName: displayName.isEmpty ? handle : displayName
                    )
                }
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
        .disabled(session.isBusy || handle.isEmpty || password.isEmpty)
        .opacity(handle.isEmpty || password.isEmpty ? 0.55 : 1)
    }

    private var switcher: some View {
        Button {
            SoundBank.shared.play(.select)
            withAnimation { mode = mode == .signIn ? .register : .signIn }
            session.errorMessage = nil
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
