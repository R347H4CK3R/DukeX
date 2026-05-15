import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject var profileStore: InsigniaProfileStore
    let signIn: () -> Void
    let openDashboard: () -> Void
    let changeProfileImage: () -> Void

    var body: some View {
        List {
            if let session = profileStore.session {
                signedInContent(session)
            } else {
                signedOutContent
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func signedInContent(_ session: InsigniaProfileSession) -> some View {
        Section {
            ProfileHeaderRow(
                gamertag: session.gamertag,
                lastRefreshed: profileStore.lastRefreshedText,
                profileImage: profileStore.profileImage,
                changeProfileImage: changeProfileImage,
                clearProfileImage: profileStore.clearProfileImage
            )
        }

        Section("Account") {
            Button(action: openDashboard) {
                Label("Open Insignia Dashboard", systemImage: "person.text.rectangle")
            }

            Text("DukeX only stores your gamertag locally. Sign in through Insignia's web dashboard to manage the real account.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("Insignia Status") {
            ProfileInfoRow(title: "Users Online",
                           value: profileStore.usersOnlineText,
                           systemImage: "person.2.wave.2")
            ProfileInfoRow(title: "Registered Users",
                           value: profileStore.registeredUsersText,
                           systemImage: "person.3")
            ProfileInfoRow(title: "Games Supported",
                           value: profileStore.gamesSupportedText,
                           systemImage: "gamecontroller")
        }

        Section("Active Games") {
            if profileStore.activeGames.isEmpty {
                ProfileEmptyRow(title: "No public activity synced",
                                systemImage: "antenna.radiowaves.left.and.right")
            } else {
                ForEach(profileStore.activeGames) { game in
                    ProfileInfoRow(title: game.title,
                                   value: game.onlineUsers,
                                   detail: game.detail,
                                   systemImage: "play.circle")
                }
            }
        }
    }

    private var signedOutContent: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text("Insignia Profile")
                        .font(.headline)
                    Text("Not signed in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(action: signIn) {
                    Label("Set Gamertag", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(action: openDashboard) {
                    Label("Open Insignia Dashboard", systemImage: "person.text.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
    }
}

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

private struct ProfileHeaderRow: View {
    let gamertag: String
    let lastRefreshed: String
    let profileImage: UIImage?
    let changeProfileImage: () -> Void
    let clearProfileImage: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            avatar
                .contextMenu {
                    Button(action: changeProfileImage) {
                        Label("Change Profile Picture", systemImage: "photo")
                    }

                    if profileImage != nil {
                        Button(role: .destructive, action: clearProfileImage) {
                            Label("Remove Profile Picture", systemImage: "trash")
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(gamertag)
                    .font(.headline)
                Text("Last refresh: \(lastRefreshed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 72)
    }

    @ViewBuilder
    private var avatar: some View {
        if let profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                Text(initial)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)
        }
    }

    private var initial: String {
        String(gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

private struct ProfileInfoRow: View {
    let title: String
    let value: String
    let detail: String?
    let systemImage: String

    init(title: String, value: String, detail: String? = nil, systemImage: String) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(minHeight: 44)
    }
}

private struct ProfileEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
    }
}
