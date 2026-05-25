import SwiftUI

struct ProfileLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profileStore: InsigniaProfileStore
    @State private var email = ""
    @State private var password = ""
    @State private var gamertag = ""
    @State private var errorText: String?
    @State private var isSigningIn = false

    init(profileStore: InsigniaProfileStore) {
        self.profileStore = profileStore
        _email = State(initialValue: profileStore.session?.email ?? "")
        _gamertag = State(initialValue: profileStore.session?.gamertag ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textContentType(.password)

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Insignia Account")
                } footer: {
                    Text("DukeX stores only the session token returned by the unofficial Insignia auth service. Your password is sent only for sign-in and is not saved.")
                }

                Section {
                    Button {
                        Task {
                            await signIn()
                        }
                    } label: {
                        HStack {
                            Label("Sign In", systemImage: "person.crop.circle.badge.checkmark")
                            Spacer()
                            if isSigningIn {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSigningIn || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                    Button {
                        saveGamertagOnly()
                    } label: {
                        Label("Use Gamertag Only", systemImage: "person.crop.circle")
                    }
                    .disabled(isSigningIn || gamertag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    TextField("Gamertag for local lookup", text: $gamertag)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section {
                    Label {
                        Text("Signing in here only powers the DukeX profile tab. It does not change the account tied to your Xbox dashboard. To play online through Insignia, keep Force NAT to Insignia enabled in Settings and make sure your dashboard is registered with Insignia's Xbox Live services.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSigningIn)
    }

    private func signIn() async {
        errorText = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await profileStore.signIn(email: email, password: password)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveGamertagOnly() {
        do {
            try profileStore.signIn(gamertag: gamertag)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
