import Foundation
import SafariServices
import Security
import SwiftUI
import UIKit

struct InsigniaProfileSession: Codable, Equatable {
    let gamertag: String
    let email: String?
    let signedInAt: Date
    let isAuthenticated: Bool
}

struct InsigniaPublicSnapshot: Codable, Equatable {
    let registeredUsers: String
    let gamesSupported: String
    let usersOnline: String
    let activeGames: [InsigniaActiveGame]
}

struct InsigniaActiveGame: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let serial: String
    let onlineUsers: String
    let detail: String
    let iconUrl: String?

    var iconURL: URL? { iconUrl.flatMap(URL.init(string:)) }
}

struct InsigniaSupportedGame: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let serial: String
    let titleID: String
    let iconUrl: String?

    var iconURL: URL? { iconUrl.flatMap(URL.init(string:)) }
}

struct InsigniaAuthenticatedSnapshot: Codable, Equatable {
    let profile: InsigniaAuthenticatedProfile?
    let friends: [InsigniaFriend]
    let games: [InsigniaProfileGame]
    let messages: [InsigniaMessage]
    let xbProfile: XBLiveProfileSnapshot?
    let playtimeGames: [XBLiveGamePlayed]
    let achievements: XBLiveAchievementsSnapshot?
    let friendProfiles: [String: XBLiveFriendProfile]
    let events: [XBLiveEvent]
    let supportedGames: [InsigniaSupportedGame]
    let loadedAt: Date

    enum CodingKeys: String, CodingKey {
        case profile
        case friends
        case games
        case messages
        case xbProfile
        case playtimeGames
        case achievements
        case friendProfiles
        case events
        case supportedGames
        case loadedAt
    }

    init(
        profile: InsigniaAuthenticatedProfile?,
        friends: [InsigniaFriend],
        games: [InsigniaProfileGame],
        messages: [InsigniaMessage],
        xbProfile: XBLiveProfileSnapshot?,
        playtimeGames: [XBLiveGamePlayed],
        achievements: XBLiveAchievementsSnapshot?,
        friendProfiles: [String: XBLiveFriendProfile],
        events: [XBLiveEvent],
        supportedGames: [InsigniaSupportedGame],
        loadedAt: Date
    ) {
        self.profile = profile
        self.friends = friends
        self.games = games
        self.messages = messages
        self.xbProfile = xbProfile
        self.playtimeGames = playtimeGames
        self.achievements = achievements
        self.friendProfiles = friendProfiles
        self.events = events
        self.supportedGames = supportedGames
        self.loadedAt = loadedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(InsigniaAuthenticatedProfile.self, forKey: .profile)
        friends = try container.decodeIfPresent([InsigniaFriend].self, forKey: .friends) ?? []
        games = try container.decodeIfPresent([InsigniaProfileGame].self, forKey: .games) ?? []
        messages = try container.decodeIfPresent([InsigniaMessage].self, forKey: .messages) ?? []
        xbProfile = try container.decodeIfPresent(XBLiveProfileSnapshot.self, forKey: .xbProfile)
        playtimeGames = try container.decodeIfPresent([XBLiveGamePlayed].self, forKey: .playtimeGames) ?? []
        achievements = try container.decodeIfPresent(XBLiveAchievementsSnapshot.self, forKey: .achievements)
        friendProfiles = try container.decodeIfPresent([String: XBLiveFriendProfile].self, forKey: .friendProfiles) ?? [:]
        events = try container.decodeIfPresent([XBLiveEvent].self, forKey: .events) ?? []
        supportedGames = try container.decodeIfPresent([InsigniaSupportedGame].self, forKey: .supportedGames) ?? []
        loadedAt = try container.decodeIfPresent(Date.self, forKey: .loadedAt) ?? .distantPast
    }
}

struct InsigniaAuthenticatedProfile: Codable, Equatable {
    let isOnline: Bool
    let status: String
    let game: String?
    let timeOnline: String?
    let psoServer: String?
    let nameplate: String?
    let gamesPlayed: [InsigniaProfileGame]
    let lastUpdated: Double?
    let count: Int
}

struct InsigniaFriend: Codable, Identifiable, Equatable {
    let gamertag: String
    let status: String
    let isOnline: Bool
    let game: String?
    let duration: String?
    let lastSeen: String?
    let lastSeenAt: Double?

    var id: String { key }
    var key: String { gamertag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ProfileFlexibleCodingKey.self)
        gamertag = container.flexibleString(for: [
            "gamertag",
            "username",
            "displayName",
            "display_name",
            "name"
        ]) ?? "Unknown"
        status = container.flexibleString(for: [
            "status",
            "lastState",
            "last_state",
            "state"
        ]) ?? "Offline"
        game = container.flexibleString(for: [
            "game",
            "currentGame",
            "current_game",
            "activeGame",
            "active_game"
        ])
        duration = container.flexibleString(for: [
            "duration",
            "timeOnline",
            "time_online",
            "onlineDuration",
            "online_duration"
        ])
        lastSeen = container.flexibleString(for: [
            "lastSeen",
            "last_seen",
            "lastOnline",
            "last_online",
            "lastSeenText",
            "last_seen_text",
            "lastOnlineText",
            "last_online_text"
        ])
        lastSeenAt = container.flexibleTimestamp(for: [
            "lastSeenAt",
            "last_seen_at",
            "lastOnlineAt",
            "last_online_at",
            "lastActiveAt",
            "last_active_at",
            "seenAt",
            "seen_at"
        ])

        let onlineValue = container.flexibleBool(for: [
            "isOnline",
            "is_online",
            "online",
            "active",
            "isActive",
            "is_active"
        ])
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        isOnline = onlineValue ?? (
            normalizedStatus == "online" ||
            normalizedStatus == "active" ||
            game?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        )
    }
}

struct InsigniaProfileGame: Codable, Identifiable, Equatable {
    let title: String
    let lastPlayed: String?
    let iconUrl: String?

    var id: String { "\(title)-\(lastPlayed ?? "")" }
    var iconURL: URL? { iconUrl.flatMap(URL.init(string:)) }
}

struct InsigniaMessage: Codable, Identifiable, Equatable {
    let id: String
    let sender: String
    let type: String
    let game: String?
    let sentAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sender = "from"
        case type
        case game
        case sentAt
    }

    init(id: String, sender: String, type: String, game: String?, sentAt: String?) {
        self.id = id
        self.sender = sender
        self.type = type
        self.game = game
        self.sentAt = sentAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(forKey: .id) ?? UUID().uuidString
        sender = try container.decodeIfPresent(String.self, forKey: .sender) ?? "Unknown"
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Message"
        game = try container.decodeIfPresent(String.self, forKey: .game)
        sentAt = try container.decodeIfPresent(String.self, forKey: .sentAt)
    }
}

struct XBLiveProfileSnapshot: Codable, Equatable {
    let username: String
    let avatarURLString: String?
    let linkedGamertag: String?
    let isOnline: Bool
    let lastState: String?
    let currentGame: String?
    let lastPlayedGame: String?
    let lastPlayedAt: Double?
    let lastOnlineAt: Double?
    let lastCheckedAt: Double?
    let totalMinutes: Double?
    let achievementScore: Int?
    let achievementCount: Int?

    var avatarURL: URL? { avatarURLString.flatMap(URL.init(string:)) }
}

struct XBLiveFriendProfile: Codable, Equatable {
    let gamertag: String
    let avatarURLString: String?
    let isOnline: Bool?
    let lastState: String?
    let currentGame: String?
    let lastPlayedGame: String?
    let lastPlayedAt: Double?
    let lastOnlineAt: Double?
    let lastCheckedAt: Double?
    let achievementScore: Int?
    let achievementCount: Int?
    let totalMinutes: Double?
    let lastPlayedImageURLString: String?
    let gamesPlayed: [XBLiveGamePlayed]?
    let achievements: XBLiveAchievementsSnapshot?

    var avatarURL: URL? { avatarURLString.flatMap(URL.init(string:)) }
    var lastPlayedImageURL: URL? { lastPlayedImageURLString.flatMap(URL.init(string:)) }
}

struct XBLiveGamePlayed: Codable, Identifiable, Equatable {
    let gameName: String
    let titleId: String?
    let imageUrl: String?
    let lastPlayedAt: Double?
    let totalMinutes: Double?

    var id: String {
        (titleId ?? gameName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }

    init(
        gameName: String,
        titleId: String?,
        imageUrl: String?,
        lastPlayedAt: Double?,
        totalMinutes: Double?
    ) {
        self.gameName = gameName
        self.titleId = titleId
        self.imageUrl = imageUrl
        self.lastPlayedAt = lastPlayedAt
        self.totalMinutes = totalMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ProfileFlexibleCodingKey.self)
        let minutes = container.flexibleDouble(for: [
            "totalMinutes",
            "total_minutes",
            "minutes",
            "minutesPlayed",
            "minutes_played",
            "playtimeMinutes",
            "playtime_minutes",
            "playTimeMinutes",
            "play_time_minutes"
        ])
        let seconds = container.flexibleDouble(for: [
            "totalSeconds",
            "total_seconds",
            "seconds",
            "secondsPlayed",
            "seconds_played",
            "playtimeSeconds",
            "playtime_seconds",
            "playTimeSeconds",
            "play_time_seconds"
        ])
        let hours = container.flexibleDouble(for: [
            "totalHours",
            "total_hours",
            "hours",
            "hoursPlayed",
            "hours_played",
            "playtimeHours",
            "playtime_hours",
            "playTimeHours",
            "play_time_hours"
        ])

        gameName = container.flexibleString(for: [
            "gameName",
            "game_name",
            "name",
            "title",
            "titleName",
            "title_name"
        ]) ?? "Unknown Game"
        titleId = container.flexibleString(for: [
            "titleId",
            "title_id",
            "gameTitleId",
            "game_title_id"
        ])?.uppercased()
        imageUrl = container.flexibleString(for: [
            "imageUrl",
            "image_url",
            "image",
            "iconUrl",
            "icon_url",
            "icon"
        ])
        lastPlayedAt = container.flexibleDouble(for: [
            "lastPlayedAt",
            "last_played_at",
            "lastPlayedTimestamp",
            "last_played_timestamp",
            "lastSeenAt",
            "last_seen_at"
        ])
        totalMinutes = minutes ?? seconds.map { $0 / 60.0 } ?? hours.map { $0 * 60.0 }
    }

    enum CodingKeys: String, CodingKey {
        case gameName
        case titleId
        case imageUrl
        case lastPlayedAt
        case totalMinutes
    }
}

struct XBLiveAchievementsSnapshot: Codable, Equatable {
    let totalScore: Int?
    let totalCount: Int?
    let unlockedCount: Int?
    let achievements: [XBLiveAchievement]

    var summaryText: String {
        if let unlockedCount {
            return "\(unlockedCount)"
        }
        if !achievements.isEmpty {
            return "\(achievements.filter { $0.isUnlocked != false }.count)"
        }
        return totalCount.map(String.init) ?? "Not Synced"
    }

    init(totalScore: Int?, totalCount: Int?, unlockedCount: Int?, achievements: [XBLiveAchievement]) {
        self.totalScore = totalScore
        self.totalCount = totalCount
        self.unlockedCount = unlockedCount
        self.achievements = achievements
    }

    init(json: Any) {
        if let array = json as? [[String: Any]] {
            let achievements = array.map { XBLiveAchievement(json: $0) }
            self.init(totalScore: achievements.compactMap(\.score).reduce(0, +),
                      totalCount: achievements.count,
                      unlockedCount: achievements.filter { $0.isUnlocked == true }.count,
                      achievements: achievements)
            return
        }

        let dictionary = json as? [String: Any] ?? [:]
        let groups = dictionary.arrayOfDictionaries(for: ["groups"])
        let groupedAchievements = Self.achievements(fromGroups: groups)
        let rawAchievements = dictionary.arrayOfDictionaries(for: ["achievements", "data", "items", "results"])
        let achievements = groupedAchievements.isEmpty ? rawAchievements.map { XBLiveAchievement(json: $0) } : groupedAchievements
        self.init(
            totalScore: dictionary.flexibleInt(for: ["achievement_score", "achievementScore", "gamerscore", "score", "total_score"]) ??
                Self.sum(groups: groups, keys: ["earnedPoints", "earned_points", "score", "earned_score"]),
            totalCount: dictionary.flexibleInt(for: ["achievement_count", "achievementCount", "total", "total_count"]) ??
                Self.sum(groups: groups, keys: ["totalCount", "total_count", "count"]) ?? achievements.count,
            unlockedCount: dictionary.flexibleInt(for: ["unlocked_count", "unlockedCount", "earned", "earned_count"]) ??
                Self.sum(groups: groups, keys: ["unlockedCount", "unlocked_count", "earnedCount", "earned_count"]),
            achievements: achievements
        )
    }

    private static func achievements(fromGroups groups: [[String: Any]]) -> [XBLiveAchievement] {
        groups.flatMap { group in
            let groupID = group.flexibleString(for: ["groupId", "group_id", "id"])
            let groupTitleID = group.flexibleString(for: ["titleId", "title_id", "gameTitleId", "game_title_id"])?.uppercased()
            let groupTitle = group.flexibleString(for: ["displayName", "display_name", "title", "name", "game", "gameName"]) ??
                XBLiveAchievement.defaultTitle(forGroupID: groupID, category: nil)
            let groupIcon = group.flexibleString(for: ["imageUrl", "image_url", "iconUrl", "icon_url", "thumbnail", "thumbnailUrl"])
            return group.arrayOfDictionaries(for: ["achievements", "items", "results"]).map { achievement in
                XBLiveAchievement(json: achievement,
                                  inheritedGameTitle: groupTitle,
                                  inheritedGameTitleID: groupTitleID,
                                  inheritedGameIconURLString: groupIcon,
                                  inheritedGroupID: groupID)
            }
        }
    }

    private static func sum(groups: [[String: Any]], keys: [String]) -> Int? {
        let values = groups.compactMap { $0.flexibleInt(for: keys) }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

struct XBLiveAchievement: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let gameTitle: String?
    let gameTitleID: String?
    let groupID: String?
    let category: String?
    let description: String?
    let score: Int?
    let iconURLString: String?
    let gameIconURLString: String?
    let isUnlocked: Bool?
    let unlockedAt: String?

    var iconURL: URL? { iconURLString.flatMap(URL.init(string:)) }
    var gameIconURL: URL? { gameIconURLString.flatMap(URL.init(string:)) }

    init(json: [String: Any],
         inheritedGameTitle: String? = nil,
         inheritedGameTitleID: String? = nil,
         inheritedGameIconURLString: String? = nil,
         inheritedGroupID: String? = nil) {
        id = json.flexibleString(for: ["id", "achievement_id", "achievementId", "key"]) ?? UUID().uuidString
        title = json.flexibleString(for: ["title", "name", "achievement_name", "achievementName"]) ?? "Achievement"
        groupID = inheritedGroupID ?? json.flexibleString(for: ["groupId", "group_id", "group", "category_id", "categoryId"])
        category = json.flexibleString(for: ["category", "type"])
        gameTitle = json.flexibleString(for: ["game", "game_name", "gameName", "title_name", "titleName"]) ??
            inheritedGameTitle ??
            Self.defaultTitle(forGroupID: groupID, category: category)
        gameTitleID = (json.flexibleString(for: ["title_id", "titleId", "game_title_id", "gameTitleId", "game_id", "gameId"]) ?? inheritedGameTitleID)?.uppercased()
        description = json.flexibleString(for: ["description", "desc", "body"])
        score = json.flexibleInt(for: ["score", "gamerscore", "points", "value"])
        iconURLString = json.flexibleString(for: ["icon", "icon_url", "iconUrl", "image", "image_url", "imageUrl"])
        gameIconURLString = json.flexibleString(for: ["gameIconUrl", "game_icon_url", "gameImageUrl", "game_image_url", "titleImageUrl", "title_image_url"]) ??
            inheritedGameIconURLString
        isUnlocked = json.flexibleBool(for: ["unlocked", "earned", "achieved", "is_unlocked", "isUnlocked"])
        unlockedAt = json.flexibleString(for: ["unlocked_at", "unlockedAt", "earned_at", "earnedAt", "date"])
    }

    static func defaultTitle(forGroupID groupID: String?, category: String?) -> String? {
        let normalizedGroupID = groupID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedGroupID == "xbl_core" || normalizedCategory == "xbl core" {
            return "XBL Core"
        }
        return nil
    }
}

struct XBLiveEvent: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let gameName: String?
    let gameImage: String?
    let description: String?
    let eventDate: String?
    let startTime: String?
    let endTime: String?
    let dlcRequired: Bool?
    let moddedContentRequired: Bool?
    let communityHost: String?
    let eventTag: String?
    let xlinkKai: Bool?
    let isLeaderboard: Bool?
    let bannerURLString: String?
    let source: String?
    let createdBy: String?
    let discordEventID: String?
    let discordGuildID: String?
    let eventTimezone: String?
    let eventEndDate: String?
    let startDateUTC: String?
    let startDateTimeUTC: String?
    let endDateUTC: String?
    let endDateTimeUTC: String?
    let additionalRules: String?
    let winningParameters: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case gameName = "game_name"
        case gameImage = "game_image"
        case description
        case eventDate = "event_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case dlcRequired = "dlc_required"
        case moddedContentRequired = "modded_content_required"
        case communityHost = "community_host"
        case eventTag = "event_tag"
        case xlinkKai = "xlink_kai"
        case isLeaderboard = "is_leaderboard"
        case bannerURLString = "banner_url"
        case source
        case createdBy = "created_by"
        case discordEventID = "discord_event_id"
        case discordGuildID = "discord_guild_id"
        case eventTimezone = "event_timezone"
        case eventEndDate = "event_end_date"
        case startDateUTC = "start_date_utc"
        case startDateTimeUTC = "start_datetime_utc"
        case endDateUTC = "end_date_utc"
        case endDateTimeUTC = "end_datetime_utc"
        case additionalRules = "additional_rules"
        case winningParameters = "winning_parameters"
    }

    var gameImageURL: URL? { gameImage.flatMap(URL.init(string:)) }
    var bannerURL: URL? { bannerURLString.flatMap(URL.init(string:)) }

    var startDate: Date? {
        if let date = Self.parsedUTCDate(date: startDateUTC, time: startDateTimeUTC) {
            return date
        }
        return Self.parsedLocalDate(date: eventDate, time: startTime, timeZoneID: eventTimezone)
    }

    var endDate: Date? {
        let date = Self.parsedUTCDate(date: endDateUTC, time: endDateTimeUTC) ??
            Self.parsedLocalDate(date: eventEndDate ?? eventDate, time: endTime, timeZoneID: eventTimezone)

        guard let startDate, let date else {
            return date
        }

        if date < startDate {
            return Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: date)
        }
        return date
    }

    var scheduleText: String {
        guard let startDate else {
            return [eventDate, startTime]
                .compactMap { Self.trimmed($0) }
                .joined(separator: " ")
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let startText = formatter.string(from: startDate)

        guard let endDate else {
            return startText
        }

        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = .current
            timeFormatter.timeStyle = .short
            return "\(startText) - \(timeFormatter.string(from: endDate))"
        }

        return "\(startText) - \(formatter.string(from: endDate))"
    }

    static func currentEvents(from events: [XBLiveEvent], referenceDate: Date = Date()) -> [XBLiveEvent] {
        events
            .filter { $0.startsWithinNext24Hours(referenceDate: referenceDate) }
            .sorted(by: startDateSort)
    }

    private func startsWithinNext24Hours(referenceDate: Date) -> Bool {
        guard let startDate else {
            return false
        }

        let windowEnd = referenceDate.addingTimeInterval(24 * 60 * 60)
        if startDate >= referenceDate && startDate <= windowEnd {
            return true
        }

        if let endDate {
            return startDate <= referenceDate && endDate >= referenceDate
        }

        return false
    }

    private static func startDateSort(_ lhs: XBLiveEvent, _ rhs: XBLiveEvent) -> Bool {
        switch (lhs.startDate, rhs.startDate) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func parsedUTCDate(date: String?, time: String?) -> Date? {
        let utc = TimeZone(secondsFromGMT: 0)
        if let time = trimmed(time),
           (time.contains("-") || time.contains("T")),
           let date = parsedDateTime(time, timeZone: utc) {
            return date
        }
        return parsedDate(date: date, time: time, timeZone: utc)
    }

    private static func parsedLocalDate(date: String?, time: String?, timeZoneID: String?) -> Date? {
        let timeZone = trimmed(timeZoneID).flatMap(TimeZone.init(identifier:)) ?? .current
        return parsedDate(date: date, time: time, timeZone: timeZone)
    }

    private static func parsedDate(date: String?, time: String?, timeZone: TimeZone?) -> Date? {
        guard let date = trimmed(date) else {
            return nil
        }

        if date.contains("T"),
           let parsedDate = parsedDateTime(date, timeZone: timeZone) {
            return parsedDate
        }

        let time = trimmed(time) ?? "00:00"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a", "yyyy-MM-dd h:mm:ss a"] {
            formatter.dateFormat = format
            if let parsedDate = formatter.date(from: "\(date) \(time)") {
                return parsedDate
            }
        }

        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }

    private static func parsedDateTime(_ value: String, timeZone: TimeZone?) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct InsigniaDashboardView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    }
}

enum InsigniaPublicService {
    static let dashboardURL = URL(string: "https://insignia.live/dashboard/")!
    static let gamesURL = URL(string: "https://insignia.live/games")!

    static func fetchLiveStatusSnapshot() async throws -> InsigniaLiveStatusSnapshot {
        async let publicSnapshot = fetchPublicSnapshot()
        async let supportedGames = fetchSupportedGames()

        let (snapshot, games) = try await (publicSnapshot, supportedGames)
        return InsigniaLiveStatusSnapshot(
            supportedGames: games,
            activeGames: snapshot.activeGames
        )
    }

    static func fetchPublicSnapshot() async throws -> InsigniaPublicSnapshot {
        let url = URL(string: "https://insignia.live/")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw ServiceError.unavailable
        }

        return InsigniaPublicSnapshot(
            registeredUsers: firstStatistic(named: "Registered Users", in: html) ?? "Unknown",
            gamesSupported: firstStatistic(named: "Games Supported", in: html) ?? "Unknown",
            usersOnline: firstStatistic(named: "Users Online Now", in: html) ?? "Unknown",
            activeGames: activeGames(from: html)
        )
    }

    static func fetchSupportedGames() async throws -> [InsigniaSupportedGame] {
        let (data, response) = try await URLSession.shared.data(from: gamesURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw ServiceError.unavailable
        }

        return supportedGames(from: html)
    }

    private static func firstStatistic(named label: String, in html: String) -> String? {
        let pattern = "<h3>\\s*([0-9,]+)\\s*</h3>\\s*<p>\\s*\(NSRegularExpression.escapedPattern(for: label))\\s*</p>"
        return firstMatch(pattern: pattern, in: html).first
    }

    private static func activeGames(from html: String) -> [InsigniaActiveGame] {
        let pattern = #"<tr>\s*<td>\s*<a href="[^"]+">\s*<img[^>]*\bsrc="([^"]+)"[\s\S]*?</a>\s*<a href="[^"]+">([\s\S]*?)</a>\s*<br />\s*<small[^>]*>([\s\S]*?)</small>\s*</td>\s*<td>\s*([\s\S]*?)<br />\s*<small[^>]*>([\s\S]*?)</small>\s*</td>\s*<td[^>]*>\s*([0-9]+)\s*</td>\s*<td[^>]*>\s*([\s\S]*?)\s*</td>"#

        return matches(pattern: pattern, in: html)
            .compactMap { captures -> InsigniaActiveGame? in
                guard captures.count == 7 else {
                    return nil
                }

                let iconUrl = absoluteInsigniaURLString(captures[0])
                let title = cleanedHTML(captures[1])
                let subtitle = cleanedHTML(captures[2])
                let publisherCode = cleanedHTML(captures[3])
                let titleID = cleanedHTML(captures[4])
                let onlineUsers = cleanedHTML(captures[5])
                let activePlayers = cleanedHTML(captures[6])
                let serial = [publisherCode, titleID]
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                let detailParts = [serial, activePlayers]
                    .filter { !$0.isEmpty && $0 != "-" }
                let detail = detailParts.isEmpty ? "Public activity" : detailParts.joined(separator: " - ")

                return InsigniaActiveGame(
                    id: titleID.isEmpty ? title : titleID,
                    title: title.isEmpty ? subtitle : title,
                    serial: serial,
                    onlineUsers: onlineUsers,
                    detail: detail,
                    iconUrl: iconUrl
                )
            }
    }

    private static func supportedGames(from html: String) -> [InsigniaSupportedGame] {
        let pattern = #"<tr>\s*<td>\s*<a href="[^"]+">\s*<img[^>]*\bsrc="([^"]+)"[\s\S]*?</a>\s*<a href="[^"]+">([\s\S]*?)</a>\s*<br />\s*<small[^>]*>([\s\S]*?)</small>\s*</td>\s*<td>\s*([\s\S]*?)<br />\s*<small[^>]*>([\s\S]*?)</small>\s*</td>"#

        return matches(pattern: pattern, in: html)
            .compactMap { captures -> InsigniaSupportedGame? in
                guard captures.count == 5 else {
                    return nil
                }

                let iconUrl = absoluteInsigniaURLString(captures[0])
                let title = cleanedHTML(captures[1])
                let subtitle = cleanedHTML(captures[2])
                let publisherCode = cleanedHTML(captures[3])
                let titleID = cleanedHTML(captures[4]).uppercased()
                guard !titleID.isEmpty else {
                    return nil
                }

                return InsigniaSupportedGame(
                    id: titleID,
                    title: title.isEmpty ? subtitle : title,
                    subtitle: subtitle,
                    serial: publisherCode,
                    titleID: titleID,
                    iconUrl: iconUrl
                )
            }
    }

    private static func firstMatch(pattern: String, in text: String) -> [String] {
        matches(pattern: pattern, in: text).first ?? []
    }

    private static func matches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    private static func cleanedHTML(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = withoutTags
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = collapsed.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return collapsed
        }

        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func absoluteInsigniaURLString(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(string: trimmed, relativeTo: URL(string: "https://insignia.live"))?.absoluteString
    }

    enum ServiceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Insignia service metadata is unavailable."
        }
    }
}

enum InsigniaAuthService {
    private static let baseURL = URL(string: "https://auth.insigniastats.live/api")!

    static func login(email: String, password: String) async throws -> (sessionKey: String, username: String, email: String?) {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LoginRequest(email: email, password: password, specialAccess: "dukex")
        )

        let response: LoginResponse = try await decodedResponse(for: request)
        guard response.success == true,
              let sessionKey = response.sessionKey,
              let username = response.username else {
            throw AuthError.serverMessage(response.error ?? "Insignia sign in failed.")
        }

        return (sessionKey, username, response.email ?? email)
    }

    static func logout(sessionKey: String) async {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/logout"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["sessionKey": sessionKey])
        _ = try? await URLSession.shared.data(for: request)
    }

    static func verify(sessionKey: String) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["sessionKey": sessionKey])

        guard let response: VerifyResponse = try? await decodedResponse(for: request) else {
            return false
        }
        return response.valid == true
    }

    static func fetchProfile(sessionKey: String, refresh: Bool) async throws -> InsigniaAuthenticatedProfile {
        try await authenticatedResponse(
            path: refresh ? "auth/refresh/profile" : "auth/profile",
            method: refresh ? "POST" : "GET",
            sessionKey: sessionKey
        )
    }

    static func fetchFriends(sessionKey: String, refresh: Bool) async throws -> FriendsResponse {
        try await authenticatedResponse(
            path: refresh ? "auth/refresh/friends" : "auth/friends",
            method: refresh ? "POST" : "GET",
            sessionKey: sessionKey
        )
    }

    static func fetchGames(sessionKey: String, refresh: Bool) async throws -> GamesResponse {
        try await authenticatedResponse(
            path: refresh ? "auth/refresh/games" : "auth/games",
            method: refresh ? "POST" : "GET",
            sessionKey: sessionKey
        )
    }

    static func fetchMessages(sessionKey: String, refresh: Bool) async throws -> MessagesResponse {
        try await authenticatedResponse(
            path: refresh ? "auth/refresh/messages" : "auth/messages",
            method: refresh ? "POST" : "GET",
            sessionKey: sessionKey
        )
    }

    private static func authenticatedResponse<T: Decodable>(
        path: String,
        method: String,
        sessionKey: String
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")
        return try await decodedResponse(for: request)
    }

    private static func decodedResponse<T: Decodable>(for request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.unavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }

            if let error = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let message = error.error {
                throw AuthError.serverMessage(message)
            }

            throw AuthError.unavailable
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    struct LoginRequest: Encodable {
        let email: String
        let password: String
        let specialAccess: String

        enum CodingKeys: String, CodingKey {
            case email
            case password
            case specialAccess = "special_access"
        }
    }

    struct LoginResponse: Decodable {
        let success: Bool?
        let username: String?
        let email: String?
        let sessionKey: String?
        let specialAccess: String?
        let error: String?
    }

    struct VerifyResponse: Decodable {
        let valid: Bool?
    }

    struct FriendsResponse: Decodable {
        let friends: [InsigniaFriend]
        let lastUpdated: Double?
        let count: Int
    }

    struct GamesResponse: Decodable {
        let games: [InsigniaProfileGame]
        let lastUpdated: Double?
        let count: Int
    }

    struct MessagesResponse: Decodable {
        let messages: [InsigniaMessage]
        let lastUpdated: Double?
        let count: Int
    }

    struct APIErrorResponse: Decodable {
        let error: String?
    }

    enum AuthError: LocalizedError {
        case serverMessage(String)
        case unauthorized
        case unavailable

        var errorDescription: String? {
            switch self {
            case .serverMessage(let message):
                return message
            case .unauthorized:
                return "The Insignia session is no longer valid."
            case .unavailable:
                return "The Insignia auth service is unavailable."
            }
        }
    }
}

enum XBLiveService {
    private static let baseURL = URL(string: "https://xb.live/api")!

    static func fetchProfile(username: String) async throws -> XBLiveProfileSnapshot {
        let response: ProfileResponse = try await decodedResponse(pathComponents: ["profile", username])
        let isOnline = response.playTime.lastState?.lowercased() == "online" || response.playTime.currentGame != nil
        let hasLastPlayedGame = response.playTime.lastPlayedGame?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let lastPlayedAt = hasLastPlayedGame ? response.playTime.lastPlayedAt : nil
        let lastOnlineAt = response.playTime.lastOnlineAt ??
            (isOnline ? response.playTime.lastCheckedAt : lastPlayedAt)
        return XBLiveProfileSnapshot(
            username: response.username,
            avatarURLString: response.profile.avatarURLString,
            linkedGamertag: response.profile.linkedGamertag,
            isOnline: isOnline,
            lastState: response.playTime.lastState,
            currentGame: response.playTime.currentGame,
            lastPlayedGame: response.playTime.lastPlayedGame,
            lastPlayedAt: lastPlayedAt,
            lastOnlineAt: lastOnlineAt,
            lastCheckedAt: response.playTime.lastCheckedAt,
            totalMinutes: response.playTime.totalMinutes,
            achievementScore: response.achievementScore,
            achievementCount: response.achievementCount
        )
    }

    static func fetchGamesPlayed(username: String) async throws -> [XBLiveGamePlayed] {
        let response: GamesPlayedResponse = try await decodedResponse(pathComponents: ["profile", username, "games-played"])
        return response.games
    }

    static func fetchAchievements(username: String) async throws -> XBLiveAchievementsSnapshot {
        let json = try await jsonObject(pathComponents: ["profile", username, "achievements"])
        return XBLiveAchievementsSnapshot(json: json)
    }

    static func fetchEvents() async throws -> [XBLiveEvent] {
        try await decodedResponse(pathComponents: ["events"])
    }

    private static func decodedResponse<T: Decodable>(pathComponents: [String]) async throws -> T {
        let url = endpointURL(pathComponents: pathComponents)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ServiceError.unavailable
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func jsonObject(pathComponents: [String]) async throws -> Any {
        let url = endpointURL(pathComponents: pathComponents)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ServiceError.unavailable
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    private static func endpointURL(pathComponents: [String]) -> URL {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/%?#")
        let path = pathComponents
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? $0 }
            .joined(separator: "/")
        return URL(string: "\(baseURL.absoluteString)/\(path)")!
    }

    struct ProfileResponse: Decodable {
        let username: String
        let profile: Profile
        let playTime: PlayTime
        let achievementScore: Int?
        let achievementCount: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ProfileFlexibleCodingKey.self)
            username = container.flexibleString(for: ["username", "gamertag", "displayName", "display_name"]) ?? "Unknown"
            profile = (try? container.decode(Profile.self, forKey: ProfileFlexibleCodingKey(stringValue: "profile")!)) ??
                Profile(avatarURLString: nil, linkedGamertag: nil)
            playTime = (try? container.decode(PlayTime.self, forKey: ProfileFlexibleCodingKey(stringValue: "playTime")!)) ??
                (try? container.decode(PlayTime.self, forKey: ProfileFlexibleCodingKey(stringValue: "play_time")!)) ??
                PlayTime(totalMinutes: nil, lastState: nil, currentGame: nil, lastPlayedGame: nil, lastPlayedAt: nil, lastOnlineAt: nil, lastCheckedAt: nil)
            achievementScore = container.flexibleInt(for: [
                "achievementScore",
                "achievement_score",
                "gamerscore",
                "score",
                "totalScore",
                "total_score"
            ])
            achievementCount = container.flexibleInt(for: [
                "achievementCount",
                "achievement_count",
                "achievements",
                "totalAchievements",
                "total_achievements",
                "totalCount",
                "total_count"
            ])
        }

        struct Profile: Decodable {
            let avatarURLString: String?
            let linkedGamertag: String?

            init(avatarURLString: String?, linkedGamertag: String?) {
                self.avatarURLString = avatarURLString
                self.linkedGamertag = linkedGamertag
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: ProfileFlexibleCodingKey.self)
                avatarURLString = container.flexibleString(for: [
                    "avatar_url",
                    "avatarURL",
                    "avatarUrl",
                    "avatar",
                    "image_url",
                    "imageUrl"
                ])
                linkedGamertag = container.flexibleString(for: [
                    "linked_gamertag",
                    "linkedGamertag",
                    "gamertag",
                    "xboxGamertag",
                    "xbox_gamertag"
                ])
            }
        }

        struct PlayTime: Decodable {
            let totalMinutes: Double?
            let lastState: String?
            let currentGame: String?
            let lastPlayedGame: String?
            let lastPlayedAt: Double?
            let lastOnlineAt: Double?
            let lastCheckedAt: Double?

            init(
                totalMinutes: Double?,
                lastState: String?,
                currentGame: String?,
                lastPlayedGame: String?,
                lastPlayedAt: Double?,
                lastOnlineAt: Double?,
                lastCheckedAt: Double?
            ) {
                self.totalMinutes = totalMinutes
                self.lastState = lastState
                self.currentGame = currentGame
                self.lastPlayedGame = lastPlayedGame
                self.lastPlayedAt = lastPlayedAt
                self.lastOnlineAt = lastOnlineAt
                self.lastCheckedAt = lastCheckedAt
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: ProfileFlexibleCodingKey.self)
                let minutes = container.flexibleDouble(for: [
                    "totalMinutes",
                    "total_minutes",
                    "minutes",
                    "playtimeMinutes",
                    "playtime_minutes",
                    "playTimeMinutes",
                    "play_time_minutes"
                ])
                let seconds = container.flexibleDouble(for: [
                    "totalSeconds",
                    "total_seconds",
                    "seconds",
                    "playtimeSeconds",
                    "playtime_seconds",
                    "playTimeSeconds",
                    "play_time_seconds"
                ])
                let hours = container.flexibleDouble(for: [
                    "totalHours",
                    "total_hours",
                    "hours",
                    "playtimeHours",
                    "playtime_hours",
                    "playTimeHours",
                    "play_time_hours"
                ])

                totalMinutes = minutes ?? seconds.map { $0 / 60.0 } ?? hours.map { $0 * 60.0 }
                lastState = container.flexibleString(for: [
                    "lastState",
                    "last_state",
                    "state",
                    "status"
                ])
                currentGame = container.flexibleString(for: [
                    "currentGame",
                    "current_game",
                    "activeGame",
                    "active_game",
                    "game"
                ])
                lastPlayedGame = container.flexibleString(for: [
                    "lastPlayedGame",
                    "last_played_game",
                    "lastGame",
                    "last_game",
                    "lastTitle",
                    "last_title"
                ])
                lastPlayedAt = container.flexibleTimestamp(for: [
                    "lastPlayedAt",
                    "last_played_at",
                    "lastPlayedTimestamp",
                    "last_played_timestamp"
                ])
                lastOnlineAt = container.flexibleTimestamp(for: [
                    "lastOnlineAt",
                    "last_online_at",
                    "lastSeenAt",
                    "last_seen_at",
                    "lastActiveAt",
                    "last_active_at",
                    "seenAt",
                    "seen_at"
                ])
                lastCheckedAt = container.flexibleTimestamp(for: [
                    "lastCheckTs",
                    "last_check_ts",
                    "lastCheckedAt",
                    "last_checked_at",
                    "checkedAt",
                    "checked_at"
                ])
            }
        }
    }

    struct GamesPlayedResponse: Decodable {
        let games: [XBLiveGamePlayed]
    }

    enum ServiceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "xb.live profile data is unavailable."
        }
    }
}

@MainActor
final class InsigniaProfileStore: ObservableObject {
    @Published private(set) var session: InsigniaProfileSession?
    @Published private(set) var publicSnapshot: InsigniaPublicSnapshot?
    @Published private(set) var authenticatedSnapshot: InsigniaAuthenticatedSnapshot?
    @Published private(set) var profileImage: UIImage?
    @Published private(set) var friendProfileImages: [String: UIImage] = [:]
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var isRefreshing = false
    @Published private var viewedMessageKeys: Set<String> = []

    private static let gamertagKey = "InsigniaProfileGamertag"
    private static let emailKey = "InsigniaProfileEmail"
    private static let isAuthenticatedKey = "InsigniaProfileIsAuthenticated"
    private static let signedInAtKey = "InsigniaProfileSignedInAt"
    private static let lastRefreshedKey = "InsigniaProfileLastRefreshedAt"
    private static let publicSnapshotKey = "InsigniaPublicSnapshot"
    private static let authenticatedSnapshotKey = "InsigniaAuthenticatedSnapshot"
    private static let viewedMessagesKeyPrefix = "InsigniaProfileViewedMessages"
    private static let profileImageFileName = "profile-picture.jpg"

    var isSignedIn: Bool {
        session != nil
    }

    var isAuthenticatedForCloudServices: Bool {
        session?.isAuthenticated == true
    }

    nonisolated static func storedSessionKey() throws -> String? {
        try ProfileSessionKeychain.loadSessionKey()
    }

    var registeredUsersText: String {
        publicSnapshot?.registeredUsers ?? "Not Synced"
    }

    var gamesSupportedText: String {
        publicSnapshot?.gamesSupported ?? "Not Synced"
    }

    var usersOnlineText: String {
        publicSnapshot?.usersOnline ?? "Not Synced"
    }

    var activeGames: [InsigniaActiveGame] {
        publicSnapshot?.activeGames ?? []
    }

    init() {
        let defaults = UserDefaults.standard
        if let gamertag = defaults.string(forKey: Self.gamertagKey), !gamertag.isEmpty {
            let signedInAt = defaults.object(forKey: Self.signedInAtKey) as? Date ?? Date()
            let email = defaults.string(forKey: Self.emailKey)
            let isAuthenticated = defaults.object(forKey: Self.isAuthenticatedKey) as? Bool ?? false
            session = InsigniaProfileSession(
                gamertag: gamertag,
                email: email,
                signedInAt: signedInAt,
                isAuthenticated: isAuthenticated
            )
        }
        lastRefreshed = defaults.object(forKey: Self.lastRefreshedKey) as? Date
        publicSnapshot = Self.loadPublicSnapshot()
        authenticatedSnapshot = Self.loadAuthenticatedSnapshot()
        viewedMessageKeys = Self.loadViewedMessageKeys(for: session)
        loadProfileImage()
        loadFriendProfileImages()
    }

    func signIn(email: String, password: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            throw ProfileSignInError.missingCredentials
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let login = try await InsigniaAuthService.login(email: trimmedEmail, password: password)
        try ProfileSessionKeychain.saveSessionKey(login.sessionKey)

        let signedInAt = Date()
        session = InsigniaProfileSession(
            gamertag: login.username,
            email: login.email,
            signedInAt: signedInAt,
            isAuthenticated: true
        )
        viewedMessageKeys = Self.loadViewedMessageKeys(for: session)

        let defaults = UserDefaults.standard
        defaults.set(login.username, forKey: Self.gamertagKey)
        defaults.set(login.email, forKey: Self.emailKey)
        defaults.set(true, forKey: Self.isAuthenticatedKey)
        defaults.set(signedInAt, forKey: Self.signedInAtKey)
        defaults.removeObject(forKey: Self.lastRefreshedKey)
        lastRefreshed = nil

        try await loadAuthenticatedData(refreshRemote: false)
    }

    func signIn(gamertag: String) throws {
        let trimmed = gamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProfileSignInError.missingGamertag
        }

        let signedInAt = Date()
        session = InsigniaProfileSession(
            gamertag: trimmed,
            email: nil,
            signedInAt: signedInAt,
            isAuthenticated: false
        )
        viewedMessageKeys = Self.loadViewedMessageKeys(for: session)
        lastRefreshed = nil

        let defaults = UserDefaults.standard
        defaults.set(trimmed, forKey: Self.gamertagKey)
        defaults.removeObject(forKey: Self.emailKey)
        defaults.set(false, forKey: Self.isAuthenticatedKey)
        defaults.set(signedInAt, forKey: Self.signedInAtKey)
        defaults.removeObject(forKey: Self.lastRefreshedKey)
        try? ProfileSessionKeychain.deleteSessionKey()
    }

    func signOut() {
        let sessionKey = try? ProfileSessionKeychain.loadSessionKey()
        if let sessionKey {
            Task {
                await InsigniaAuthService.logout(sessionKey: sessionKey)
            }
        }

        session = nil
        lastRefreshed = nil
        isRefreshing = false
        authenticatedSnapshot = nil
        viewedMessageKeys = []

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.gamertagKey)
        defaults.removeObject(forKey: Self.emailKey)
        defaults.removeObject(forKey: Self.isAuthenticatedKey)
        defaults.removeObject(forKey: Self.signedInAtKey)
        defaults.removeObject(forKey: Self.lastRefreshedKey)
        defaults.removeObject(forKey: Self.authenticatedSnapshotKey)
        try? ProfileSessionKeychain.deleteSessionKey()
    }

    func assignProfileImage(_ data: Data) throws {
        let image = UIImage(data: data)
        let imageData = image?.jpegData(compressionQuality: 0.9) ?? data
        try FileManager.default.createDirectory(at: profileDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try imageData.write(to: profileImageURL, options: .atomic)
        profileImage = UIImage(data: imageData)
    }

    func assignFriendProfileImage(_ data: Data, to friend: InsigniaFriend) throws {
        try assignFriendProfileImage(data, key: friend.key)
    }

    func assignFriendProfileImage(_ data: Data, key: String) throws {
        let image = UIImage(data: data)
        let imageData = image?.jpegData(compressionQuality: 0.9) ?? data
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try FileManager.default.createDirectory(
            at: friendProfileImagesDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try imageData.write(to: friendProfileImageURL(for: normalizedKey), options: .atomic)
        friendProfileImages[normalizedKey] = UIImage(data: imageData)
    }

    func clearProfileImage() {
        try? FileManager.default.removeItem(at: profileImageURL)
        profileImage = nil
    }

    func refresh() {
        guard isSignedIn, !isRefreshing else {
            return
        }

        isRefreshing = true
        Task { @MainActor in
            defer { isRefreshing = false }

            do {
                if session?.isAuthenticated == true {
                    try await loadAuthenticatedData(refreshRemote: true, refreshFriendProfiles: true)
                } else {
                    let snapshot = try await InsigniaPublicService.fetchPublicSnapshot()
                    publicSnapshot = snapshot
                    Self.savePublicSnapshot(snapshot)
                    markRefreshed()
                }
            } catch InsigniaAuthService.AuthError.unauthorized {
                signOut()
            } catch {
            }
        }
    }

    func unviewedMessages(from messages: [InsigniaMessage]) -> [InsigniaMessage] {
        messages.filter { !viewedMessageKeys.contains(Self.messageViewedKey($0)) }
    }

    func markMessageViewed(_ message: InsigniaMessage) {
        let key = Self.messageViewedKey(message)
        guard !viewedMessageKeys.contains(key) else {
            return
        }

        viewedMessageKeys.insert(key)
        Self.saveViewedMessageKeys(viewedMessageKeys, for: session)
    }

    private func loadAuthenticatedData(
        refreshRemote: Bool,
        refreshFriendProfiles: Bool = true
    ) async throws {
        guard let session,
              let sessionKey = try? ProfileSessionKeychain.loadSessionKey() else {
            throw ProfileSignInError.missingSession
        }

        let profile = try? await InsigniaAuthService.fetchProfile(sessionKey: sessionKey, refresh: refreshRemote)
        let friendsResponse = try? await InsigniaAuthService.fetchFriends(sessionKey: sessionKey, refresh: refreshRemote)
        let gamesResponse = try? await InsigniaAuthService.fetchGames(sessionKey: sessionKey, refresh: refreshRemote)
        let messagesResponse = try? await InsigniaAuthService.fetchMessages(sessionKey: sessionKey, refresh: refreshRemote)
        let xbProfile = try? await XBLiveService.fetchProfile(username: session.gamertag)
        let playtimeGames = (try? await XBLiveService.fetchGamesPlayed(username: session.gamertag)) ??
            authenticatedSnapshot?.playtimeGames ??
            []
        let achievements = try? await XBLiveService.fetchAchievements(username: session.gamertag)
        let livePublicSnapshot = try? await InsigniaPublicService.fetchPublicSnapshot()
        let supportedGames = (try? await InsigniaPublicService.fetchSupportedGames()) ?? []
        let events = (try? await XBLiveService.fetchEvents()) ?? []

        let cachedFriends = authenticatedSnapshot?.friends ?? []
        let fetchedFriends = friendsResponse?.friends
        let shouldUseFetchedFriends = fetchedFriends?.isEmpty == false || cachedFriends.isEmpty
        let friends = shouldUseFetchedFriends ? fetchedFriends ?? [] : cachedFriends
        let existingFriendProfiles = authenticatedSnapshot?.friendProfiles ?? [:]
        let friendProfiles: [String: XBLiveFriendProfile]
        if refreshFriendProfiles {
            friendProfiles = await fetchFriendProfiles(
                for: friends,
                existingProfiles: existingFriendProfiles
            )
        } else {
            let currentFriendKeys = Set(friends.map(\.key))
            var retainedProfiles = existingFriendProfiles.filter { currentFriendKeys.contains($0.key) }
            let missingProfileFriends = friends.filter { retainedProfiles[$0.key] == nil }
            if !missingProfileFriends.isEmpty {
                let missingProfiles = await fetchFriendProfiles(
                    for: missingProfileFriends,
                    existingProfiles: [:]
                )
                retainedProfiles.merge(missingProfiles) { _, new in new }
            }
            friendProfiles = retainedProfiles
        }

        if let livePublicSnapshot {
            publicSnapshot = livePublicSnapshot
            Self.savePublicSnapshot(livePublicSnapshot)
        }

        let snapshot = InsigniaAuthenticatedSnapshot(
            profile: profile,
            friends: friends,
            games: gamesResponse?.games ?? profile?.gamesPlayed ?? [],
            messages: messagesResponse?.messages ?? [],
            xbProfile: xbProfile,
            playtimeGames: playtimeGames,
            achievements: achievements,
            friendProfiles: friendProfiles,
            events: XBLiveEvent.currentEvents(from: events),
            supportedGames: supportedGames,
            loadedAt: Date()
        )

        authenticatedSnapshot = snapshot
        Self.saveAuthenticatedSnapshot(snapshot)
        markRefreshed()
    }

    private func fetchFriendProfiles(
        for friends: [InsigniaFriend],
        existingProfiles: [String: XBLiveFriendProfile]
    ) async -> [String: XBLiveFriendProfile] {
        let currentFriendKeys = Set(friends.map(\.key))
        var profiles = existingProfiles.filter { currentFriendKeys.contains($0.key) }

        for friend in friends {
            guard let xbProfile = try? await XBLiveService.fetchProfile(username: friend.gamertag) else {
                continue
            }

            let existingProfile = existingProfiles[friend.key]
            let games = (try? await XBLiveService.fetchGamesPlayed(username: friend.gamertag)) ??
                existingProfile?.gamesPlayed ??
                []
            let achievements = (try? await XBLiveService.fetchAchievements(username: friend.gamertag)) ??
                existingProfile?.achievements
            let lastGame = games.first { $0.gameName == xbProfile.lastPlayedGame } ?? games.first
            let totalMinutes = xbProfile.totalMinutes ?? Self.totalMinutes(from: games)
            let isOnline = xbProfile.isOnline
            let currentGame = xbProfile.currentGame ?? (isOnline ? friend.game : nil)
            let lastOnlineAt = Self.lastOnlineTimestamp(
                isOnline: isOnline,
                profile: xbProfile
            )
            profiles[friend.key] = XBLiveFriendProfile(
                gamertag: friend.gamertag,
                avatarURLString: xbProfile.avatarURLString,
                isOnline: isOnline,
                lastState: xbProfile.lastState ?? friend.status,
                currentGame: currentGame,
                lastPlayedGame: xbProfile.lastPlayedGame ?? lastGame?.gameName,
                lastPlayedAt: xbProfile.lastPlayedAt,
                lastOnlineAt: lastOnlineAt,
                lastCheckedAt: xbProfile.lastCheckedAt,
                achievementScore: xbProfile.achievementScore,
                achievementCount: xbProfile.achievementCount,
                totalMinutes: totalMinutes,
                lastPlayedImageURLString: lastGame?.imageUrl,
                gamesPlayed: games,
                achievements: achievements
            )
        }

        return profiles
    }

    private static func lastOnlineTimestamp(
        isOnline: Bool,
        profile: XBLiveProfileSnapshot
    ) -> Double? {
        if isOnline {
            return profile.lastCheckedAt ?? Date().timeIntervalSince1970
        }
        return profile.lastOnlineAt
    }

    private static func totalMinutes(from games: [XBLiveGamePlayed]) -> Double? {
        let values = games.compactMap(\.totalMinutes)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +)
    }

    private func markRefreshed() {
        let refreshedAt = Date()
        lastRefreshed = refreshedAt
        UserDefaults.standard.set(refreshedAt, forKey: Self.lastRefreshedKey)
    }

    private static func loadPublicSnapshot() -> InsigniaPublicSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: publicSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(InsigniaPublicSnapshot.self, from: data)
    }

    private static func savePublicSnapshot(_ snapshot: InsigniaPublicSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        UserDefaults.standard.set(data, forKey: publicSnapshotKey)
    }

    private static func loadAuthenticatedSnapshot() -> InsigniaAuthenticatedSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: authenticatedSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(InsigniaAuthenticatedSnapshot.self, from: data)
    }

    private static func saveAuthenticatedSnapshot(_ snapshot: InsigniaAuthenticatedSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        UserDefaults.standard.set(data, forKey: authenticatedSnapshotKey)
    }

    private static func loadViewedMessageKeys(for session: InsigniaProfileSession?) -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: viewedMessagesDefaultsKey(for: session)) ?? []
        return Set(values)
    }

    private static func saveViewedMessageKeys(_ keys: Set<String>, for session: InsigniaProfileSession?) {
        UserDefaults.standard.set(Array(keys).sorted(), forKey: viewedMessagesDefaultsKey(for: session))
    }

    private static func viewedMessagesDefaultsKey(for session: InsigniaProfileSession?) -> String {
        let normalizedGamertag = session?.gamertag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let gamertag: String
        if let normalizedGamertag, !normalizedGamertag.isEmpty {
            gamertag = normalizedGamertag
        } else {
            gamertag = "default"
        }
        return "\(viewedMessagesKeyPrefix).\(gamertag)"
    }

    private static func messageViewedKey(_ message: InsigniaMessage) -> String {
        [
            message.sender,
            message.type,
            message.game ?? "",
            message.sentAt ?? ""
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: "|")
    }

    private var profileDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Profile", isDirectory: true)
    }

    private var profileImageURL: URL {
        profileDirectoryURL.appendingPathComponent(Self.profileImageFileName)
    }

    private var friendProfileImagesDirectoryURL: URL {
        profileDirectoryURL.appendingPathComponent("Friends", isDirectory: true)
    }

    private func friendProfileImageURL(for key: String) -> URL {
        friendProfileImagesDirectoryURL.appendingPathComponent(Self.friendProfileImageFileName(for: key))
    }

    private func loadProfileImage() {
        guard let data = try? Data(contentsOf: profileImageURL) else {
            profileImage = nil
            return
        }
        profileImage = UIImage(data: data)
    }

    private func loadFriendProfileImages() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: friendProfileImagesDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            friendProfileImages = [:]
            return
        }

        var images: [String: UIImage] = [:]
        for url in urls where url.pathExtension.lowercased() == "jpg" {
            let encodedKey = url.deletingPathExtension().lastPathComponent
            let key = encodedKey.removingPercentEncoding ?? encodedKey
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                continue
            }
            images[key] = image
        }
        friendProfileImages = images
    }

    private static func friendProfileImageFileName(for key: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? key
        return "\(encodedKey).jpg"
    }
}

private enum ProfileSessionKeychain {
    private static let service = "com.mafty.dukex.insignia-auth"
    private static let account = "session-key"

    static func saveSessionKey(_ sessionKey: String) throws {
        try deleteSessionKey()

        let data = Data(sessionKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ProfileSignInError.keychainUnavailable
        }
    }

    static func loadSessionKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = result as? Data else {
            throw ProfileSignInError.keychainUnavailable
        }

        return String(data: data, encoding: .utf8)
    }

    static func deleteSessionKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProfileSignInError.keychainUnavailable
        }
    }
}

private enum ProfileSignInError: LocalizedError {
    case missingGamertag
    case missingCredentials
    case missingSession
    case keychainUnavailable

    var errorDescription: String? {
        switch self {
        case .missingGamertag:
            return "Enter a gamertag to continue."
        case .missingCredentials:
            return "Enter the email and password for your Insignia account."
        case .missingSession:
            return "The Insignia session is missing. Sign in again to continue."
        case .keychainUnavailable:
            return "DukeX could not access the secure session store."
        }
    }
}

private struct ProfileFlexibleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer {
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

private extension KeyedDecodingContainer where Key == ProfileFlexibleCodingKey {
    func flexibleString(for keys: [String]) -> String? {
        for key in keys {
            guard let codingKey = ProfileFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else {
                continue
            }

            if let value = try? decodeIfPresent(String.self, forKey: codingKey),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return String(value)
            }
            if let value = try? decodeIfPresent(Int64.self, forKey: codingKey) {
                return String(value)
            }
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return String(format: "%.0f", value)
            }
        }
        return nil
    }

    func flexibleDouble(for keys: [String]) -> Double? {
        for key in keys {
            guard let codingKey = ProfileFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else {
                continue
            }

            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return Double(value)
            }
            if let value = try? decodeIfPresent(Int64.self, forKey: codingKey) {
                return Double(value)
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey),
               let doubleValue = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return doubleValue
            }
        }
        return nil
    }

    func flexibleTimestamp(for keys: [String]) -> Double? {
        for key in keys {
            guard let codingKey = ProfileFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else {
                continue
            }

            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return normalizedTimestamp(value)
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return normalizedTimestamp(Double(value))
            }
            if let value = try? decodeIfPresent(Int64.self, forKey: codingKey) {
                return normalizedTimestamp(Double(value))
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey),
               let timestamp = timestamp(from: value) {
                return timestamp
            }
        }
        return nil
    }

    func flexibleInt(for keys: [String]) -> Int? {
        for key in keys {
            guard let codingKey = ProfileFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else {
                continue
            }

            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Int64.self, forKey: codingKey) {
                return Int(value)
            }
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return Int(value)
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey),
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
        }
        return nil
    }

    func flexibleBool(for keys: [String]) -> Bool? {
        for key in keys {
            guard let codingKey = ProfileFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else {
                continue
            }

            if let value = try? decodeIfPresent(Bool.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return value != 0
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "yes", "online", "active", "1"].contains(normalized) {
                    return true
                }
                if ["false", "no", "offline", "inactive", "0"].contains(normalized) {
                    return false
                }
            }
        }
        return nil
    }

    private func timestamp(from value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let doubleValue = Double(trimmed) {
            return normalizedTimestamp(doubleValue)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) {
            return date.timeIntervalSince1970
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)?.timeIntervalSince1970
    }

    private func normalizedTimestamp(_ value: Double) -> Double {
        value > 9_999_999_999 ? value / 1_000.0 : value
    }
}

private extension Dictionary where Key == String, Value == Any {
    func flexibleString(for keys: [String]) -> String? {
        for key in keys {
            guard let value = self[key], !(value is NSNull) else {
                continue
            }
            if let string = value as? String,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
            if let int = value as? Int {
                return String(int)
            }
            if let double = value as? Double {
                return String(format: "%.0f", double)
            }
        }
        return nil
    }

    func flexibleInt(for keys: [String]) -> Int? {
        for key in keys {
            guard let value = self[key], !(value is NSNull) else {
                continue
            }
            if let int = value as? Int {
                return int
            }
            if let double = value as? Double {
                return Int(double)
            }
            if let string = value as? String,
               let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return int
            }
        }
        return nil
    }

    func flexibleBool(for keys: [String]) -> Bool? {
        for key in keys {
            guard let value = self[key], !(value is NSNull) else {
                continue
            }
            if let bool = value as? Bool {
                return bool
            }
            if let int = value as? Int {
                return int != 0
            }
            if let string = value as? String {
                switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "earned", "unlocked", "1":
                    return true
                case "false", "no", "locked", "0":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    func arrayOfDictionaries(for keys: [String]) -> [[String: Any]] {
        for key in keys {
            if let array = self[key] as? [[String: Any]] {
                return array
            }
            if let dictionary = self[key] as? [String: Any] {
                return dictionary.arrayOfDictionaries(for: keys)
            }
        }
        return []
    }
}
