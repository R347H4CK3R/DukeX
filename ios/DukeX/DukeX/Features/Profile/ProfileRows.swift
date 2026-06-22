import Charts
import SwiftUI
import UIKit

enum ProfileFriendSortMode: String, CaseIterable, Identifiable {
    case favorites
    case alphabetical
    case recentActivity

    static let defaultsKey = "DukeXProfileFriendSortMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites:
            return "Favorites"
        case .alphabetical:
            return "A-Z"
        case .recentActivity:
            return "Recent"
        }
    }
}

enum ProfileEventMode: String, CaseIterable, Identifiable {
    case today
    case paid
    case tournaments

    static let defaultsKey = "DukeXProfileEventMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today's Events"
        case .paid:
            return "Paid Events"
        case .tournaments:
            return "Tournaments"
        }
    }

    var emptyTitle: String {
        switch self {
        case .today:
            return "No events starting in the next 24 hours"
        case .paid:
            return "No paid events listed"
        case .tournaments:
            return "No tournaments in the next 30 days"
        }
    }

    var requiresPaidEventDisclaimer: Bool {
        switch self {
        case .today:
            return false
        case .paid, .tournaments:
            return true
        }
    }
}

enum ProfileActivityMode: String, CaseIterable, Identifiable {
    case activeGames
    case twentyFourHour
    case sevenDay

    static let defaultsKey = "DukeXProfileActivityMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeGames:
            return "Active Games"
        case .twentyFourHour:
            return "24 Hour"
        case .sevenDay:
            return "7 Day"
        }
    }

    var chartTitle: String {
        switch self {
        case .activeGames:
            return "Active Games"
        case .twentyFourHour:
            return "24 Hour Activity"
        case .sevenDay:
            return "7 Day Activity"
        }
    }

    var xAxisMarkCount: Int {
        switch self {
        case .activeGames:
            return 0
        case .twentyFourHour:
            return 5
        case .sevenDay:
            return 4
        }
    }
}

enum ProfileFriendFavorites {
    private static let defaultsKey = "DukeXProfileFriendFavorites"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    static func save(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys).sorted(), forKey: defaultsKey)
    }

    static func key(for friend: InsigniaFriend) -> String {
        friend.key
    }

    static func key(for friend: XBLiveSocialFriend) -> String {
        "xblive:\(friend.key)"
    }
}

struct ProfileHeaderRow: View {
    private let avatarSize: CGFloat = 48

    let session: InsigniaProfileSession
    let snapshot: InsigniaAuthenticatedSnapshot?
    let profileImage: UIImage?
    let dukeXDownloadCountState: DukeXDownloadCountState
    let avatarTapAction: () -> Void
    let changeProfileImage: () -> Void
    let clearProfileImage: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            avatar
                .contentShape(Circle())
                .onTapGesture(perform: avatarTapAction)
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

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(session.gamertag)
                        .font(.headline)
                        .lineLimit(1)

                    if session.isAuthenticated {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.accentColor)
                            .imageScale(.small)
                    }
                }

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)

                if let gamerscore = snapshot?.xbProfile?.achievementScore {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy")
                            .imageScale(.small)
                        Text("\(gamerscore) Gamerscore")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if dukeXDownloadCountState != .hidden {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .imageScale(.small)
                        Text(dukeXDownloadCountText)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 78)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = snapshot?.xbProfile?.avatarURL {
            RemoteCircleImage(url: avatarURL, fallbackInitial: initial)
                .frame(width: avatarSize, height: avatarSize)
        } else if let profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
        } else {
            InitialAvatar(initial: initial)
                .frame(width: avatarSize, height: avatarSize)
        }
    }

    private var statusText: String {
        guard let snapshot else {
            return "Not Synced"
        }

        if let currentGame = snapshot.xbProfile?.currentGame ?? snapshot.profile?.game,
           !currentGame.isEmpty {
            let duration = snapshot.profile?.timeOnline
            return duration.map { "Playing \(currentGame) for \($0)" } ?? "Playing \(currentGame)"
        }

        if snapshot.xbProfile?.isOnline == true || snapshot.profile?.isOnline == true {
            return "Online"
        }

        if let lastGame = snapshot.xbProfile?.lastPlayedGame {
            return "Last played \(lastGame)"
        }

        return "Offline"
    }

    private var statusColor: Color {
        if snapshot?.xbProfile?.isOnline == true || snapshot?.profile?.isOnline == true {
            return .green
        }
        return .secondary
    }

    private var initial: String {
        String(session.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var dukeXDownloadCountText: String {
        switch dukeXDownloadCountState {
        case .hidden:
            return ""
        case .loading:
            return "Loading DukeX downloads..."
        case .loaded(let count):
            return "\(count.formatted(.number)) DukeX Downloads"
        case .failed:
            return "DukeX downloads unavailable"
        }
    }
}

struct ProfileInfoRow: View {
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

struct ProfileFriendRow: View {
    let friend: InsigniaFriend
    let profile: XBLiveFriendProfile?
    let customProfileImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ProfileCircleImage(image: customProfileImage, url: profile?.avatarURL, fallbackInitial: initial)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.gamertag)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Circle()
                        .fill(isOnline ? Color.green : Color.secondary.opacity(0.55))
                        .frame(width: 7, height: 7)
                }

                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let imageURL = profile?.lastPlayedImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.secondary.opacity(0.18)
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(minHeight: 54)
    }

    private var statusLine: String {
        ProfileFriendOnlineText.statusLine(friend: friend, profile: profile)
    }

    private var isOnline: Bool {
        ProfileFriendOnlineText.isOnline(friend: friend, profile: profile)
    }

    private var initial: String {
        String(friend.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

private enum ProfileFriendListEntry: Identifiable {
    case insignia(InsigniaFriend)
    case xbLive(XBLiveSocialFriend)

    var id: String {
        switch self {
        case .insignia(let friend):
            return "insignia-\(friend.key)"
        case .xbLive(let friend):
            return "xblive-\(friend.key)"
        }
    }
}

struct ProfileFriendsView: View {
    @ObservedObject var profileStore: InsigniaProfileStore
    @ObservedObject var socialStore: XBLiveSocialStore
    @Binding var sortMode: ProfileFriendSortMode
    let favoriteFriendKeys: Set<String>
    let toggleFavorite: (InsigniaFriend) -> Void
    let toggleSocialFavorite: (XBLiveSocialFriend) -> Void
    let changeFriendProfileImage: (InsigniaFriend) -> Void
    let changeSocialFriendProfileImage: (XBLiveSocialFriend) -> Void
    let installedGames: [LibraryFile]
    let inviteEligibleGames: [LibraryFile]
    let currentUserAchievements: XBLiveAchievementsSnapshot?
    let currentUserGamesPlayed: [XBLiveGamePlayed]
    let launchGameFromInvite: (LibraryFile) -> Void

    @State private var isAddFriendPresented = false

    var body: some View {
        List {
            pendingRequestsSection

            Section("Friends") {
                ProfileFriendSortPickerRow(selection: $sortMode)
                    .listRowSeparator(.hidden)

                if friendEntries.isEmpty {
                    if socialStore.isRefreshingFriends && friends.isEmpty {
                        ProfileSocialLoadingRow(title: "Loading friends...")
                    } else {
                        ProfileEmptyRow(title: emptyFriendsTitle, systemImage: emptyFriendsSystemImage)
                    }
                } else {
                    ForEach(friendEntries) { entry in
                        friendEntryRow(entry)
                    }
                }
            }
            .dukeXThemedListRowBackground()

            if !socialStore.blockedUsers.isEmpty {
                Section("Blocked") {
                    ForEach(socialStore.blockedUsers, id: \.self) { username in
                        HStack {
                            Label(username, systemImage: "hand.raised")
                            Spacer()
                            Button("Unblock") {
                                Task {
                                    await socialStore.unblockUser(username)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(minHeight: 44)
                    }
                }
                .dukeXThemedListRowBackground()
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddFriendPresented = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add Friend")
            }
        }
        .task {
            profileStore.refresh()
            await socialStore.refreshFriends()
        }
        .refreshable {
            profileStore.refresh()
            await socialStore.refreshFriends()
        }
        .sheet(isPresented: $isAddFriendPresented) {
            NavigationStack {
                ProfileSocialFriendRequestComposer(socialStore: socialStore)
            }
        }
        .alert(item: $socialStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var pendingRequestsSection: some View {
        Section("Pending Requests") {
            if socialStore.incomingRequests.isEmpty && socialStore.outgoingRequests.isEmpty {
                ProfileInfoRow(
                    title: "Pending Friend Requests",
                    value: "0",
                    detail: "No pending XB.Live requests",
                    systemImage: "person.crop.circle.badge.plus"
                )
            } else {
                ForEach(socialStore.incomingRequests) { request in
                    ProfileSocialFriendRequestRow(request: request, direction: .incoming) {
                        Task {
                            await socialStore.acceptFriendRequest(from: request.username)
                        }
                    } secondaryAction: {
                        Task {
                            await socialStore.declineFriendRequest(from: request.username)
                        }
                    }
                }

                ForEach(socialStore.outgoingRequests) { request in
                    ProfileSocialFriendRequestRow(
                        request: request,
                        direction: .outgoing,
                        primaryAction: {
                            Task {
                                await socialStore.cancelFriendRequest(to: request.username)
                            }
                        },
                        secondaryAction: nil
                    )
                }
            }
        }
        .dukeXThemedListRowBackground()
    }

    @ViewBuilder
    private func friendEntryRow(_ entry: ProfileFriendListEntry) -> some View {
        switch entry {
        case .insignia(let friend):
            NavigationLink {
                ProfileFriendDetailView(
                    friend: friend,
                    profile: friendProfiles[friend.key],
                    customProfileImage: friendProfileImages[friend.key],
                    supportedGames: supportedGames,
                    socialStore: socialStore,
                    socialFriend: socialFriend(for: friend),
                    legacyMessages: legacyMessages,
                    markLegacyMessageViewed: profileStore.markMessageViewed,
                    installedGames: installedGames,
                    inviteEligibleGames: inviteEligibleGames,
                    currentUserAchievements: currentUserAchievements,
                    currentUserGamesPlayed: currentUserGamesPlayed,
                    launchGameFromInvite: launchGameFromInvite,
                    changeProfileImage: { changeFriendProfileImage(friend) }
                )
            } label: {
                ProfileFriendRow(
                    friend: friend,
                    profile: friendProfiles[friend.key],
                    customProfileImage: friendProfileImages[friend.key]
                )
            }
            .swipeActions(edge: .trailing) {
                Button {
                    changeFriendProfileImage(friend)
                } label: {
                    Label("Set Picture", systemImage: "photo")
                }
                .tint(Color.accentColor)

                Button {
                    toggleFavorite(friend)
                } label: {
                    Label(isFavorite(friend) ? "Unfavorite" : "Favorite",
                          systemImage: isFavorite(friend) ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
            .contextMenu {
                Button {
                    changeFriendProfileImage(friend)
                } label: {
                    Label("Set Picture", systemImage: "photo")
                }

                Button {
                    toggleFavorite(friend)
                } label: {
                    Label(isFavorite(friend) ? "Unfavorite" : "Favorite",
                          systemImage: isFavorite(friend) ? "star.slash" : "star")
                }
            }

        case .xbLive(let friend):
            NavigationLink {
                ProfileXBLiveFriendDetailView(
                    socialStore: socialStore,
                    friend: friend,
                    customProfileImage: friendProfileImages[friend.key],
                    supportedGames: supportedGames,
                    legacyMessages: legacyMessages,
                    markLegacyMessageViewed: profileStore.markMessageViewed,
                    installedGames: installedGames,
                    inviteEligibleGames: inviteEligibleGames,
                    currentUserAchievements: currentUserAchievements,
                    currentUserGamesPlayed: currentUserGamesPlayed,
                    launchGameFromInvite: launchGameFromInvite,
                    changeProfileImage: { changeSocialFriendProfileImage(friend) }
                )
            } label: {
                ProfileSocialFriendRow(
                    friend: friend,
                    profile: socialFriendProfile(for: friend),
                    customProfileImage: friendProfileImages[friend.key]
                )
            }
            .swipeActions(edge: .trailing) {
                Button {
                    changeSocialFriendProfileImage(friend)
                } label: {
                    Label("Set Picture", systemImage: "photo")
                }
                .tint(Color.accentColor)

                Button {
                    toggleSocialFavorite(friend)
                } label: {
                    Label(isFavorite(friend) ? "Unfavorite" : "Favorite",
                          systemImage: isFavorite(friend) ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
            .contextMenu {
                Button {
                    changeSocialFriendProfileImage(friend)
                } label: {
                    Label("Set Picture", systemImage: "photo")
                }

                Button {
                    toggleSocialFavorite(friend)
                } label: {
                    Label(isFavorite(friend) ? "Unfavorite" : "Favorite",
                          systemImage: isFavorite(friend) ? "star.slash" : "star")
                }
            }
        }
    }

    private var friends: [InsigniaFriend] {
        profileStore.authenticatedSnapshot?.friends ?? []
    }

    private var legacyMessages: [InsigniaMessage] {
        profileStore.authenticatedSnapshot?.messages ?? []
    }

    private var friendProfiles: [String: XBLiveFriendProfile] {
        profileStore.authenticatedSnapshot?.friendProfiles ?? [:]
    }

    private var supportedGames: [InsigniaSupportedGame] {
        profileStore.authenticatedSnapshot?.supportedGames ?? []
    }

    private var friendProfileImages: [String: UIImage] {
        profileStore.friendProfileImages
    }

    private var friendEntries: [ProfileFriendListEntry] {
        switch sortMode {
        case .favorites:
            return allFriendEntries
                .filter(isFavorite)
                .sorted(by: activityThenNameSort)
        case .alphabetical:
            return allFriendEntries.sorted(by: entryNameSort)
        case .recentActivity:
            return allFriendEntries.sorted(by: activityThenNameSort)
        }
    }

    private var allFriendEntries: [ProfileFriendListEntry] {
        friends.map(ProfileFriendListEntry.insignia) +
            socialOnlyFriends.map(ProfileFriendListEntry.xbLive)
    }

    private var socialOnlyFriends: [XBLiveSocialFriend] {
        socialStore.messageableFriends.filter { socialFriend in
            socialMatchingKeys(for: socialFriend).allSatisfy { !insigniaFriendKeys.contains($0) }
        }
    }

    private var insigniaFriendKeys: Set<String> {
        Set(friends.map(\.key))
    }

    private var emptyFriendsTitle: String {
        switch sortMode {
        case .favorites:
            return "No favorite or XB.Live-only friends"
        case .alphabetical, .recentActivity:
            return "No friends synced"
        }
    }

    private var emptyFriendsSystemImage: String {
        switch sortMode {
        case .favorites:
            return "star"
        case .alphabetical, .recentActivity:
            return "person.2"
        }
    }

    private func isFavorite(_ friend: InsigniaFriend) -> Bool {
        favoriteFriendKeys.contains(ProfileFriendFavorites.key(for: friend))
    }

    private func isFavorite(_ friend: XBLiveSocialFriend) -> Bool {
        favoriteFriendKeys.contains(ProfileFriendFavorites.key(for: friend))
    }

    private func isFavorite(_ entry: ProfileFriendListEntry) -> Bool {
        switch entry {
        case .insignia(let friend):
            return isFavorite(friend)
        case .xbLive(let friend):
            return isFavorite(friend)
        }
    }

    private func friendNameSort(_ lhs: InsigniaFriend, _ rhs: InsigniaFriend) -> Bool {
        lhs.gamertag.localizedStandardCompare(rhs.gamertag) == .orderedAscending
    }

    private func socialFriendNameSort(_ lhs: XBLiveSocialFriend, _ rhs: XBLiveSocialFriend) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func entryNameSort(_ lhs: ProfileFriendListEntry, _ rhs: ProfileFriendListEntry) -> Bool {
        entryName(lhs).localizedStandardCompare(entryName(rhs)) == .orderedAscending
    }

    private func activityThenNameSort(_ lhs: ProfileFriendListEntry, _ rhs: ProfileFriendListEntry) -> Bool {
        let lhsActivity = activitySortValue(for: lhs)
        let rhsActivity = activitySortValue(for: rhs)
        if lhsActivity != rhsActivity {
            return lhsActivity > rhsActivity
        }
        return entryNameSort(lhs, rhs)
    }

    private func activitySortValue(for friend: InsigniaFriend) -> Double {
        let profile = friendProfiles[friend.key]
        if ProfileFriendOnlineText.isOnline(friend: friend, profile: profile) {
            return .greatestFiniteMagnitude
        }
        if let profile {
            return profile.lastOnlineAt ?? 0
        }
        return friend.lastSeenAt ?? 0
    }

    private func activitySortValue(for entry: ProfileFriendListEntry) -> Double {
        switch entry {
        case .insignia(let friend):
            return activitySortValue(for: friend)
        case .xbLive(let friend):
            let profile = socialFriendProfile(for: friend)
            if profile?.isOnline == true ||
                profile?.currentGame?.nilIfEmpty != nil ||
                friend.isOnline == true ||
                friend.currentGame?.nilIfEmpty != nil {
                return .greatestFiniteMagnitude
            }
            return profile?.lastOnlineAt ?? friend.lastOnlineAt ?? 0
        }
    }

    private func entryName(_ entry: ProfileFriendListEntry) -> String {
        switch entry {
        case .insignia(let friend):
            return friend.gamertag
        case .xbLive(let friend):
            return friend.title
        }
    }

    private func socialFriend(for friend: InsigniaFriend) -> XBLiveSocialFriend? {
        socialStore.messageableFriends.first { socialFriend in
            socialMatchingKeys(for: socialFriend).contains(friend.key)
        }
    }

    private func socialFriendProfile(for friend: XBLiveSocialFriend) -> XBLiveFriendProfile? {
        socialStore.messageableFriendProfiles[friend.key]
    }

    private func socialMatchingKeys(for friend: XBLiveSocialFriend) -> Set<String> {
        Set([
            friend.username,
            friend.displayName ?? ""
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }
}

private struct ProfileFriendSortPickerRow: View {
    @Binding var selection: ProfileFriendSortMode

    var body: some View {
        ProfileFriendSortPicker(selection: $selection)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(height: GameLibraryGridMetrics.compactControlHeight + 12)
    }
}

private struct ProfileFriendSortPicker: View {
    @Binding var selection: ProfileFriendSortMode

    var body: some View {
        Picker("Sort Friends", selection: $selection) {
            ForEach(ProfileFriendSortMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: GameLibraryGridMetrics.compactControlHeight)
        .pickerStyle(.segmented)
        .accessibilityLabel("Sort Friends")
    }
}

struct ProfileEventModePickerRow: View {
    @Binding var selection: ProfileEventMode

    var body: some View {
        Picker("Event Category", selection: $selection) {
            ForEach(ProfileEventMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: GameLibraryGridMetrics.compactControlHeight)
        .pickerStyle(.segmented)
        .accessibilityLabel("Event Category")
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(height: GameLibraryGridMetrics.compactControlHeight + 12)
    }
}

struct ProfileActivityModePickerRow: View {
    @Binding var selection: ProfileActivityMode

    var body: some View {
        Picker("Activity Category", selection: $selection) {
            ForEach(ProfileActivityMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: GameLibraryGridMetrics.compactControlHeight)
        .pickerStyle(.segmented)
        .accessibilityLabel("Activity Category")
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(height: GameLibraryGridMetrics.compactControlHeight + 12)
    }
}

private enum ProfileFriendOnlineText {
    static func isOnline(friend: InsigniaFriend, profile: XBLiveFriendProfile?) -> Bool {
        if let profile {
            return profile.isOnline == true || profile.currentGame?.nilIfEmpty != nil
        }
        return friend.isOnline || friend.game?.nilIfEmpty != nil
    }

    static func statusLine(friend: InsigniaFriend, profile: XBLiveFriendProfile?) -> String {
        if isOnline(friend: friend, profile: profile) {
            if let game = activeGame(friend: friend, profile: profile) {
                return "Online in \(game)"
            }
            return "Online"
        }

        if let profile {
            if let lastOnlineAt = profile.lastOnlineAt,
               let relativeText = relativeLastOnlineText(from: lastOnlineAt) {
                return "Last Online: \(relativeText)"
            }
            return "Last Online: Unknown"
        }

        if let lastSeenAt = friend.lastSeenAt,
           let relativeText = relativeLastOnlineText(from: lastSeenAt) {
            return "Last Online: \(relativeText)"
        }

        if let lastSeen = friend.lastSeen?.nilIfEmpty {
            return "Last Online: \(normalizedLastSeenText(lastSeen))"
        }

        return "Last Online: Unknown"
    }

    private static func activeGame(friend: InsigniaFriend, profile: XBLiveFriendProfile?) -> String? {
        if let profile {
            return profile.currentGame?.nilIfEmpty
        }
        return friend.game?.nilIfEmpty
    }

    private static func normalizedLastSeenText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for prefix in ["last seen", "last online"] where lowered.hasPrefix(prefix) {
            let suffix = trimmed.dropFirst(prefix.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: " :").union(.whitespacesAndNewlines))
            if !suffix.isEmpty {
                return String(suffix)
            }
        }
        return trimmed
    }

    private static func relativeLastOnlineText(from timestamp: Double) -> String? {
        guard timestamp > 0 else {
            return nil
        }

        var epochSeconds = timestamp
        if epochSeconds > 9_999_999_999 {
            epochSeconds /= 1_000
        }

        let elapsedSeconds = max(0, Date().timeIntervalSince1970 - epochSeconds)
        let minutes = max(1, Int(elapsedSeconds / 60))
        if minutes < 60 {
            return "\(minutes) \(unit("minute", count: minutes)) ago"
        }

        let hours = max(1, Int(elapsedSeconds / 3_600))
        if hours < 24 {
            return "\(hours) \(unit("hour", count: hours)) ago"
        }

        let days = max(1, Int(elapsedSeconds / 86_400))
        return "\(days) \(unit("day", count: days)) ago"
    }

    private static func unit(_ singular: String, count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }
}

struct ProfileGameRow: View {
    let game: InsigniaProfileGame

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: game.iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(game.lastPlayed ?? "Last played unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 50)
    }
}

struct ProfileActiveGameRow: View {
    let game: InsigniaActiveGame

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: game.iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                        Image(systemName: "play.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(game.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(game.onlineUsers)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .frame(minHeight: 50)
    }
}

struct ProfileActivityChartRow: View {
    let points: [InsigniaActivityPoint]
    let mode: ProfileActivityMode

    private var chartPoints: [InsigniaActivityPoint] {
        points
            .filter { $0.timestamp > 0 }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var maximumOnlineCount: Int {
        chartPoints.map(\.onlineCount).max() ?? 0
    }

    private var yUpperBound: Int {
        max(1, Int((Double(maximumOnlineCount) * 1.12).rounded(.up)))
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = chartPoints.first?.date,
              let last = chartPoints.last?.date else {
            let now = Date()
            return now.addingTimeInterval(-3_600)...now
        }

        guard first < last else {
            return first.addingTimeInterval(-3_600)...first.addingTimeInterval(3_600)
        }

        return first...last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(mode.chartTitle, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text("Peak \(maximumOnlineCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Chart(chartPoints) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Users Online", point.onlineCount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.34),
                            Color.accentColor.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Users Online", point.onlineCount)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0...yUpperBound)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: mode.xAxisMarkCount)) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(for: date))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) {
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel()
                        .foregroundStyle(.secondary)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.black.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: 220)
        }
        .padding(.vertical, 8)
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .autoupdatingCurrent
        switch mode {
        case .activeGames:
            return ""
        case .twentyFourHour:
            formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        case .sevenDay:
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        }
        return formatter.string(from: date)
    }
}

struct ProfileMessageRow: View {
    let message: InsigniaMessage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.type)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
    }

    private var detail: String {
        let parts = [
            "From \(message.sender)",
            message.game,
            message.sentAt
        ].compactMap { $0?.nilIfEmpty }

        return parts.joined(separator: " - ")
    }

    private var iconName: String {
        if message.type.localizedCaseInsensitiveContains("request") {
            return "person.crop.circle.badge.plus"
        }
        if message.type.localizedCaseInsensitiveContains("invite") {
            return "gamecontroller"
        }
        return "envelope"
    }
}

struct ProfileMessagesView: View {
    @ObservedObject var profileStore: InsigniaProfileStore
    let messages: [InsigniaMessage]

    var body: some View {
        List {
            Section("Messages") {
                let pendingMessages = profileStore.unviewedMessages(from: messages)
                if pendingMessages.isEmpty {
                    ProfileEmptyRow(title: "No pending messages", systemImage: "envelope")
                } else {
                    ForEach(pendingMessages) { message in
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
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
    }
}

struct ProfilePlaytimeView: View {
    let totalMinutes: Double?
    let games: [XBLiveGamePlayed]

    var body: some View {
        List {
            Section("Total") {
                if let totalMinutes {
                    ProfileInfoRow(title: "Total Playtime",
                                   value: Self.playTimeText(totalMinutes),
                                   systemImage: "timer")
                } else {
                    ProfileEmptyRow(title: "No total playtime synced", systemImage: "timer")
                }
            }
            .dukeXThemedListRowBackground()

            Section("By Game") {
                if sortedGames.isEmpty {
                    ProfileEmptyRow(title: "No per-game playtime synced", systemImage: "gamecontroller")
                } else {
                    ForEach(sortedGames) { game in
                        ProfilePlaytimeGameRow(game: game)
                    }
                }
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("Playtime")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
    }

    private var sortedGames: [XBLiveGamePlayed] {
        games.sorted { lhs, rhs in
            let lhsMinutes = lhs.totalMinutes ?? -1
            let rhsMinutes = rhs.totalMinutes ?? -1
            if lhsMinutes != rhsMinutes {
                return lhsMinutes > rhsMinutes
            }

            let lhsLastPlayedAt = Self.normalizedTimestamp(lhs.lastPlayedAt) ?? -1
            let rhsLastPlayedAt = Self.normalizedTimestamp(rhs.lastPlayedAt) ?? -1
            if lhsLastPlayedAt != rhsLastPlayedAt {
                return lhsLastPlayedAt > rhsLastPlayedAt
            }

            return lhs.gameName.localizedCaseInsensitiveCompare(rhs.gameName) == .orderedAscending
        }
    }

    private static func playTimeText(_ minutes: Double) -> String {
        let hours = minutes / 60.0
        if hours >= 10 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
    }

    private static func normalizedTimestamp(_ timestamp: Double?) -> Double? {
        guard let timestamp, timestamp > 0 else {
            return nil
        }
        return timestamp > 9_999_999_999 ? timestamp / 1_000.0 : timestamp
    }
}

struct ProfilePlaytimeGameRow: View {
    let game: XBLiveGamePlayed

    var body: some View {
        HStack(spacing: 12) {
            ProfileGameIcon(
                url: iconDisplay.url,
                assetName: iconDisplay.assetName,
                systemImage: iconDisplay.systemImage
            )
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.gameName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let totalMinutes = game.totalMinutes {
                Text(Self.playTimeText(totalMinutes))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 50)
    }

    private var iconDisplay: ProfileGameIconDisplay {
        ProfileGameIconDisplayResolver.display(
            title: game.gameName,
            titleID: game.titleId,
            primaryURL: game.imageURL
        )
    }

    private var detailText: String {
        if let date = Self.lastPlayedDate(from: game.lastPlayedAt) {
            return "Last Played: \(Self.lastPlayedFormatter.string(from: date))"
        }
        if game.totalMinutes != nil {
            return "Tracked by xb.live"
        }
        return "Playtime unavailable"
    }

    private static func playTimeText(_ minutes: Double) -> String {
        let hours = minutes / 60.0
        if hours >= 10 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
    }

    private static func lastPlayedDate(from timestamp: Double?) -> Date? {
        guard let timestamp, timestamp > 0 else {
            return nil
        }

        let seconds = timestamp > 9_999_999_999 ? timestamp / 1_000.0 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }

    private static let lastPlayedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct ProfileAchievementsSummaryRow: View {
    let countText: String

    var body: some View {
        ProfileInfoRow(
            title: "Achievements",
            value: countText,
            systemImage: "medal"
        )
    }
}

struct ProfileFriendDetailView: View {
    let friend: InsigniaFriend
    let profile: XBLiveFriendProfile?
    let customProfileImage: UIImage?
    let supportedGames: [InsigniaSupportedGame]
    @ObservedObject var socialStore: XBLiveSocialStore
    let socialFriend: XBLiveSocialFriend?
    let legacyMessages: [InsigniaMessage]
    let markLegacyMessageViewed: (InsigniaMessage) -> Void
    let installedGames: [LibraryFile]
    let inviteEligibleGames: [LibraryFile]
    let currentUserAchievements: XBLiveAchievementsSnapshot?
    let currentUserGamesPlayed: [XBLiveGamePlayed]
    let launchGameFromInvite: (LibraryFile) -> Void
    let changeProfileImage: () -> Void

    @State private var isComposePresented = false
    @State private var isRemoveConfirmationPresented = false
    @State private var isBlockConfirmationPresented = false
    @State private var reportTarget: ProfileSocialReportTarget?
    @State private var liveProfile: XBLiveFriendProfile?
    @State private var isLoadingLiveProfile = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    ProfileCircleImage(image: customProfileImage, url: effectiveProfile?.avatarURL, fallbackInitial: initial)
                        .frame(width: 74, height: 74)
                        .contextMenu {
                            Button(action: changeProfileImage) {
                                Label("Set Picture", systemImage: "photo")
                            }
                        }

                    VStack(spacing: 4) {
                        Text(friend.gamertag)
                            .font(.title3.weight(.semibold))
                        Text(statusLine)
                            .font(.subheadline)
                            .foregroundStyle(isOnline ? .green : .secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .dukeXThemedListRowBackground()

            Section("Profile") {
                if let score = effectiveProfile?.achievementScore {
                    ProfileInfoRow(title: "Gamerscore", value: "\(score)", systemImage: "trophy")
                }

                NavigationLink {
                    ProfileAchievementsView(
                        snapshot: effectiveProfile?.achievements,
                        profileScore: effectiveProfile?.achievementScore,
                        profileCount: effectiveProfile?.achievementCount,
                        supportedGames: supportedGames,
                        gamesPlayed: effectiveProfile?.gamesPlayed ?? []
                    )
                } label: {
                    ProfileInfoRow(title: "Achievements", value: achievementsSummaryText, systemImage: "medal")
                }

                NavigationLink {
                    ProfilePlaytimeView(
                        totalMinutes: effectiveProfile?.totalMinutes,
                        games: effectiveProfile?.gamesPlayed ?? []
                    )
                } label: {
                    ProfileInfoRow(title: "Play Time", value: playtimeSummaryText, systemImage: "timer")
                }

                if let lastPlayed = effectiveProfile?.lastPlayedGame {
                    ProfileInfoRow(title: "Last Played", value: lastPlayed, systemImage: "clock")
                }
            }
            .dukeXThemedListRowBackground()

            if let socialFriend {
                Section("XB.Live") {
                    NavigationLink {
                        ProfileSocialThreadView(
                            socialStore: socialStore,
                            username: socialFriend.username,
                            legacyMessages: legacyMessages,
                            friendProfileImages: threadProfileImages,
                            friendProfiles: threadFriendProfiles,
                            socialFriends: threadSocialFriends,
                            markLegacyMessageViewed: markLegacyMessageViewed,
                            installedGames: installedGames,
                            inviteEligibleGames: inviteEligibleGames,
                            currentUserAchievements: currentUserAchievements,
                            currentUserGamesPlayed: currentUserGamesPlayed,
                            launchGameFromInvite: launchGameFromInvite
                        )
                    } label: {
                        ProfileInfoRow(title: "Messages", value: "Open", systemImage: "bubble.left.and.bubble.right")
                    }

                    Button {
                        isComposePresented = true
                    } label: {
                        Label("New Message", systemImage: "square.and.pencil")
                    }
                }
                .dukeXThemedListRowBackground()

                Section("Moderation") {
                    Button {
                        reportTarget = ProfileSocialReportTarget(username: socialFriend.username)
                    } label: {
                        Label("Report User", systemImage: "flag")
                    }

                    Button(role: .destructive) {
                        isBlockConfirmationPresented = true
                    } label: {
                        Label("Block User", systemImage: "hand.raised")
                    }

                    Button(role: .destructive) {
                        isRemoveConfirmationPresented = true
                    } label: {
                        Label("Remove Friend", systemImage: "person.crop.circle.badge.minus")
                    }
                }
                .dukeXThemedListRowBackground()
            }
        }
        .navigationTitle(friend.gamertag)
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: changeProfileImage) {
                    Image(systemName: "photo")
                }
                .accessibilityLabel("Set Profile Picture")
            }
        }
        .sheet(isPresented: $isComposePresented) {
            NavigationStack {
                ProfileSocialComposeView(
                    socialStore: socialStore,
                    initialRecipient: socialFriend?.username ?? friend.gamertag
                )
            }
        }
        .sheet(item: $reportTarget) { target in
            NavigationStack {
                ProfileSocialReportView(target: target) { reason in
                    Task {
                        await socialStore.reportUser(target.username, reason: reason)
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove \(socialFriend?.title ?? friend.gamertag)?",
            isPresented: $isRemoveConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let socialFriend {
                Button("Remove Friend", role: .destructive) {
                    Task {
                        await socialStore.removeFriend(socialFriend.username)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                isRemoveConfirmationPresented = false
            }
        } message: {
            Text("This removes the XB.Live friendship and does not affect Insignia friends.")
        }
        .confirmationDialog(
            "Block \(socialFriend?.title ?? friend.gamertag)?",
            isPresented: $isBlockConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let socialFriend {
                Button("Block User", role: .destructive) {
                    Task {
                        await socialStore.blockUser(socialFriend.username)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                isBlockConfirmationPresented = false
            }
        } message: {
            Text("Blocked users can no longer message you on XB.Live.")
        }
        .task(id: friend.gamertag) {
            await loadLiveProfile()
        }
        .alert(item: $socialStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var statusLine: String {
        ProfileFriendOnlineText.statusLine(friend: friend, profile: effectiveProfile)
    }

    private var isOnline: Bool {
        ProfileFriendOnlineText.isOnline(friend: friend, profile: effectiveProfile)
    }

    private var initial: String {
        String(friend.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var threadProfileImages: [String: UIImage] {
        guard let customProfileImage else {
            return [:]
        }

        var images = [friend.key: customProfileImage]
        if let socialFriend {
            images[socialFriend.key] = customProfileImage
        }
        return images
    }

    private var threadFriendProfiles: [String: XBLiveFriendProfile] {
        guard let profile = effectiveProfile else {
            return [:]
        }

        var profiles = [friend.key: profile]
        if let socialFriend {
            profiles[socialFriend.key] = profile
        }
        return profiles
    }

    private var threadSocialFriends: [XBLiveSocialFriend] {
        socialFriend.map { [$0] } ?? []
    }

    private var achievementsSummaryText: String {
        effectiveProfile?.achievements?.summaryText ??
            effectiveProfile?.achievementCount.map(String.init) ??
            "Not Synced"
    }

    private var playtimeSummaryText: String {
        if let minutes = effectiveProfile?.totalMinutes {
            return playTimeText(minutes)
        }

        let games = effectiveProfile?.gamesPlayed ?? []
        if !games.isEmpty {
            return "\(games.count) Game\(games.count == 1 ? "" : "s")"
        }

        return "Not Synced"
    }

    private func playTimeText(_ minutes: Double) -> String {
        let hours = minutes / 60.0
        if hours >= 10 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
    }

    private var effectiveProfile: XBLiveFriendProfile? {
        liveProfile ?? profile
    }

    private func loadLiveProfile() async {
        guard !isLoadingLiveProfile else {
            return
        }

        isLoadingLiveProfile = true
        defer {
            isLoadingLiveProfile = false
        }

        let username = socialFriend?.username ?? friend.gamertag
        guard let xbProfile = try? await XBLiveService.fetchProfile(username: username) else {
            return
        }

        let existingProfile = effectiveProfile
        let games = (try? await XBLiveService.fetchGamesPlayed(username: username)) ??
            existingProfile?.gamesPlayed ??
            []
        let achievements = (try? await XBLiveService.fetchAchievements(username: username)) ??
            existingProfile?.achievements
        let lastGame = games.first { $0.gameName == xbProfile.lastPlayedGame } ?? games.first
        let isOnline = xbProfile.isOnline || friend.isOnline || friend.game?.nilIfEmpty != nil

        liveProfile = XBLiveFriendProfile(
            gamertag: friend.gamertag,
            avatarURLString: xbProfile.avatarURLString ?? existingProfile?.avatarURLString,
            isOnline: isOnline,
            lastState: xbProfile.lastState ?? friend.status,
            currentGame: xbProfile.currentGame ?? (isOnline ? friend.game : nil),
            lastPlayedGame: xbProfile.lastPlayedGame ?? lastGame?.gameName,
            lastPlayedAt: xbProfile.lastPlayedAt,
            lastOnlineAt: lastOnlineTimestamp(isOnline: isOnline, profile: xbProfile),
            lastCheckedAt: xbProfile.lastCheckedAt,
            achievementScore: xbProfile.achievementScore,
            achievementCount: xbProfile.achievementCount,
            totalMinutes: xbProfile.totalMinutes ?? totalMinutes(from: games),
            lastPlayedImageURLString: lastGame?.imageUrl ?? existingProfile?.lastPlayedImageURLString,
            gamesPlayed: games,
            achievements: achievements
        )
    }

    private func lastOnlineTimestamp(isOnline: Bool, profile: XBLiveProfileSnapshot) -> Double? {
        if isOnline {
            return profile.lastCheckedAt ?? profile.lastOnlineAt ?? friend.lastSeenAt ?? Date().timeIntervalSince1970
        }
        return profile.lastOnlineAt ?? profile.lastPlayedAt ?? friend.lastSeenAt
    }

    private func totalMinutes(from games: [XBLiveGamePlayed]) -> Double? {
        let minutes = games.compactMap(\.totalMinutes)
        guard !minutes.isEmpty else {
            return nil
        }
        return minutes.reduce(0, +)
    }
}

struct ProfileMessageDetailView: View {
    let message: InsigniaMessage

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message.type, systemImage: iconName)
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)

                    ProfileInfoRow(title: "From", value: message.sender, systemImage: "person")

                    if let game = message.game?.nilIfEmpty {
                        ProfileInfoRow(title: "Game", value: game, systemImage: "gamecontroller")
                    }

                    if let sentAt = message.sentAt?.nilIfEmpty {
                        ProfileInfoRow(title: "Sent", value: sentAt, systemImage: "clock")
                    }
                }
                .padding(.vertical, 6)
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
    }

    private var iconName: String {
        if message.type.localizedCaseInsensitiveContains("request") {
            return "person.crop.circle.badge.plus"
        }
        if message.type.localizedCaseInsensitiveContains("invite") {
            return "gamecontroller"
        }
        return "envelope"
    }
}

struct ProfileAchievementsView: View {
    let snapshot: XBLiveAchievementsSnapshot?
    let profileScore: Int?
    let profileCount: Int?
    let supportedGames: [InsigniaSupportedGame]
    let gamesPlayed: [XBLiveGamePlayed]

    var body: some View {
        List {
            Section {
                ProfileInfoRow(title: "Gamerscore",
                               value: "\(snapshot?.totalScore ?? profileScore ?? 0)",
                               systemImage: "trophy")
                ProfileInfoRow(title: "Achievements",
                               value: snapshot?.summaryText ?? profileCount.map(String.init) ?? "Not Synced",
                               systemImage: "medal")
            }
            .dukeXThemedListRowBackground()

            Section("Games") {
                if gameAchievementGroups.isEmpty {
                    ProfileEmptyRow(
                        title: achievementGroups.isEmpty ? "No achievements synced" : "No game achievements synced",
                        systemImage: "medal"
                    )
                } else {
                    ForEach(gameAchievementGroups) { group in
                        NavigationLink {
                            ProfileAchievementGameView(group: group)
                        } label: {
                            ProfileAchievementGameRow(group: group)
                        }
                    }
                }
            }
            .dukeXThemedListRowBackground()

            if !xblCoreAchievementGroups.isEmpty {
                Section("Cores") {
                    ForEach(xblCoreAchievementGroups) { group in
                        NavigationLink {
                            ProfileAchievementGameView(group: group)
                        } label: {
                            ProfileAchievementGameRow(group: group)
                        }
                    }
                }
                .dukeXThemedListRowBackground()
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
    }

    private var achievementGroups: [ProfileAchievementGameGroup] {
        let achievements = snapshot?.achievements ?? []
        let grouped = Dictionary(grouping: achievements, by: Self.groupKey(for:))

        return grouped
            .map { _, achievements in
                let sortedAchievements = achievements.sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                let first = sortedAchievements[0]
                let supportedGame = supportedGame(for: sortedAchievements)
                let coreKind = Self.coreAchievementKind(for: sortedAchievements)
                let isCoreAchievementGroup = coreKind != nil
                let groupTitle = coreKind?.title ?? supportedGame?.title ?? first.gameTitle?.nilIfEmpty ?? "Unknown Game"
                let groupTitleID = supportedGame?.titleID ?? first.gameTitleID
                let matchingPlayedGame = playedGame(for: sortedAchievements, supportedGame: supportedGame)
                let iconDisplay = ProfileGameIconDisplayResolver.display(
                    title: groupTitle,
                    titleID: groupTitleID,
                    primaryURL: isCoreAchievementGroup ? nil : (
                        XboxTitleIconCatalog.iconURL(for: groupTitleID) ??
                        matchingPlayedGame?.imageURL ??
                        first.gameIconURL
                    )
                )
                return ProfileAchievementGameGroup(
                    id: coreKind?.id ?? supportedGame?.titleID ?? first.gameTitleID ?? first.groupID ?? Self.groupKey(for: first),
                    title: groupTitle,
                    iconURL: iconDisplay.url,
                    iconAssetName: coreKind?.assetName ?? iconDisplay.assetName ?? Self.iconAssetName(for: sortedAchievements),
                    iconSystemImage: iconDisplay.systemImage,
                    achievements: sortedAchievements,
                    gamesPlayed: gamesPlayed,
                    isXBLCore: isCoreAchievementGroup
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var gameAchievementGroups: [ProfileAchievementGameGroup] {
        achievementGroups.filter { !$0.isXBLCore }
    }

    private var xblCoreAchievementGroups: [ProfileAchievementGameGroup] {
        achievementGroups.filter(\.isXBLCore)
            .sorted { lhs, rhs in
                let lhsOrder = Self.coreSortOrder(forTitle: lhs.title)
                let rhsOrder = Self.coreSortOrder(forTitle: rhs.title)
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func supportedGame(for achievements: [XBLiveAchievement]) -> InsigniaSupportedGame? {
        let titleIDs = Set(achievements.compactMap { $0.gameTitleID?.uppercased().nilIfEmpty })
        if let supportedGame = supportedGames.first(where: { titleIDs.contains($0.titleID.uppercased()) }) {
            return supportedGame
        }

        let titles = Set(achievements.compactMap { $0.gameTitle?.nilIfEmpty.map(Self.normalizedTitle) })
        return supportedGames.first { supportedGame in
            titles.contains(Self.normalizedTitle(supportedGame.title)) ||
            titles.contains(Self.normalizedTitle(supportedGame.subtitle))
        }
    }

    private func playedGame(
        for achievements: [XBLiveAchievement],
        supportedGame: InsigniaSupportedGame?
    ) -> XBLiveGamePlayed? {
        let titleIDs = Set(
            achievements.compactMap { $0.gameTitleID?.uppercased().nilIfEmpty } +
            [supportedGame?.titleID.uppercased()].compactMap { $0?.nilIfEmpty }
        )
        if let game = gamesPlayed.first(where: { game in
            guard let titleID = game.titleId?.uppercased().nilIfEmpty else {
                return false
            }
            return titleIDs.contains(titleID)
        }) {
            return game
        }

        let titles = Set(
            achievements.compactMap { $0.gameTitle?.nilIfEmpty.map(Self.normalizedTitle) } +
            [supportedGame?.title, supportedGame?.subtitle].compactMap { $0?.nilIfEmpty.map(Self.normalizedTitle) }
        )
        return gamesPlayed.first { game in
            titles.contains(Self.normalizedTitle(game.gameName))
        }
    }

    private static func groupKey(for achievement: XBLiveAchievement) -> String {
        if coreAchievementKind(for: achievement) != nil {
            return coreGroupKey(for: achievement)
        }
        if let groupID = achievement.groupID?.nilIfEmpty {
            return groupID.lowercased()
        }
        if let titleID = achievement.gameTitleID?.nilIfEmpty {
            return titleID.uppercased()
        }
        return normalizedTitle(achievement.gameTitle?.nilIfEmpty ?? "Unknown Game")
    }

    private static func iconAssetName(for achievements: [XBLiveAchievement]) -> String? {
        coreAchievementKind(for: achievements)?.assetName
    }

    private static func coreAchievementKind(for achievements: [XBLiveAchievement]) -> ProfileCoreAchievementKind? {
        achievements.compactMap(coreAchievementKind(for:))
            .sorted { lhs, rhs in
                lhs.sortOrder < rhs.sortOrder
            }
            .first
    }

    private static func coreAchievementKind(for achievement: XBLiveAchievement) -> ProfileCoreAchievementKind? {
        let normalizedValues = [
            achievement.groupID,
            achievement.gameTitle,
            achievement.category
        ]
            .compactMap { value -> String? in
                guard let value = value?.nilIfEmpty else {
                    return nil
                }
                return normalizedTitle(value)
            }

        if normalizedValues.contains("dukexcore") {
            return .dukeX
        }
        if normalizedValues.contains("xblcore") || normalizedValues.contains("xblivecore") {
            return .xbLive
        }
        return nil
    }

    private static func coreGroupKey(for achievement: XBLiveAchievement) -> String {
        if let groupID = achievement.groupID?.nilIfEmpty {
            return groupID.lowercased()
        }
        if let category = achievement.category?.nilIfEmpty {
            return normalizedTitle(category)
        }
        if let gameTitle = achievement.gameTitle?.nilIfEmpty {
            return normalizedTitle(gameTitle)
        }
        return "core"
    }

    private static func coreSortOrder(forTitle title: String) -> Int {
        switch normalizedTitle(title) {
        case "xblivecore", "xblcore":
            return 0
        case "dukexcore":
            return 1
        default:
            return 2
        }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }
}

private enum ProfileCoreAchievementKind {
    case xbLive
    case dukeX

    var id: String {
        switch self {
        case .xbLive:
            return "xbl-core"
        case .dukeX:
            return "dukex-core"
        }
    }

    var title: String {
        switch self {
        case .xbLive:
            return "XB.Live Core"
        case .dukeX:
            return "DukeX Core"
        }
    }

    var assetName: String {
        switch self {
        case .xbLive:
            return "XBLCoreAchievementIcon"
        case .dukeX:
            return "DukeXAppIcon"
        }
    }

    var sortOrder: Int {
        switch self {
        case .xbLive:
            return 0
        case .dukeX:
            return 1
        }
    }
}

private struct ProfileAchievementGameGroup: Identifiable {
    let id: String
    let title: String
    let iconURL: URL?
    let iconAssetName: String?
    let iconSystemImage: String
    let achievements: [XBLiveAchievement]
    let gamesPlayed: [XBLiveGamePlayed]
    let isXBLCore: Bool

    var unlockedAchievements: [XBLiveAchievement] {
        achievements
            .filter(isEffectivelyUnlocked)
            .sorted(by: Self.unlockedAchievementSort)
    }

    var lockedAchievements: [XBLiveAchievement] {
        achievements
            .filter { !isEffectivelyUnlocked($0) }
            .sorted(by: lockedAchievementSort)
    }

    var score: Int {
        unlockedAchievements.compactMap(\.score).reduce(0, +)
    }

    func progress(for achievement: XBLiveAchievement) -> ProfileAchievementProgress? {
        ProfileAchievementProgressResolver.visibleProgress(for: achievement, gamesPlayed: gamesPlayed)
    }

    private func isEffectivelyUnlocked(_ achievement: XBLiveAchievement) -> Bool {
        if achievement.isUnlocked != false {
            return true
        }
        return ProfileAchievementProgressResolver.resolvedProgress(
            for: achievement,
            gamesPlayed: gamesPlayed
        )?.fractionComplete == 1
    }

    private func lockedAchievementSort(_ lhs: XBLiveAchievement, _ rhs: XBLiveAchievement) -> Bool {
        let lhsProgress = progress(for: lhs)?.fractionComplete
        let rhsProgress = progress(for: rhs)?.fractionComplete

        switch (lhsProgress, rhsProgress) {
        case let (lhsProgress?, rhsProgress?):
            if lhsProgress != rhsProgress {
                return lhsProgress > rhsProgress
            }
            return Self.titleSort(lhs, rhs)
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return Self.titleSort(lhs, rhs)
        }
    }

    private static func unlockedAchievementSort(_ lhs: XBLiveAchievement, _ rhs: XBLiveAchievement) -> Bool {
        let lhsDate = unlockDate(for: lhs)
        let rhsDate = unlockDate(for: rhs)

        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return titleSort(lhs, rhs)
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return titleSort(lhs, rhs)
        }
    }

    private static func titleSort(_ lhs: XBLiveAchievement, _ rhs: XBLiveAchievement) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func unlockDate(for achievement: XBLiveAchievement) -> Date? {
        guard let unlockedAt = achievement.unlockedAt?.nilIfEmpty else {
            return nil
        }
        return parsedDate(from: unlockedAt)
    }

    private static func parsedDate(from value: String) -> Date? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = Double(trimmedValue) {
            let seconds = timestamp > 9_999_999_999 ? timestamp / 1_000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmedValue) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: trimmedValue) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: trimmedValue) {
                return date
            }
        }

        return nil
    }
}

private struct ProfileAchievementProgress: Equatable {
    let fractionComplete: Double
    let label: String?

    var displayPercent: Int {
        min(max(Int((fractionComplete * 100).rounded()), 1), 99)
    }
}

private enum ProfileAchievementProgressResolver {
    static func resolvedProgress(
        for achievement: XBLiveAchievement,
        gamesPlayed: [XBLiveGamePlayed]
    ) -> ProfileAchievementProgress? {
        apiProgress(for: achievement) ??
            playtimeProgress(for: achievement, gamesPlayed: gamesPlayed) ??
            gameCountProgress(for: achievement, gamesPlayed: gamesPlayed)
    }

    static func visibleProgress(
        for achievement: XBLiveAchievement,
        gamesPlayed: [XBLiveGamePlayed]
    ) -> ProfileAchievementProgress? {
        guard achievement.isUnlocked == false,
              let progress = resolvedProgress(for: achievement, gamesPlayed: gamesPlayed),
              progress.fractionComplete > 0,
              progress.fractionComplete < 1 else {
            return nil
        }
        return progress
    }

    private static func apiProgress(for achievement: XBLiveAchievement) -> ProfileAchievementProgress? {
        guard let apiProgress = achievement.progress,
              let fraction = apiProgress.fractionComplete else {
            return nil
        }
        return ProfileAchievementProgress(
            fractionComplete: clampedFraction(fraction),
            label: apiProgress.label ?? achievement.progressHint
        )
    }

    private static func playtimeProgress(
        for achievement: XBLiveAchievement,
        gamesPlayed: [XBLiveGamePlayed]
    ) -> ProfileAchievementProgress? {
        guard let description = achievement.description?.nilIfEmpty,
              description.localizedCaseInsensitiveContains("play"),
              description.localizedCaseInsensitiveContains("time"),
              let targetMinutes = targetMinutes(from: description),
              targetMinutes > 0 else {
            return nil
        }

        let currentMinutes = currentPlaytimeMinutes(for: achievement, gamesPlayed: gamesPlayed)
        return ProfileAchievementProgress(
            fractionComplete: clampedFraction(currentMinutes / targetMinutes),
            label: nil
        )
    }

    private static func gameCountProgress(
        for achievement: XBLiveAchievement,
        gamesPlayed: [XBLiveGamePlayed]
    ) -> ProfileAchievementProgress? {
        guard let description = achievement.description?.nilIfEmpty else {
            return nil
        }

        let normalizedDescription = description.lowercased()
        guard normalizedDescription.contains("game"),
              normalizedDescription.contains("insignia"),
              normalizedDescription.contains("play"),
              let targetCount = targetGameCount(from: description),
              targetCount > 0 else {
            return nil
        }

        let currentCount = gamesPlayed.filter { game in
            (game.totalMinutes ?? 0) > 0 || game.lastPlayedAt != nil
        }.count
        return ProfileAchievementProgress(
            fractionComplete: clampedFraction(Double(currentCount) / Double(targetCount)),
            label: nil
        )
    }

    private static func currentPlaytimeMinutes(
        for achievement: XBLiveAchievement,
        gamesPlayed: [XBLiveGamePlayed]
    ) -> Double {
        if let titleID = achievement.gameTitleID?.nilIfEmpty {
            let normalizedTitleID = titleID.uppercased()
            return gamesPlayed
                .first { $0.titleId?.uppercased() == normalizedTitleID }?
                .totalMinutes ?? 0
        }

        if let gameTitle = achievement.gameTitle?.nilIfEmpty,
           gameTitle.localizedCaseInsensitiveCompare("XBL Core") != .orderedSame,
           let game = gamesPlayed.first(where: {
               normalizedTitle($0.gameName) == normalizedTitle(gameTitle)
           }) {
            return game.totalMinutes ?? 0
        }

        return gamesPlayed.compactMap(\.totalMinutes).reduce(0, +)
    }

    private static func targetMinutes(from text: String) -> Double? {
        if let hours = firstNumber(in: text, before: #"hours?|hrs?"#) {
            return hours * 60
        }
        if let minutes = firstNumber(in: text, before: #"minutes?|mins?"#) {
            return minutes
        }
        return nil
    }

    private static func targetGameCount(from text: String) -> Int? {
        if let count = firstNumber(in: text, before: #"different\s+games|games"#) {
            return max(1, Int(count.rounded()))
        }
        return nil
    }

    private static func firstNumber(in text: String, before unitPattern: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s+"# + unitPattern
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[valueRange])
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private static func clampedFraction(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}

private struct ProfileGameIconDisplay {
    let url: URL?
    let assetName: String?
    let systemImage: String
}

private enum ProfileGameIconDisplayResolver {
    static func display(
        title: String?,
        titleID: String?,
        primaryURL: URL?,
        systemImage: String = "gamecontroller"
    ) -> ProfileGameIconDisplay {
        let normalizedTitleID = GameLaunchLink.normalizedTitleID(titleID)
        let normalizedTitle = normalizedTitle(title)
        if normalizedTitleID == "4D53007C" || normalizedTitle == "xboxvideochat" {
            return ProfileGameIconDisplay(url: nil, assetName: "XboxVideoChatIcon", systemImage: "video.circle")
        }
        if normalizedTitleID == "FFFE0000" || normalizedTitle == "xboxlivedashboard" {
            return ProfileGameIconDisplay(url: nil, assetName: "XboxLiveDashboardIcon", systemImage: "network")
        }
        return ProfileGameIconDisplay(url: primaryURL, assetName: nil, systemImage: systemImage)
    }

    private static func normalizedTitle(_ title: String?) -> String {
        title?
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression) ?? ""
    }
}

private struct ProfileAchievementGameRow: View {
    let group: ProfileAchievementGameGroup

    var body: some View {
        HStack(spacing: 12) {
            ProfileGameIcon(url: group.iconURL, assetName: group.iconAssetName, systemImage: group.iconSystemImage)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(group.unlockedAchievements.count)/\(group.achievements.count) unlocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if group.score > 0 {
                Text("\(group.score)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 50)
    }
}

private struct ProfileAchievementGameView: View {
    let group: ProfileAchievementGameGroup

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ProfileGameIcon(url: group.iconURL, assetName: group.iconAssetName, systemImage: group.iconSystemImage)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title)
                            .font(.headline)
                        Text("\(group.unlockedAchievements.count)/\(group.achievements.count) unlocked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if group.score > 0 {
                        Text("\(group.score)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 58)
            }
            .dukeXThemedListRowBackground()

            if group.unlockedAchievements.isEmpty {
                Section("Unlocked") {
                    ProfileEmptyRow(title: "No unlocked achievements", systemImage: "lock")
                }
                .dukeXThemedListRowBackground()
            } else {
                Section("Unlocked") {
                    ForEach(group.unlockedAchievements) { achievement in
                        ProfileAchievementRow(achievement: achievement)
                    }
                }
                .dukeXThemedListRowBackground()
            }

            if !group.lockedAchievements.isEmpty {
                Section("Not Yet Unlocked") {
                    ForEach(group.lockedAchievements) { achievement in
                        ProfileAchievementRow(
                            achievement: achievement,
                            isLocked: true,
                            progress: group.progress(for: achievement)
                        )
                    }
                }
                .dukeXThemedListRowBackground()
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
    }
}

private struct ProfileAchievementRow: View {
    let achievement: XBLiveAchievement
    var isLocked = false
    var progress: ProfileAchievementProgress? = nil

    var body: some View {
        HStack(spacing: 12) {
            achievementIcon
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let description = achievement.description?.nilIfEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !isLocked, let unlockedAt = achievement.unlockedAt?.nilIfEmpty {
                    Text("Unlocked \(unlockedAt)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let score = achievement.score {
                Text("\(score)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 54)
        .opacity(isLocked ? 0.48 : 1.0)
    }

    @ViewBuilder
    private var achievementIcon: some View {
        if let progress {
            ProfileAchievementProgressBadge(progress: progress)
        } else {
            AsyncImage(url: achievement.iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                        Image(systemName: isLocked ? "lock" : "medal")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct ProfileAchievementProgressBadge: View {
    let progress: ProfileAchievementProgress

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.18))

            Circle()
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 3.5)
                .frame(width: 30, height: 30)

            Circle()
                .trim(from: 0, to: progress.fractionComplete)
                .stroke(
                    Color.accentColor.opacity(0.92),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 30)

            Text("\(progress.displayPercent)%")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.85)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileGameIcon: View {
    let url: URL?
    var assetName: String?
    let systemImage: String

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var fallback: some View {
        if assetName == "DukeXAppIcon" {
            DukeXAppIconImage()
        } else if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DukeXAppIconImage: View {
    var body: some View {
        if let image = UIImage.dukeXPrimaryAppIcon {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension UIImage {
    static var dukeXPrimaryAppIcon: UIImage? {
        let iconFiles = (((Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconFiles"] as? [String]) ?? []
        for iconFile in iconFiles.reversed() {
            if let image = UIImage(named: iconFile) {
                return image
            }
        }
        return UIImage(named: "AppIconGC") ?? UIImage(named: "dukex_gc_1024")
    }
}

struct ProfileEventRow: View {
    let event: XBLiveEvent

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: event.gameImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Color.secondary.opacity(0.18)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.profileDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
        .frame(minHeight: 50)
    }

    private var subtitle: String {
        event.profileRowSubtitleParts
            .joined(separator: " - ")
    }
}

struct ProfilePaidEventDisclaimerRow: View {
    static let text = "Contests and paid promotions on xb.live are sponsored solely by Tiny Umbrella, LLC. DukeX is not a sponsor of, and is not involved in any way with, any contest, tournament, or promotion offered through xb.live services. Official rules can be found at: https://xb.live/paid-events-terms"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Official Rules", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            ProfileJustifiedText(Self.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

private struct ProfileJustifiedText: UIViewRepresentable {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributedText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private var attributedText: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.hyphenationFactor = 0.2

        return NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraph
            ]
        )
    }
}

private struct ProfileEventDetailHeaderImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProfileEventDetailView: View {
    let event: XBLiveEvent

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ProfileEventDetailHeaderImage(url: event.profileDetailHeaderImageURL)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.profileDisplayTitle)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(event.scheduleText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }
            .dukeXThemedListRowBackground()

            if let description = event.description?.nilIfEmpty {
                Section("Description") {
                    Text(description)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .dukeXThemedListRowBackground()
            }

            Section("Requirements") {
                if requirements.isEmpty {
                    ProfileEmptyRow(title: "No special requirements listed", systemImage: "checkmark.circle")
                } else {
                    ForEach(requirements) { requirement in
                        Label(requirement.title, systemImage: requirement.systemImage)
                            .foregroundStyle(.primary)
                            .frame(minHeight: 36)
                    }
                }
            }
            .dukeXThemedListRowBackground()

            Section("Details") {
                if let type = event.profileTypeText {
                    ProfileInfoRow(title: "Type", value: type, systemImage: event.isTournament ? "trophy" : "ticket")
                }
                if let gameName = event.gameName?.nilIfEmpty {
                    ProfileInfoRow(title: "Game", value: gameName, systemImage: "gamecontroller")
                }
                if let titleID = event.titleID?.nilIfEmpty {
                    ProfileInfoRow(title: "Title ID", value: titleID, systemImage: "number")
                }
                ProfileInfoRow(title: "Starts", value: event.scheduleText, systemImage: "clock")
                if let host = event.communityHost?.nilIfEmpty ?? event.createdBy?.nilIfEmpty {
                    ProfileInfoRow(title: "Host", value: host, systemImage: "person")
                }
                if let tag = event.eventTag?.nilIfEmpty {
                    ProfileInfoRow(title: "Tag", value: tag, systemImage: "tag")
                }
                if let status = event.profileStatusText {
                    ProfileInfoRow(title: "Status", value: status, systemImage: "flag.checkered")
                }
                if let signups = event.profileSignupText {
                    ProfileInfoRow(title: "Signups", value: signups, systemImage: "person.2")
                }
                if let entryFee = event.profileEntryFeeText {
                    ProfileInfoRow(title: "Entry Fee", value: entryFee, systemImage: "bitcoinsign.circle")
                }
                if let reward = event.profileRewardText {
                    ProfileInfoRow(title: "Reward", value: reward, systemImage: "gift")
                }
                if let sponsor = event.sponsorName?.nilIfEmpty {
                    ProfileInfoRow(title: "Sponsor", value: sponsor, systemImage: "building.2")
                }
                if let registration = event.profileRegistrationText {
                    ProfileInfoRow(title: "Registration", value: registration, systemImage: "square.and.pencil")
                }
                if let pot = event.profilePotText {
                    ProfileInfoRow(title: "Pot", value: pot, systemImage: "banknote")
                }
                if let source = event.source?.nilIfEmpty {
                    ProfileInfoRow(title: "Source", value: source.capitalized, systemImage: "network")
                }
            }
            .dukeXThemedListRowBackground()

            if let additionalRules = event.additionalRules?.nilIfEmpty ?? event.winningParameters?.nilIfEmpty {
                Section("Rules") {
                    Text(additionalRules)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .dukeXThemedListRowBackground()
            }

            if event.isPaid || event.isTournament {
                Section {
                    ProfilePaidEventDisclaimerRow()
                }
                .dukeXThemedListRowBackground()
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
    }

    private var requirements: [ProfileEventRequirement] {
        event.profileRequirements
    }
}

private struct ProfileEventRequirement: Identifiable {
    let title: String
    let systemImage: String

    var id: String { title }
}

private extension XBLiveEvent {
    var profileDetailHeaderImageURL: URL? {
        if isTournament {
            return gameImageURL ?? bannerURL
        }
        return bannerURL ?? gameImageURL
    }

    var profileDisplayTitle: String {
        guard isTournament else {
            return title
        }
        let cleanedTitle = Self.removingEmoji(from: title)
        return cleanedTitle.nilIfEmpty ?? title
    }

    var profileRowSubtitleParts: [String] {
        var parts = [String]()
        if let gameName = gameName?.nilIfEmpty {
            parts.append(gameName)
        }
        if let status = profileStatusText, isTournament {
            parts.append(status)
        } else if isPaid,
                  let reward = profileRewardText {
            parts.append(reward)
        }
        parts.append(scheduleText)
        return parts
    }

    var profileTypeText: String? {
        if isPaid && isTournament {
            return "Paid Tournament"
        }
        if isPaid {
            return "Paid Event"
        }
        if isTournament {
            return "Tournament"
        }
        return nil
    }

    var profileStatusText: String? {
        guard let status = tournamentStatus?.nilIfEmpty else {
            return nil
        }
        return status
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var profileSignupText: String? {
        guard let signupCount else {
            return allowSignup == true ? "Open" : nil
        }
        let suffix = signupCount == 1 ? "signup" : "signups"
        if allowSignup == true {
            return "\(signupCount) \(suffix), open"
        }
        return "\(signupCount) \(suffix)"
    }

    var profileEntryFeeText: String? {
        if let entryFeeSats {
            return "\(Self.satsText(entryFeeSats)) \(entryFeeCurrency?.nilIfEmpty ?? "sats")"
        }
        if isPaid {
            return "No entry fee listed"
        }
        return nil
    }

    var profileRewardText: String? {
        if let rewardTotalSats {
            return "\(Self.satsText(rewardTotalSats)) sats"
        }
        if hasPrize == true,
           let prizeAmount = prizeAmount?.nilIfEmpty {
            return prizeAmount
        }
        if isPaid {
            return "Reward not listed"
        }
        return nil
    }

    var profileRegistrationText: String? {
        let opens = registrationOpensAt?.nilIfEmpty
        let closes = registrationClosesAt?.nilIfEmpty
        switch (opens, closes) {
        case let (opens?, closes?):
            return "Opens \(opens), closes \(closes)"
        case let (opens?, nil):
            return "Opens \(opens)"
        case let (nil, closes?):
            return "Closes \(closes)"
        case (nil, nil):
            return allowSignup == true ? "Open" : nil
        }
    }

    var profilePotText: String? {
        var parts: [String] = []
        if let potExpectedSats {
            parts.append("Expected \(Self.satsText(potExpectedSats)) sats")
        }
        if let potVerifiedBalanceSats {
            parts.append("Verified \(Self.satsText(potVerifiedBalanceSats)) sats")
        }
        if potFundsVerified == true {
            parts.append("Funds verified")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    private static func satsText(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func removingEmoji(from value: String) -> String {
        let scalars = value.unicodeScalars.filter { scalar in
            !scalar.properties.isEmojiPresentation &&
                scalar.value != 0xFE0F &&
                scalar.value != 0x200D
        }
        return String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var profileRequirements: [ProfileEventRequirement] {
        var requirements: [ProfileEventRequirement] = []

        if dlcRequired == true || textRequires("dlc") {
            requirements.append(ProfileEventRequirement(title: "DLC required", systemImage: "square.and.arrow.down"))
        }

        if textRequires("tu") || textRequires("title update") {
            requirements.append(ProfileEventRequirement(title: "Title update required", systemImage: "arrow.triangle.2.circlepath"))
        }

        if moddedContentRequired == true || textRequires("modded content") {
            requirements.append(ProfileEventRequirement(title: "Modded content required", systemImage: "hammer"))
        }

        if requiresDiscordVoice {
            requirements.append(ProfileEventRequirement(title: "Discord voice chat", systemImage: "mic"))
        }

        if xlinkKai == true || textRequires("xlink kai") || textRequires("xlink-kai") {
            requirements.append(ProfileEventRequirement(title: "XLink Kai", systemImage: "link"))
        }

        if isLeaderboard == true {
            requirements.append(ProfileEventRequirement(title: "Leaderboard event", systemImage: "list.number"))
        }

        return requirements
    }

    private var requiresDiscordVoice: Bool {
        let text = searchableRequirementText
        if text.range(of: #"voice\s*:\s*(no|none|n/a|false)"#, options: .regularExpression) != nil {
            return false
        }
        return text.contains("discord voice") ||
            text.contains("voice: discord") ||
            text.contains("voice chat: discord") ||
            text.contains("using discord voice")
    }

    private func textRequires(_ keyword: String) -> Bool {
        let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword.lowercased())
        let text = searchableRequirementText
        let negativePattern = #"\b\#(escapedKeyword)\b[^\n\r.;]*(no|none|n/a|false)"#
        if text.range(of: negativePattern, options: .regularExpression) != nil {
            return false
        }

        let forwardPattern = #"\b\#(escapedKeyword)\b[^\n\r.;]*(required|yes)"#
        let reversePattern = #"(required|yes)[^\n\r.;]*\b\#(escapedKeyword)\b"#
        return text.range(of: forwardPattern, options: .regularExpression) != nil ||
            text.range(of: reversePattern, options: .regularExpression) != nil
    }

    private var searchableRequirementText: String {
        [
            description,
            eventTag,
            additionalRules,
            winningParameters
        ]
        .compactMap { $0?.nilIfEmpty }
        .joined(separator: "\n")
        .lowercased()
    }
}

struct ProfileEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
    }
}

private struct ProfileCircleImage: View {
    let image: UIImage?
    let url: URL?
    let fallbackInitial: String

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            RemoteCircleImage(url: url, fallbackInitial: fallbackInitial)
        }
    }
}

private struct RemoteCircleImage: View {
    let url: URL?
    let fallbackInitial: String

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    InitialAvatar(initial: fallbackInitial)
                }
            }
            .clipShape(Circle())
        } else {
            InitialAvatar(initial: fallbackInitial)
        }
    }
}

private struct InitialAvatar: View {
    let initial: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
            Text(initial)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
