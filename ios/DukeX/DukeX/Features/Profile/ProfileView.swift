import SwiftUI
import UIKit

enum DukeXDownloadCountState: Equatable {
    case hidden
    case loading
    case loaded(Int)
    case failed
}

struct ProfileView: View {
    @ObservedObject var profileStore: InsigniaProfileStore
    @ObservedObject var socialStore: XBLiveSocialStore
    @AppStorage(ProfileFriendSortMode.defaultsKey) private var friendSortModeRawValue = ProfileFriendSortMode.favorites.rawValue
    @State private var favoriteFriendKeys = ProfileFriendFavorites.load()
    @State private var maftyAvatarTapCount = 0
    @State private var maftyDownloadCountUnlocked = false
    @State private var maftyDownloadCountState = DukeXDownloadCountState.hidden
    @State private var maftyDownloadCountTask: Task<Void, Never>?

    let signIn: () -> Void
    let signOut: () -> Void
    let changeProfileImage: () -> Void
    let changeFriendProfileImage: (InsigniaFriend) -> Void
    let changeSocialFriendProfileImage: (XBLiveSocialFriend) -> Void
    let installedGames: [LibraryFile]
    let inviteEligibleGames: [LibraryFile]
    let launchGameFromInvite: (LibraryFile) -> Void

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
        .dukeXThemedListBackground()
        .task(id: profileStore.session?.gamertag) {
            guard profileStore.session?.isAuthenticated == true else {
                await MainActor.run {
                    socialStore.clear()
                }
                return
            }

            await socialStore.refreshAll()
        }
    }

    @ViewBuilder
    private func signedInContent(_ session: InsigniaProfileSession) -> some View {
        let snapshot = profileStore.authenticatedSnapshot

        Section {
            ProfileHeaderRow(
                session: session,
                snapshot: snapshot,
                profileImage: profileStore.profileImage,
                dukeXDownloadCountState: dukeXDownloadCountState(for: session),
                avatarTapAction: { handleProfileAvatarTap(for: session) },
                changeProfileImage: changeProfileImage,
                clearProfileImage: profileStore.clearProfileImage
            )
        }
        .dukeXThemedListRowBackground()

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
            let friends = snapshot?.friends ?? []

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

            NavigationLink {
                ProfileFriendsView(
                    profileStore: profileStore,
                    socialStore: socialStore,
                    sortMode: friendSortModeBinding,
                    favoriteFriendKeys: favoriteFriendKeys,
                    toggleFavorite: toggleFavorite,
                    toggleSocialFavorite: toggleSocialFavorite,
                    changeFriendProfileImage: changeFriendProfileImage,
                    changeSocialFriendProfileImage: changeSocialFriendProfileImage,
                    installedGames: installedGames,
                    inviteEligibleGames: inviteEligibleGames,
                    currentUserAchievements: snapshot?.achievements,
                    launchGameFromInvite: launchGameFromInvite
                )
            } label: {
                ProfileInfoRow(title: "Friends",
                               value: countText(mergedFriendsCount(insigniaFriends: friends)),
                               systemImage: "person.2")
            }

            NavigationLink {
                ProfileSocialMessagesView(
                    socialStore: socialStore,
                    legacyMessages: snapshot?.messages ?? [],
                    legacyUnreadMessages: profileStore.unviewedMessages(from: snapshot?.messages ?? []),
                    friendProfileImages: profileStore.friendProfileImages,
                    friendProfiles: snapshot?.friendProfiles ?? [:],
                    socialFriends: socialStore.messageableFriends,
                    markLegacyMessageViewed: profileStore.markMessageViewed,
                    installedGames: installedGames,
                    inviteEligibleGames: inviteEligibleGames,
                    currentUserAchievements: snapshot?.achievements,
                    launchGameFromInvite: launchGameFromInvite
                )
            } label: {
                ProfileInfoRow(title: "Messages",
                               value: unreadMessagesText(legacyMessages: snapshot?.messages ?? []),
                               systemImage: "envelope")
            }

            NavigationLink {
                ProfilePlaytimeView(
                    totalMinutes: snapshot?.xbProfile?.totalMinutes,
                    games: snapshot?.playtimeGames ?? []
                )
            } label: {
                ProfileInfoRow(title: "Playtime",
                               value: playtimeSummaryText(
                                   totalMinutes: snapshot?.xbProfile?.totalMinutes,
                                   gameCount: snapshot?.playtimeGames.count ?? 0
                               ),
                               systemImage: "timer")
            }
        }
        .dukeXThemedListRowBackground()

        activeGamesSection

        Section("Events") {
            let events = XBLiveEvent.currentEvents(from: snapshot?.events ?? [])
            if events.isEmpty {
                ProfileEmptyRow(title: "No events starting in the next 24 hours", systemImage: "calendar")
            } else {
                ForEach(events) { event in
                    NavigationLink {
                        ProfileEventDetailView(event: event)
                    } label: {
                        ProfileEventRow(event: event)
                    }
                }
            }
        }
        .dukeXThemedListRowBackground()
    }

    private var gamertagOnlySections: some View {
        Group {
            Section("Account") {
                Text("This profile is using local gamertag lookup only. Sign in with an Insignia account to sync friends, messages, active games, events, and xb.live profile details.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .dukeXThemedListRowBackground()

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
            .dukeXThemedListRowBackground()

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
        .dukeXThemedListRowBackground()
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
        .dukeXThemedListRowBackground()
    }

    private var poweredBySection: some View {
        Section {
            VStack(spacing: 8) {
                if profileStore.isSignedIn {
                    Button(role: .destructive, action: signOut) {
                        Text("Sign Out")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.red.opacity(0.88), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel("Sign Out")
                }

                JustifiedProfileFootnote(
                    text: "DukeX’s profile features are powered by xb.live and Insignia services. An Insignia account and xb.live profile setup may be required to access the full functionality of the Profiles section."
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        }
        .dukeXThemedListRowBackground()
    }

    private func playTimeText(_ minutes: Double) -> String {
        let hours = minutes / 60.0
        if hours >= 10 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
    }

    private func playtimeSummaryText(totalMinutes: Double?, gameCount: Int) -> String {
        if let totalMinutes {
            return playTimeText(totalMinutes)
        }
        if gameCount > 0 {
            return countText(gameCount)
        }
        return "Not Synced"
    }

    private var friendSortMode: ProfileFriendSortMode {
        ProfileFriendSortMode(rawValue: friendSortModeRawValue) ?? .favorites
    }

    private var friendSortModeBinding: Binding<ProfileFriendSortMode> {
        Binding(
            get: { friendSortMode },
            set: { friendSortModeRawValue = $0.rawValue }
        )
    }

    private func toggleFavorite(_ friend: InsigniaFriend) {
        let key = ProfileFriendFavorites.key(for: friend)
        if favoriteFriendKeys.contains(key) {
            favoriteFriendKeys.remove(key)
        } else {
            favoriteFriendKeys.insert(key)
        }
        ProfileFriendFavorites.save(favoriteFriendKeys)
    }

    private func toggleSocialFavorite(_ friend: XBLiveSocialFriend) {
        let key = ProfileFriendFavorites.key(for: friend)
        if favoriteFriendKeys.contains(key) {
            favoriteFriendKeys.remove(key)
        } else {
            favoriteFriendKeys.insert(key)
        }
        ProfileFriendFavorites.save(favoriteFriendKeys)
    }

    private func countText(_ count: Int) -> String {
        count == 0 ? "None" : "\(count)"
    }

    private func mergedFriendsCount(insigniaFriends: [InsigniaFriend]) -> Int {
        let insigniaKeys = Set(insigniaFriends.map(\.key))
        let xbLiveOnlyCount = socialStore.messageableFriends.filter { friend in
            let keys = [
                friend.username,
                friend.displayName ?? ""
            ]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }

            return keys.allSatisfy { !insigniaKeys.contains($0) }
        }.count

        return insigniaFriends.count + xbLiveOnlyCount
    }

    private func unreadMessagesText(legacyMessages: [InsigniaMessage]) -> String {
        let count = socialStore.unreadCount + profileStore.unviewedMessages(from: legacyMessages).count
        return "\(count) Unread"
    }

    private func pendingMessagesText(_ count: Int) -> String {
        count == 0 ? "None" : "\(count) Pending"
    }

    private func dukeXDownloadCountState(for session: InsigniaProfileSession) -> DukeXDownloadCountState {
        guard maftyDownloadCountUnlocked,
              session.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Mafty") == .orderedSame else {
            return .hidden
        }

        return maftyDownloadCountState
    }

    private func handleProfileAvatarTap(for session: InsigniaProfileSession) {
        guard session.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Mafty") == .orderedSame else {
            maftyAvatarTapCount = 0
            return
        }

        maftyAvatarTapCount += 1

        guard maftyAvatarTapCount >= 3 else {
            return
        }

        maftyAvatarTapCount = 0
        maftyDownloadCountUnlocked = true
        refreshMaftyDownloadCount()
    }

    private func refreshMaftyDownloadCount() {
        maftyDownloadCountTask?.cancel()
        maftyDownloadCountState = .loading
        maftyDownloadCountTask = Task {
            do {
                let totalDownloads = try await DukeXReleaseStatsService.fetchTotalDownloads()
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    maftyDownloadCountState = .loaded(totalDownloads)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    maftyDownloadCountState = .failed
                }
            }
        }
    }
}

enum DukeXReleaseStatsService {
    private static let releasesURL = URL(string: "https://api.github.com/repos/MaftyManicEMU/DukeX/releases")!

    static func fetchTotalDownloads() async throws -> Int {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DukeX", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ServiceError.unavailable
        }

        return try JSONDecoder()
            .decode([GitHubRelease].self, from: data)
            .reduce(0) { releaseTotal, release in
                releaseTotal + release.assets.reduce(0) { assetTotal, asset in
                    assetTotal + asset.downloadCount
                }
            }
    }

    private struct GitHubRelease: Decodable {
        let assets: [GitHubReleaseAsset]
    }

    private struct GitHubReleaseAsset: Decodable {
        let downloadCount: Int

        enum CodingKeys: String, CodingKey {
            case downloadCount = "download_count"
        }
    }

    enum ServiceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "DukeX release download stats are unavailable."
        }
    }
}

private struct JustifiedProfileFootnote: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 3
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.88
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        applyText(to: label)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        applyText(to: uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        uiView.preferredMaxLayoutWidth = width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let maxHeight = UIFont.preferredFont(forTextStyle: .footnote).lineHeight * 3.0 + 2.0
        return CGSize(width: width, height: min(size.height, maxHeight))
    }

    private func applyText(to label: UILabel) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified
        paragraphStyle.lineBreakMode = .byTruncatingTail

        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
