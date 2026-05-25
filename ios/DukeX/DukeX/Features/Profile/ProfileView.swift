import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject var profileStore: InsigniaProfileStore
    let signIn: () -> Void
    let changeProfileImage: () -> Void

    var body: some View {
        List {
            if let session = profileStore.session {
                signedInContent(session)
            } else {
                signedOutContent
            }

            poweredBySection
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func signedInContent(_ session: InsigniaProfileSession) -> some View {
        let snapshot = profileStore.authenticatedSnapshot

        Section {
            ProfileHeaderRow(
                session: session,
                snapshot: snapshot,
                profileImage: profileStore.profileImage,
                changeProfileImage: changeProfileImage,
                clearProfileImage: profileStore.clearProfileImage
            )
        }

        if session.isAuthenticated {
            authenticatedSections(session: session, snapshot: snapshot)
        } else {
            gamertagOnlySections
        }
    }

    @ViewBuilder
    private func authenticatedSections(
        session: InsigniaProfileSession,
        snapshot: InsigniaAuthenticatedSnapshot?
    ) -> some View {
        Section("Account") {
            NavigationLink {
                ProfileAchievementsView(
                    snapshot: snapshot?.achievements,
                    profileScore: snapshot?.xbProfile?.achievementScore,
                    profileCount: snapshot?.xbProfile?.achievementCount,
                    supportedGames: snapshot?.supportedGames ?? []
                )
            } label: {
                ProfileAchievementsSummaryRow(
                    countText: snapshot?.achievements?.summaryText ??
                        snapshot?.xbProfile?.achievementCount.map(String.init) ??
                        "Not Synced"
                )
            }

            if let minutes = snapshot?.xbProfile?.totalMinutes {
                ProfileInfoRow(title: "Play Time", value: playTimeText(minutes), systemImage: "timer")
            }

            ProfileInfoRow(title: "Last Refresh",
                           value: profileStore.lastRefreshedText,
                           systemImage: "clock")
        }

        Section("Friends") {
            let friends = snapshot?.friends ?? []
            if friends.isEmpty {
                ProfileEmptyRow(title: "No friends synced", systemImage: "person.2")
            } else {
                ForEach(friends) { friend in
                    NavigationLink {
                        ProfileFriendDetailView(friend: friend, profile: snapshot?.friendProfiles[friend.key])
                    } label: {
                        ProfileFriendRow(friend: friend, profile: snapshot?.friendProfiles[friend.key])
                    }
                }
            }
        }

        Section("Messages") {
            let messages = profileStore.unviewedMessages(from: snapshot?.messages ?? [])
            if messages.isEmpty {
                ProfileEmptyRow(title: "No pending messages", systemImage: "envelope")
            } else {
                ForEach(messages) { message in
                    NavigationLink {
                        ProfileMessageDetailView(message: message)
                            .onAppear {
                                profileStore.markMessageViewed(message)
                            }
                    } label: {
                        ProfileMessageRow(message: message)
                    }
                }
            }
        }

        activeGamesSection

        Section("Events") {
            let events = snapshot?.events ?? []
            if events.isEmpty {
                ProfileEmptyRow(title: "No xb.live events synced", systemImage: "calendar")
            } else {
                ForEach(events) { event in
                    ProfileEventRow(event: event)
                }
            }
        }
    }

    private var gamertagOnlySections: some View {
        Group {
            Section("Account") {
                Text("This profile is using local gamertag lookup only. Sign in with an Insignia account to sync friends, messages, active games, events, and xb.live profile details.")
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

            activeGamesSection
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
                    Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("Profile sign-in only powers the DukeX profile tab. Online play still requires Force NAT to Insignia in Settings and a dashboard registered with Insignia's Xbox Live services.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
    }

    private var activeGamesSection: some View {
        Section("Active Games") {
            if profileStore.activeGames.isEmpty {
                ProfileEmptyRow(title: "No public activity synced",
                                systemImage: "antenna.radiowaves.left.and.right")
            } else {
                ForEach(profileStore.activeGames) { game in
                    ProfileActiveGameRow(game: game)
                }
            }
        }
    }

    private var poweredBySection: some View {
        Section {
            Text("DukeX's profile section is powered by xb.live and Insignia services. An Insignia account and xb.live profile setup may be required to fully utilize DukeX's profile features.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.88)
            .allowsTightening(true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private func playTimeText(_ minutes: Double) -> String {
        let hours = minutes / 60.0
        if hours >= 10 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
    }
}
