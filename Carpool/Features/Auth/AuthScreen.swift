import CarpoolKit
import CarpoolUI
import SwiftUI

/// Anmelden oder Konto erstellen mit E-Mail und Passwort.
struct AuthScreen: View {
    private enum Mode { case signIn, signUp }
    private enum Field { case email, password }

    let session: AppSession

    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Carpool").screenTitleStyle()
                    Text(mode == .signIn
                         ? "Melde dich an, um zu sehen, wer welches Auto hat."
                         : "Leg ein Konto an. Danach trittst du deiner Familie bei.")
                        .font(.callout)
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top, Spacing.xl)

                FormCard {
                    TextField("E-Mail", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .formFieldStyle()
                    Hairline()
                    SecureField("Passwort", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit(submit)
                        .formFieldStyle()
                }

                FormError(message: error)

                VStack(spacing: Spacing.s) {
                    BusyButton(title: mode == .signIn ? "Anmelden" : "Konto erstellen", isBusy: isBusy,
                               action: submit)
                        .disabled(!canSubmit)
                    Button(mode == .signIn ? "Noch kein Konto? Konto erstellen" : "Schon ein Konto? Anmelden") {
                        mode = mode == .signIn ? .signUp : .signIn
                        error = nil
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, Spacing.page)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper)
        .animation(Motion.crossfade, value: error)
    }

    private var canSubmit: Bool {
        !isBusy && email.contains("@") && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isBusy = true
        error = nil
        Task {
            do throws(CarpoolError) {
                if mode == .signIn {
                    try await session.signIn(email: email, password: password)
                } else {
                    try await session.signUp(email: email, password: password)
                }
            } catch {
                self.error = error.message
                if error.code == "confirmation_required" { mode = .signIn }
            }
            isBusy = false
        }
    }
}

#if DEBUG
#Preview {
    AuthScreen(session: AppSession(api: PreviewAPI()))
}
#endif
