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
}

struct ProfileHeaderRow: View {
    private let avatarSize: CGFloat = 48

    let session: InsigniaProfileSession
    let snapshot: InsigniaAuthenticatedSnapshot?
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
    var isFavorite = false

    var body: some View {
        HStack(spacing: 12) {
            ProfileCircleImage(image: customProfileImage, url: profile?.avatarURL, fallbackInitial: initial)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.gamertag)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .imageScale(.small)
                    }
                    Circle()
                        .fill(friend.isOnline ? Color.green : Color.secondary.opacity(0.55))
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

    private var initial: String {
        String(friend.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

struct ProfileFriendsView: View {
    let friends: [InsigniaFriend]
    let friendProfiles: [String: XBLiveFriendProfile]
    let friendProfileImages: [String: UIImage]
    @Binding var sortMode: ProfileFriendSortMode
    let favoriteFriendKeys: Set<String>
    let toggleFavorite: (InsigniaFriend) -> Void
    let changeFriendProfileImage: (InsigniaFriend) -> Void

    var body: some View {
        List {
            ProfileFriendSortPickerRow(selection: $sortMode)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section("Friends") {
                if sortedFriends.isEmpty {
                    ProfileEmptyRow(title: emptyFriendsTitle, systemImage: emptyFriendsSystemImage)
                } else {
                    ForEach(sortedFriends) { friend in
                        NavigationLink {
                            ProfileFriendDetailView(
                                friend: friend,
                                profile: friendProfiles[friend.key],
                                customProfileImage: friendProfileImages[friend.key],
                                changeProfileImage: { changeFriendProfileImage(friend) }
                            )
                        } label: {
                            ProfileFriendRow(
                                friend: friend,
                                profile: friendProfiles[friend.key],
                                customProfileImage: friendProfileImages[friend.key],
                                isFavorite: isFavorite(friend)
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
                    }
                }
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
    }

    private var sortedFriends: [InsigniaFriend] {
        switch sortMode {
        case .favorites:
            return friends
                .filter(isFavorite)
                .sorted(by: friendNameSort)
        case .alphabetical:
            return friends.sorted(by: friendNameSort)
        case .recentActivity:
            return friends.sorted { lhs, rhs in
                let lhsActivity = activitySortValue(for: lhs)
                let rhsActivity = activitySortValue(for: rhs)
                if lhsActivity != rhsActivity {
                    return lhsActivity > rhsActivity
                }
                return friendNameSort(lhs, rhs)
            }
        }
    }

    private var emptyFriendsTitle: String {
        switch sortMode {
        case .favorites:
            return "No favorite friends"
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

    private func friendNameSort(_ lhs: InsigniaFriend, _ rhs: InsigniaFriend) -> Bool {
        lhs.gamertag.localizedStandardCompare(rhs.gamertag) == .orderedAscending
    }

    private func activitySortValue(for friend: InsigniaFriend) -> Double {
        let profile = friendProfiles[friend.key]
        if friend.isOnline || profile?.isOnline == true || profile?.currentGame?.nilIfEmpty != nil {
            return .greatestFiniteMagnitude
        }
        return profile?.lastPlayedAt ?? 0
    }
}

private struct ProfileFriendSortPickerRow: View {
    @Binding var selection: ProfileFriendSortMode

    var body: some View {
        GeometryReader { proxy in
            ProfileFriendSortPicker(selection: $selection)
                .frame(width: max(0, proxy.size.width - 40))
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
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

private enum ProfileFriendOnlineText {
    static func statusLine(friend: InsigniaFriend, profile: XBLiveFriendProfile?) -> String {
        if friend.isOnline || profile?.isOnline == true || profile?.currentGame?.nilIfEmpty != nil {
            return "Last Online: Now"
        }

        if let lastPlayedAt = profile?.lastPlayedAt,
           let relativeText = relativeLastOnlineText(from: lastPlayedAt) {
            return "Last Online: \(relativeText)"
        }

        if let lastSeen = friend.lastSeen?.nilIfEmpty {
            return "Last Online: \(lastSeen)"
        }

        return "Last Online: Unknown"
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
                    .lineLimit(2)
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
            AsyncImage(url: game.imageURL) { phase in
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
    let changeProfileImage: () -> Void

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    ProfileCircleImage(image: customProfileImage, url: profile?.avatarURL, fallbackInitial: initial)
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
                            .foregroundStyle(friend.isOnline ? .green : .secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .dukeXThemedListRowBackground()

            Section("Profile") {
                if let score = profile?.achievementScore {
                    ProfileInfoRow(title: "Gamerscore", value: "\(score)", systemImage: "trophy")
                }
                if let count = profile?.achievementCount {
                    ProfileInfoRow(title: "Achievements", value: "\(count)", systemImage: "medal")
                }
                if let minutes = profile?.totalMinutes {
                    ProfileInfoRow(title: "Play Time", value: playTimeText(minutes), systemImage: "timer")
                }
                if let lastPlayed = profile?.lastPlayedGame {
                    ProfileInfoRow(title: "Last Played", value: lastPlayed, systemImage: "clock")
                }
            }
            .dukeXThemedListRowBackground()
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
    }

    private var statusLine: String {
        ProfileFriendOnlineText.statusLine(friend: friend, profile: profile)
    }

    private var initial: String {
        String(friend.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private func playTimeText(_ minutes: Double) -> String {
        let hours = minutes / 60.0
        if hours >= 10 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
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
                if achievementGroups.isEmpty {
                    ProfileEmptyRow(title: "No achievements synced", systemImage: "medal")
                } else {
                    ForEach(achievementGroups) { group in
                        NavigationLink {
                            ProfileAchievementGameView(group: group)
                        } label: {
                            ProfileAchievementGameRow(group: group)
                        }
                    }
                }
            }
            .dukeXThemedListRowBackground()
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
                return ProfileAchievementGameGroup(
                    id: supportedGame?.titleID ?? first.gameTitleID ?? first.groupID ?? Self.groupKey(for: first),
                    title: supportedGame?.title ?? first.gameTitle?.nilIfEmpty ?? "Unknown Game",
                    iconURL: supportedGame?.iconURL ?? first.gameIconURL,
                    iconAssetName: Self.iconAssetName(for: sortedAchievements),
                    achievements: sortedAchievements
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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

    private static func groupKey(for achievement: XBLiveAchievement) -> String {
        if let groupID = achievement.groupID?.nilIfEmpty {
            return groupID.lowercased()
        }
        if let titleID = achievement.gameTitleID?.nilIfEmpty {
            return titleID.uppercased()
        }
        return normalizedTitle(achievement.gameTitle?.nilIfEmpty ?? "Unknown Game")
    }

    private static func iconAssetName(for achievements: [XBLiveAchievement]) -> String? {
        achievements.contains(where: isXBLCoreAchievement) ? "XBLCoreAchievementIcon" : nil
    }

    private static func isXBLCoreAchievement(_ achievement: XBLiveAchievement) -> Bool {
        achievement.groupID?.localizedCaseInsensitiveCompare("xbl_core") == .orderedSame ||
            achievement.gameTitle?.localizedCaseInsensitiveCompare("XBL Core") == .orderedSame ||
            achievement.category?.localizedCaseInsensitiveCompare("XBL Core") == .orderedSame
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }
}

private struct ProfileAchievementGameGroup: Identifiable {
    let id: String
    let title: String
    let iconURL: URL?
    let iconAssetName: String?
    let achievements: [XBLiveAchievement]

    var unlockedAchievements: [XBLiveAchievement] {
        achievements
            .filter { $0.isUnlocked != false }
            .sorted(by: Self.unlockedAchievementSort)
    }

    var lockedAchievements: [XBLiveAchievement] {
        achievements
            .filter { $0.isUnlocked == false }
            .sorted(by: Self.titleSort)
    }

    var score: Int {
        unlockedAchievements.compactMap(\.score).reduce(0, +)
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

private struct ProfileAchievementGameRow: View {
    let group: ProfileAchievementGameGroup

    var body: some View {
        HStack(spacing: 12) {
            ProfileGameIcon(url: group.iconURL, assetName: group.iconAssetName, systemImage: "medal")
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
                    ProfileGameIcon(url: group.iconURL, assetName: group.iconAssetName, systemImage: "medal")
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
                        ProfileAchievementRow(achievement: achievement, isLocked: true)
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

    var body: some View {
        HStack(spacing: 12) {
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
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

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
        if let assetName {
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
                Text(event.title)
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
        [event.gameName, event.scheduleText]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " - ")
    }
}

struct ProfileEventDetailView: View {
    let event: XBLiveEvent

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    AsyncImage(url: event.bannerURL ?? event.gameImageURL) { phase in
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

                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title)
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
                if let gameName = event.gameName?.nilIfEmpty {
                    ProfileInfoRow(title: "Game", value: gameName, systemImage: "gamecontroller")
                }
                ProfileInfoRow(title: "Starts", value: event.scheduleText, systemImage: "clock")
                if let host = event.communityHost?.nilIfEmpty ?? event.createdBy?.nilIfEmpty {
                    ProfileInfoRow(title: "Host", value: host, systemImage: "person")
                }
                if let tag = event.eventTag?.nilIfEmpty {
                    ProfileInfoRow(title: "Tag", value: tag, systemImage: "tag")
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
