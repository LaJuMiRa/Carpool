import CarpoolKit
import CarpoolUI
import SwiftUI

/// Profil: Vorname und Kürzel (Avatar = zwei Zeichen).
struct ProfileScreen: View {
    let store: FamilyStore

    @State private var firstName = ""
    @State private var short = ""
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Avatar(short: short.isEmpty ? "?" : short, size: .large)
                    .scaleEffect(1.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.m)
                    .accessibilityHidden(true)
                FormCard {
                    HStack {
                        Text("Vorname")
                        TextField("Vorname", text: $firstName)
                            .textContentType(.givenName)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("profile.name")
                    }
                    .formFieldStyle()
                    Hairline()
                    HStack {
                        Text("Kürzel")
                        TextField("2 Zeichen", text: $short)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    .formFieldStyle()
                }
                .onChange(of: firstName) { old, new in
                    // Kürzel folgt dem Namen, solange es nicht selbst geändert wurde.
                    if short == String(old.prefix(2)) { short = String(new.prefix(2)) }
                }
                .onChange(of: short) { _, new in if new.count > 2 { short = String(new.prefix(2)) } }
                Button("Speichern") {
                    isSaving = true
                    Task {
                        if await store.rename(firstName: firstName, short: short) { dismiss() }
                        isSaving = false
                    }
                }
                .buttonStyle(.carpoolPrimary)
                .disabled(isSaving || firstName.trimmingCharacters(in: .whitespaces).count < 2 || short.count != 2)
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.m)
        }
        .background(Color.paper)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let me = store.snapshot?.me ?? store.member
            firstName = me.firstName
            short = me.short
        }
    }
}
