import CarpoolKit
import CarpoolUI
import SwiftUI

/// Nach der Anmeldung: Familie per Code beitreten oder neue Familie anlegen.
struct FamilySetupScreen: View {
    private enum Mode: String, CaseIterable { case join = "Beitreten", create = "Neue Familie" }

    let session: AppSession

    @State private var mode = Mode.join
    @State private var inviteCode = ""
    @State private var familyName = ""
    @State private var firstName = ""
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Deine Familie").screenTitleStyle()
                    Text(mode == .join
                         ? "Gib den Code ein, den du bekommen hast."
                         : "Du wirst Admin und kannst danach Autos anlegen und Mitglieder einladen.")
                        .font(.callout)
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top, Spacing.xl)

                Picker("Auswahl", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                FormCard {
                    if mode == .join {
                        TextField("Einladungscode, z. B. K7P-2QX", text: $inviteCode)
                            .font(inviteCode.isEmpty ? .body : .body.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .formFieldStyle()
                    } else {
                        TextField("Familienname, z. B. Familie Berger", text: $familyName)
                            .textInputAutocapitalization(.words)
                            .formFieldStyle()
                    }
                    Hairline()
                    TextField("Dein Vorname", text: $firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .formFieldStyle()
                }

                FormError(message: error)

                BusyButton(title: mode == .join ? "Beitreten" : "Familie anlegen", isBusy: isBusy, action: submit)
                    .disabled(!canSubmit)

                Button("Abmelden") { Task { try? await session.signOut() } }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, Spacing.page)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper)
        .onChange(of: mode) { error = nil }
    }

    private var canSubmit: Bool {
        guard !isBusy, firstName.trimmingCharacters(in: .whitespaces).count >= 2 else { return false }
        return mode == .join
            ? inviteCode.trimmingCharacters(in: .whitespaces).count >= 7
            : !familyName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isBusy = true
        error = nil
        Task {
            do throws(CarpoolError) {
                if mode == .join {
                    try await session.joinFamily(inviteCode: inviteCode, firstName: firstName)
                } else {
                    try await session.createFamily(name: familyName, firstName: firstName)
                }
            } catch {
                self.error = error.message
            }
            isBusy = false
        }
    }
}

#if DEBUG
#Preview {
    FamilySetupScreen(session: AppSession(api: PreviewAPI()))
}
#endif
