import Foundation
import SwiftUI
import UIKit

struct XBLiveNewsTag: Codable, Equatable, Identifiable {
    let id: Int?
    let slug: String?
    let label: String?

    var stableID: String {
        if let id {
            return String(id)
        }
        return slug?.activityTrimmedNonEmpty ?? label?.activityTrimmedNonEmpty ?? UUID().uuidString
    }
}

struct XBLiveNewsArticle: Codable, Equatable, Identifiable {
    let id: Int
    let slug: String
    let title: String
    let summary: String?
    let bodyHtml: String?
    let heroImageUrl: String?
    let heroVideoId: String?
    let authorUsername: String?
    let isFeatured: Bool?
    let publishedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let tags: [XBLiveNewsTag]
    let href: String?

    var publishedDate: Date? {
        XBLiveActivityTimestamp.date(from: publishedAt) ??
            XBLiveActivityTimestamp.date(from: createdAt) ??
            XBLiveActivityTimestamp.date(from: updatedAt)
    }

    var absoluteHeroImageURL: URL? {
        if let heroVideoId = heroVideoId?.activityTrimmedNonEmpty {
            return URL(string: "https://i.ytimg.com/vi/\(heroVideoId)/hqdefault.jpg")
        }

        return XBLiveActivityURL.absoluteURL(from: heroImageUrl)
    }

    var absoluteArticleURL: URL? {
        XBLiveActivityURL.absoluteURL(from: href ?? "/news/\(slug)")
    }

    var readableAuthor: String? {
        authorUsername?.activityTrimmedNonEmpty
    }

    var readableSummary: String? {
        summary?.activityTrimmedNonEmpty
    }
}

@MainActor
final class XBLiveActivityFeedStore: ObservableObject {
    @Published private(set) var articles: [XBLiveNewsArticle] = []
    @Published private(set) var isLoadingNews = false
    @Published private(set) var newsError: String?
    @Published private(set) var readArticleSlugs: Set<String>

    private var articleDetails: [String: XBLiveNewsArticle] = [:]
    private var lastNewsRefreshAt: Date?
    private let defaults: UserDefaults
    private let readDefaultsKey = "DukeXActivityFeedReadArticleSlugs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        readArticleSlugs = Set(defaults.stringArray(forKey: readDefaultsKey) ?? [])
    }

    var unreadArticleCount: Int {
        articles.filter { !readArticleSlugs.contains($0.slug) }.count
    }

    func refreshNewsIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastNewsRefreshAt,
           Date().timeIntervalSince(lastNewsRefreshAt) < maxAge,
           !articles.isEmpty {
            return
        }

        await refreshNews()
    }

    func refreshNews() async {
        guard !isLoadingNews else {
            return
        }

        isLoadingNews = true
        newsError = nil
        defer { isLoadingNews = false }

        do {
            let response = try await Self.fetchNewsResponse()
            articles = response.articles.sorted {
                ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
            }
            lastNewsRefreshAt = Date()
        } catch {
            newsError = error.localizedDescription
        }
    }

    func articleDetail(for article: XBLiveNewsArticle) async -> XBLiveNewsArticle {
        if let cached = articleDetails[article.slug] {
            return cached
        }

        do {
            let detail = try await Self.fetchArticleDetail(slug: article.slug).article
            articleDetails[article.slug] = detail
            return detail
        } catch {
            return article
        }
    }

    func markCurrentArticlesRead() {
        let articleSlugs = articles.map(\.slug)
        guard !articleSlugs.isEmpty else {
            return
        }

        readArticleSlugs.formUnion(articleSlugs)
        defaults.set(readArticleSlugs.sorted(), forKey: readDefaultsKey)
    }

    private static func fetchNewsResponse() async throws -> XBLiveNewsArticlesResponse {
        let url = URL(string: "https://xb.live/api/news/articles?limit=24")!
        return try await fetchJSON(XBLiveNewsArticlesResponse.self, from: url)
    }

    private static func fetchArticleDetail(slug: String) async throws -> XBLiveNewsArticleDetailResponse {
        let escapedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        let url = URL(string: "https://xb.live/api/news/articles/\(escapedSlug)")!
        return try await fetchJSON(XBLiveNewsArticleDetailResponse.self, from: url)
    }

    private static func fetchJSON<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("DukeX iOS Activity Feed", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw XBLiveActivityFeedError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(type, from: data)
    }
}

struct ProfileActivityFeedView: View {
    @ObservedObject var feedStore: XBLiveActivityFeedStore
    @ObservedObject var profileStore: InsigniaProfileStore
    @ObservedObject var socialStore: XBLiveSocialStore

    let installedGames: [LibraryFile]
    let inviteEligibleGames: [LibraryFile]
    let launchGameFromInvite: (LibraryFile) -> Void
    let changeFriendProfileImage: (InsigniaFriend) -> Void
    let changeSocialFriendProfileImage: (XBLiveSocialFriend) -> Void

    private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section("XB.Live") {
                if feedStore.isLoadingNews && feedEntries.isEmpty {
                    ProfileSocialLoadingRow(title: "Loading activity feed...")
                } else if feedEntries.isEmpty {
                    ProfileEmptyRow(title: emptyTitle, systemImage: "newspaper")
                } else {
                    ForEach(feedEntries) { entry in
                        switch entry.kind {
                        case .news:
                            if let article = entry.article {
                                NavigationLink {
                                    ProfileActivityArticleDetailView(article: article, feedStore: feedStore)
                                } label: {
                                    ProfileActivityFeedRow(entry: entry)
                                }
                            }
                        case .friendOnline:
                            NavigationLink {
                                activityFriendDestination(username: entry.friendUsername ?? entry.title)
                            } label: {
                                ProfileActivityFeedRow(entry: entry)
                            }
                        case .achievement:
                            ProfileActivityFeedRow(entry: entry)
                        }
                    }
                }
            }
            .dukeXThemedListRowBackground()

            if let newsError = feedStore.newsError?.activityTrimmedNonEmpty {
                Section {
                    Label(newsError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .dukeXThemedListRowBackground()
            }
        }
        .navigationTitle("Activity Feed")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .refreshable {
            await refreshActivityFeed(forceNewsRefresh: true)
        }
        .task {
            await refreshActivityFeed(forceNewsRefresh: false)
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await refreshActivityFeed(forceNewsRefresh: false)
            }
        }
        .onChange(of: feedStore.articles) { _ in
            feedStore.markCurrentArticlesRead()
        }
    }

    private var snapshot: InsigniaAuthenticatedSnapshot? {
        profileStore.authenticatedSnapshot
    }

    private func refreshActivityFeed(forceNewsRefresh: Bool) async {
        if profileStore.session?.isAuthenticated == true {
            profileStore.refresh()
            await socialStore.refreshAll()
        }

        if forceNewsRefresh {
            await feedStore.refreshNews()
        } else {
            await feedStore.refreshNewsIfNeeded(maxAge: 60)
        }
        feedStore.markCurrentArticlesRead()
    }

    private var feedEntries: [ProfileActivityFeedEntry] {
        let newsEntries = feedStore.articles.map(ProfileActivityFeedEntry.news)
        let entries = newsEntries + friendOnlineEntries + friendAchievementEntries
        return Array(
            entries
                .sorted {
                    if $0.date != $1.date {
                        return $0.date > $1.date
                    }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                .prefix(120)
        )
    }

    private var friendOnlineEntries: [ProfileActivityFeedEntry] {
        var entriesByKey: [String: ProfileActivityFeedEntry] = [:]

        for friend in snapshot?.friends ?? [] {
            let profile = snapshot?.friendProfiles[friend.key]
            guard Self.isOnline(insigniaFriend: friend, profile: profile) else {
                continue
            }

            entriesByKey[friend.key] = ProfileActivityFeedEntry.friendOnline(
                username: friend.gamertag,
                displayName: friend.gamertag,
                currentGame: profile?.currentGame.activityTrimmedNonEmpty ?? friend.game.activityTrimmedNonEmpty,
                avatarURL: profile?.avatarURL,
                date: Self.onlineDate(profile: profile, fallback: snapshot?.loadedAt)
            )
        }

        for friend in socialStore.messageableFriends {
            let profile = socialStore.messageableFriendProfiles[friend.key]
            guard Self.isOnline(socialFriend: friend, profile: profile) else {
                continue
            }

            entriesByKey[friend.key] = ProfileActivityFeedEntry.friendOnline(
                username: friend.username,
                displayName: profile?.gamertag.activityTrimmedNonEmpty ?? friend.title,
                currentGame: profile?.currentGame.activityTrimmedNonEmpty ?? friend.currentGame.activityTrimmedNonEmpty,
                avatarURL: profile?.avatarURL ?? friend.avatarURL,
                date: Self.onlineDate(profile: profile, socialFriend: friend, fallback: snapshot?.loadedAt)
            )
        }

        return Array(entriesByKey.values)
    }

    private var friendAchievementEntries: [ProfileActivityFeedEntry] {
        var profilesByKey: [String: XBLiveFriendProfile] = [:]
        snapshot?.friendProfiles.values.forEach {
            profilesByKey[$0.gamertag.activityNormalizedKey] = $0
        }
        socialStore.messageableFriendProfiles.values.forEach {
            profilesByKey[$0.gamertag.activityNormalizedKey] = $0
        }

        return profilesByKey.values.flatMap { profile in
            (profile.achievements?.achievements ?? [])
                .filter(\.isUnlockedForDisplay)
                .compactMap { achievement -> ProfileActivityFeedEntry? in
                    guard let unlockedAt = XBLiveActivityTimestamp.date(from: achievement.unlockedAt) else {
                        return nil
                    }

                    return ProfileActivityFeedEntry.achievement(
                        username: profile.gamertag,
                        achievement: achievement,
                        avatarURL: profile.avatarURL,
                        date: unlockedAt
                    )
                }
        }
    }

    private var emptyTitle: String {
        if feedStore.newsError != nil {
            return "Activity feed unavailable"
        }
        return "No activity feed items yet"
    }

    @ViewBuilder
    private func activityFriendDestination(username: String) -> some View {
        if let friend = insigniaFriend(matching: username) {
            ProfileFriendDetailView(
                friend: friend,
                profile: insigniaProfile(for: friend),
                customProfileImage: customProfileImage(for: friend.key),
                supportedGames: snapshot?.supportedGames ?? [],
                socialStore: socialStore,
                socialFriend: socialFriend(matching: friend),
                legacyMessages: snapshot?.messages ?? [],
                markLegacyMessageViewed: profileStore.markMessageViewed,
                installedGames: installedGames,
                inviteEligibleGames: inviteEligibleGames,
                currentUserAchievements: snapshot?.achievements,
                currentUserGamesPlayed: snapshot?.playtimeGames ?? [],
                launchGameFromInvite: launchGameFromInvite,
                changeProfileImage: {
                    changeFriendProfileImage(friend)
                }
            )
        } else if let friend = socialFriend(matching: username) {
            ProfileXBLiveFriendDetailView(
                socialStore: socialStore,
                friend: friend,
                customProfileImage: customProfileImage(for: friend.key),
                supportedGames: snapshot?.supportedGames ?? [],
                legacyMessages: snapshot?.messages ?? [],
                markLegacyMessageViewed: profileStore.markMessageViewed,
                installedGames: installedGames,
                inviteEligibleGames: inviteEligibleGames,
                currentUserAchievements: snapshot?.achievements,
                currentUserGamesPlayed: snapshot?.playtimeGames ?? [],
                launchGameFromInvite: launchGameFromInvite,
                changeProfileImage: {
                    changeSocialFriendProfileImage(friend)
                }
            )
        } else {
            ProfileActivityFriendUnavailableView(username: username)
        }
    }

    private func insigniaFriend(matching username: String) -> InsigniaFriend? {
        let key = username.activityNormalizedKey
        return snapshot?.friends.first {
            $0.key == key || $0.gamertag.activityNormalizedKey == key
        }
    }

    private func socialFriend(matching username: String) -> XBLiveSocialFriend? {
        let key = username.activityNormalizedKey
        if let friend = socialStore.messageableFriends.first(where: {
            $0.key == key || $0.username.activityNormalizedKey == key || $0.title.activityNormalizedKey == key
        }) {
            return friend
        }

        guard let profile = profile(matching: username) else {
            return nil
        }

        return XBLiveSocialFriend(
            username: profile.gamertag,
            displayName: profile.gamertag,
            status: profile.lastState,
            avatarURLString: profile.avatarURLString,
            isOnline: profile.isOnline,
            currentGame: profile.currentGame,
            lastOnlineAt: profile.lastOnlineAt
        )
    }

    private func socialFriend(matching friend: InsigniaFriend) -> XBLiveSocialFriend? {
        socialStore.messageableFriends.first {
            $0.key == friend.key ||
                $0.username.activityNormalizedKey == friend.key ||
                $0.title.activityNormalizedKey == friend.key
        }
    }

    private func insigniaProfile(for friend: InsigniaFriend) -> XBLiveFriendProfile? {
        snapshot?.friendProfiles[friend.key] ??
            socialStore.messageableFriendProfiles[friend.key] ??
            snapshot?.friendProfiles.values.first {
                $0.gamertag.activityNormalizedKey == friend.key
            } ??
            socialStore.messageableFriendProfiles.values.first {
                $0.gamertag.activityNormalizedKey == friend.key
            }
    }

    private func profile(matching username: String) -> XBLiveFriendProfile? {
        let key = username.activityNormalizedKey
        return snapshot?.friendProfiles[key] ??
            socialStore.messageableFriendProfiles[key] ??
            snapshot?.friendProfiles.values.first {
                $0.gamertag.activityNormalizedKey == key
            } ??
            socialStore.messageableFriendProfiles.values.first {
                $0.gamertag.activityNormalizedKey == key
            }
    }

    private func customProfileImage(for key: String) -> UIImage? {
        profileStore.friendProfileImages[key.activityNormalizedKey]
    }

    private static func isOnline(insigniaFriend friend: InsigniaFriend, profile: XBLiveFriendProfile?) -> Bool {
        if profile?.isOnline == true || profile?.currentGame.activityTrimmedNonEmpty != nil {
            return true
        }
        return friend.isOnline || friend.game.activityTrimmedNonEmpty != nil
    }

    private static func isOnline(socialFriend friend: XBLiveSocialFriend, profile: XBLiveFriendProfile?) -> Bool {
        if profile?.isOnline == true || profile?.currentGame.activityTrimmedNonEmpty != nil {
            return true
        }
        return friend.isOnline == true || friend.currentGame.activityTrimmedNonEmpty != nil
    }

    private static func onlineDate(
        profile: XBLiveFriendProfile?,
        socialFriend: XBLiveSocialFriend? = nil,
        fallback: Date?
    ) -> Date {
        let timestamp = profile?.lastOnlineAt ??
            profile?.lastCheckedAt ??
            socialFriend?.lastOnlineAt
        if let date = XBLiveActivityTimestamp.date(from: timestamp) {
            return date
        }
        return fallback ?? Date()
    }
}

private struct ProfileActivityArticleDetailView: View {
    let article: XBLiveNewsArticle
    @ObservedObject var feedStore: XBLiveActivityFeedStore

    @State private var detail: XBLiveNewsArticle?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroImage

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if resolvedArticle.isFeatured == true {
                            Text("Featured")
                                .font(.caption.weight(.bold))
                                .textCase(.uppercase)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                        }

                        Text(XBLiveActivityTimestamp.displayText(for: resolvedArticle.publishedDate))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(resolvedArticle.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let author = resolvedArticle.readableAuthor {
                        Text("By \(author)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let summary = resolvedArticle.readableSummary {
                    Text(summary)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let bodyText = ActivityFeedHTML.plainText(from: resolvedArticle.bodyHtml),
                   !bodyText.isEmpty {
                    Text(bodyText)
                        .font(.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                } else if detail == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading article...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let url = resolvedArticle.absoluteArticleURL {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label("Open on XB.Live", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 14)
        }
        .navigationTitle("XB.Live News")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
        .task(id: article.slug) {
            detail = await feedStore.articleDetail(for: article)
        }
    }

    private var resolvedArticle: XBLiveNewsArticle {
        detail ?? article
    }

    @ViewBuilder
    private var heroImage: some View {
        if let url = resolvedArticle.absoluteHeroImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                        Image(systemName: "newspaper")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
    }
}

private struct ProfileActivityFeedRow: View {
    let entry: ProfileActivityFeedEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProfileActivityFeedThumbnail(entry: entry)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.categoryTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(entry.tint)

                    Spacer(minLength: 6)

                    Text(XBLiveActivityTimestamp.displayText(for: entry.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(minHeight: 62)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileActivityFeedThumbnail: View {
    private static let size: CGFloat = 48

    let entry: ProfileActivityFeedEntry

    var body: some View {
        Group {
            if let assetName = entry.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if let url = entry.imageURL {
                ZStack {
                    fallback
                    ProfileActivityFeedCachedRemoteImage(url: url)
                }
            } else {
                fallback
            }
        }
        .frame(width: Self.size, height: Self.size)
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(entry.tint.opacity(0.16))
            Image(systemName: entry.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(entry.tint)
        }
    }
}

private struct ProfileActivityFeedCachedRemoteImage: View {
    let url: URL

    @StateObject private var loader = ProfileActivityFeedImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            await loader.load(url)
        }
    }
}

@MainActor
private final class ProfileActivityFeedImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private var loadedURL: URL?
    private static let memoryCache = NSCache<NSURL, UIImage>()

    func load(_ url: URL) async {
        if loadedURL == url, image != nil {
            return
        }

        loadedURL = url

        if let cachedImage = Self.cachedImage(for: url) {
            image = cachedImage
            return
        }

        image = nil

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return
            }
            guard let fetchedImage = UIImage(data: data) else {
                return
            }

            Self.store(data: data, image: fetchedImage, for: url)
            if loadedURL == url {
                image = fetchedImage
            }
        } catch {
        }
    }

    private static func cachedImage(for url: URL) -> UIImage? {
        let cacheKey = url as NSURL
        if let image = memoryCache.object(forKey: cacheKey) {
            return image
        }

        let fileURL = cacheFileURL(for: url)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func store(data: Data, image: UIImage, for url: URL) {
        memoryCache.setObject(image, forKey: url as NSURL)
        try? FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheFileURL(for: url), options: .atomic)
    }

    private static var cacheDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("XB.LiveActivityFeedIcons", isDirectory: true) ??
            FileManager.default.temporaryDirectory
                .appendingPathComponent("XB.LiveActivityFeedIcons", isDirectory: true)
    }

    private static func cacheFileURL(for url: URL) -> URL {
        let encoded = Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return cacheDirectoryURL.appendingPathComponent("\(encoded).img")
    }
}

private struct ProfileActivityFriendUnavailableView: View {
    let username: String

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(username)
                        .font(.title3.weight(.semibold))

                    Text("This XB.Live friend could not be found in the current profile data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .dukeXThemedListRowBackground()
        }
        .navigationTitle("Friend")
        .navigationBarTitleDisplayMode(.inline)
        .dukeXThemedListBackground(dimming: 0.18)
    }
}

private struct ProfileActivityFeedEntry: Identifiable {
    enum Kind {
        case news
        case friendOnline
        case achievement
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let date: Date
    let categoryTitle: String
    let tint: Color
    let imageURL: URL?
    let assetName: String?
    let systemImage: String
    let article: XBLiveNewsArticle?
    let friendUsername: String?

    static func news(_ article: XBLiveNewsArticle) -> ProfileActivityFeedEntry {
        ProfileActivityFeedEntry(
            id: "news-\(article.slug)",
            kind: .news,
            title: article.title,
            subtitle: article.readableSummary,
            date: article.publishedDate ?? .distantPast,
            categoryTitle: article.isFeatured == true ? "Featured News" : "News",
            tint: .green,
            imageURL: article.absoluteHeroImageURL,
            assetName: nil,
            systemImage: "newspaper",
            article: article,
            friendUsername: nil
        )
    }

    static func friendOnline(
        username: String,
        displayName: String,
        currentGame: String?,
        avatarURL: URL?,
        date: Date
    ) -> ProfileActivityFeedEntry {
        ProfileActivityFeedEntry(
            id: "friend-online-\(username.activityNormalizedKey)",
            kind: .friendOnline,
            title: "\(displayName) is online",
            subtitle: currentGame.map { "Playing \($0)" } ?? "Online now",
            date: date,
            categoryTitle: "Friend Online",
            tint: .mint,
            imageURL: avatarURL,
            assetName: nil,
            systemImage: "person.crop.circle.fill",
            article: nil,
            friendUsername: username
        )
    }

    static func achievement(
        username: String,
        achievement: XBLiveAchievement,
        avatarURL: URL?,
        date: Date
    ) -> ProfileActivityFeedEntry {
        let gameTitle = achievement.gameTitle?.activityTrimmedNonEmpty ?? "XB.Live"
        let scoreText = achievement.score.map { " - \($0)G" } ?? ""
        let assetName = localAchievementAssetName(for: achievement)
        return ProfileActivityFeedEntry(
            id: "achievement-\(username.activityNormalizedKey)-\(achievement.id)",
            kind: .achievement,
            title: "\(username) unlocked \(achievement.title)",
            subtitle: "\(gameTitle)\(scoreText)",
            date: date,
            categoryTitle: "Achievement",
            tint: .yellow,
            imageURL: assetName == nil ? (achievement.iconURL ?? achievement.gameIconURL ?? avatarURL) : nil,
            assetName: assetName,
            systemImage: "medal.fill",
            article: nil,
            friendUsername: nil
        )
    }

    private static func localAchievementAssetName(for achievement: XBLiveAchievement) -> String? {
        let normalizedValues = [
            achievement.gameTitle,
            achievement.category,
            achievement.groupID
        ]
            .compactMap { $0?.activityTrimmedNonEmpty?.activityNormalizedTitle }

        if normalizedValues.contains("testgame") {
            return "TestGameAchievementIcon"
        }
        if normalizedValues.contains("dukexcore") {
            return "DukeXCoreAchievementIcon"
        }
        if normalizedValues.contains("xblcore") || normalizedValues.contains("xblivecore") {
            return "XBLCoreAchievementIcon"
        }
        if GameLaunchLink.normalizedTitleID(achievement.gameTitleID) == "4D53007C" ||
            normalizedValues.contains("xboxvideochat") {
            return "XboxVideoChatIcon"
        }
        return nil
    }
}

private struct XBLiveNewsArticlesResponse: Decodable {
    let articles: [XBLiveNewsArticle]
}

private struct XBLiveNewsArticleDetailResponse: Decodable {
    let article: XBLiveNewsArticle
}

private enum XBLiveActivityFeedError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "XB.Live activity feed returned HTTP \(status)."
        }
    }
}

private enum XBLiveActivityURL {
    static func absoluteURL(from rawValue: String?) -> URL? {
        guard let rawValue = rawValue?.activityTrimmedNonEmpty else {
            return nil
        }

        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }

        if rawValue.hasPrefix("//") {
            return URL(string: "https:\(rawValue)")
        }

        let trimmedPath = rawValue.hasPrefix("/") ? rawValue : "/\(rawValue)"
        return URL(string: "https://xb.live\(trimmedPath)")
    }
}

private enum XBLiveActivityTimestamp {
    static func date(from rawValue: String?) -> Date? {
        guard let rawValue = rawValue?.activityTrimmedNonEmpty else {
            return nil
        }

        if let date = isoFormatter.date(from: rawValue) {
            return date
        }
        if let date = fractionalISOFormatter.date(from: rawValue) {
            return date
        }
        if let timestamp = Double(rawValue) {
            return date(from: timestamp)
        }
        for formatter in fallbackFormatters {
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }
        return nil
    }

    static func date(from timestamp: Double?) -> Date? {
        guard let timestamp, timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp > 9_999_999_999 ? timestamp / 1_000.0 : timestamp)
    }

    static func displayText(for date: Date?) -> String {
        guard let date else {
            return "Recent"
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday, \(timeFormatter.string(from: date))"
        }
        return dateTimeFormatter.string(from: date)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy, h:mm a"
        return formatter
    }()

    private static let fallbackFormatters: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()
}

private enum ActivityFeedHTML {
    static func plainText(from html: String?) -> String? {
        guard let html = html?.activityTrimmedNonEmpty,
              let data = html.data(using: .utf8) else {
            return nil
        }

        let attributedString = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        return attributedString?.string.activityTrimmedNonEmpty
    }
}

private extension Optional where Wrapped == String {
    var activityTrimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    var activityTrimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var activityNormalizedKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var activityNormalizedTitle: String {
        lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }
}
