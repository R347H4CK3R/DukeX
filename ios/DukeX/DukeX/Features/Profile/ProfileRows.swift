import SwiftUI
import UIKit

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
            return "Last refresh: Not Synced"
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

    var body: some View {
        HStack(spacing: 12) {
            RemoteCircleImage(url: profile?.avatarURL, fallbackInitial: initial)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.gamertag)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
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
        if let game = friend.game, friend.isOnline {
            return friend.duration.map { "Playing \(game) for \($0)" } ?? "Playing \(game)"
        }
        if let lastGame = profile?.lastPlayedGame {
            return "Last played \(lastGame)"
        }
        return friend.lastSeen ?? friend.status
    }

    private var initial: String {
        String(friend.gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
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

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    RemoteCircleImage(url: profile?.avatarURL, fallbackInitial: initial)
                        .frame(width: 74, height: 74)

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

            if let imageURL = profile?.lastPlayedImageURL {
                Section("Last Game") {
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .navigationTitle(friend.gamertag)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusLine: String {
        if let currentGame = profile?.currentGame ?? friend.game,
           friend.isOnline || profile?.isOnline == true {
            return friend.duration.map { "Playing \(currentGame) for \($0)" } ?? "Playing \(currentGame)"
        }
        if profile?.isOnline == true || friend.isOnline {
            return "Online"
        }
        if let lastGame = profile?.lastPlayedGame {
            return "Last played \(lastGame)"
        }
        return friend.lastSeen ?? friend.status
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
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
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
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
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
        achievements.filter { $0.isUnlocked != false }
    }

    var lockedAchievements: [XBLiveAchievement] {
        achievements.filter { $0.isUnlocked == false }
    }

    var score: Int {
        unlockedAchievements.compactMap(\.score).reduce(0, +)
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

            if group.unlockedAchievements.isEmpty {
                Section("Unlocked") {
                    ProfileEmptyRow(title: "No unlocked achievements", systemImage: "lock")
                }
            } else {
                Section("Unlocked") {
                    ForEach(group.unlockedAchievements) { achievement in
                        ProfileAchievementRow(achievement: achievement)
                    }
                }
            }

            if !group.lockedAchievements.isEmpty {
                Section("Not Yet Unlocked") {
                    ForEach(group.lockedAchievements) { achievement in
                        ProfileAchievementRow(achievement: achievement, isLocked: true)
                    }
                }
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
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
        }
        .frame(minHeight: 50)
    }

    private var subtitle: String {
        [event.gameName, event.eventDate, event.startTime]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " - ")
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
