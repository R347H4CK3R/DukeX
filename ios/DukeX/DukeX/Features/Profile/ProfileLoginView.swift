import SwiftUI

struct ProfileLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profileStore: InsigniaProfileStore
    let openDashboard: () -> Void
    @State private var gamertag: String
    @State private var errorText: String?

    init(profileStore: InsigniaProfileStore, openDashboard: @escaping () -> Void) {
        self.profileStore = profileStore
        self.openDashboard = openDashboard
        _gamertag = State(initialValue: profileStore.session?.gamertag ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Insignia") {
                    TextField("Gamertag", text: $gamertag)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        dismiss()
                        openDashboard()
                    } label: {
                        Label("Open Insignia Dashboard", systemImage: "person.text.rectangle")
                    }
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

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        signIn()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func signIn() {
        do {
            try profileStore.signIn(gamertag: gamertag)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
