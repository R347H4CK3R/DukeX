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
