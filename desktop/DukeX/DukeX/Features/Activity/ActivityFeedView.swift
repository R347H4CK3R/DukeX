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

extension XBLiveNewsTag {
    var idValue: String { stableID }
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

    private var articleDetails: [String: XBLiveNewsArticle] = [:]
    private var lastNewsRefreshAt: Date?
    private let diskCache = XBLiveActivityFeedDiskCache()

    init() {
        if let cached = diskCache.load() {
            articles = cached.articles.sorted {
                ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
            }
            articleDetails = cached.articleDetails
            lastNewsRefreshAt = cached.lastNewsRefreshAt
        }
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
            persistNewsCache()
            preloadArticleImages(from: articles)
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
            persistNewsCache()
            preloadArticleImages(from: [detail])
            return detail
        } catch {
            return article
        }
    }

    private func persistNewsCache() {
        diskCache.save(
            XBLiveActivityFeedCachedPayload(
                articles: articles,
                articleDetails: articleDetails,
                lastNewsRefreshAt: lastNewsRefreshAt
            )
        )
    }

    private func preloadArticleImages(from articles: [XBLiveNewsArticle]) {
        let urls = articles.compactMap(\.absoluteHeroImageURL)
        guard !urls.isEmpty else {
            return
        }

        Task {
            await XBLiveActivityImageCache.shared.preload(urls: urls)
        }
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
        request.setValue("DukeX macOS Activity Feed", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw XBLiveActivityFeedError.httpStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}

private struct XBLiveActivityFeedCachedPayload: Codable {
    let articles: [XBLiveNewsArticle]
    let articleDetails: [String: XBLiveNewsArticle]
    let lastNewsRefreshAt: Date?
}

private struct XBLiveActivityFeedDiskCache {
    private let payloadURL: URL

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directoryURL = baseURL
            .appendingPathComponent("DukeX", isDirectory: true)
            .appendingPathComponent("ActivityFeed", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        payloadURL = directoryURL.appendingPathComponent("news-cache.json")
    }

    func load() -> XBLiveActivityFeedCachedPayload? {
        guard let data = try? Data(contentsOf: payloadURL) else {
            return nil
        }
        return try? JSONDecoder().decode(XBLiveActivityFeedCachedPayload.self, from: data)
    }

    func save(_ payload: XBLiveActivityFeedCachedPayload) {
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        try? data.write(to: payloadURL, options: [.atomic])
    }
}

@MainActor
private final class XBLiveActivityImageCache {
    static let shared = XBLiveActivityImageCache()

    private var inMemoryImages: [URL: UIImage] = [:]
    private let directoryURL: URL
    private let fileManager: FileManager

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = baseURL
            .appendingPathComponent("DukeX", isDirectory: true)
            .appendingPathComponent("ActivityFeed", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        if let image = inMemoryImages[url] {
            return image
        }

        let fileURL = cacheFileURL(for: url)
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            inMemoryImages[url] = image
            return image
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("DukeX macOS Activity Feed", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else {
                return nil
            }

            inMemoryImages[url] = image
            try? data.write(to: fileURL, options: [.atomic])
            return image
        } catch {
            return nil
        }
    }

    func preload(urls: [URL]) async {
        for url in urls {
            _ = await image(for: url)
        }
    }

    private func cacheFileURL(for url: URL) -> URL {
        let fileName = Self.cacheFileName(for: url)
        return directoryURL.appendingPathComponent(fileName)
    }

    private static func cacheFileName(for url: URL) -> String {
        let encoded = Data(url.absoluteString.utf8).base64EncodedString()
        let safeName = encoded
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "\(safeName).img"
    }
}

struct ActivityFeedFriendTarget: Identifiable, Equatable {
    let username: String

    var id: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct ActivityFeedView: View {
    @ObservedObject var feedStore: XBLiveActivityFeedStore
    @ObservedObject var profileStore: InsigniaProfileStore
    @ObservedObject var socialStore: XBLiveSocialStore
    @Binding var width: Double
    @Binding var isExpanded: Bool

    let openFriend: (String) -> Void

    @State private var selectedArticle: XBLiveNewsArticle?

    private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    private let headerTopSpacerHeight: CGFloat = 24

    var body: some View {
        Group {
            if isExpanded {
                expandedToolbox
            } else {
                collapsedToolboxButton
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: isExpanded)
        .task {
            await feedStore.refreshNewsIfNeeded(maxAge: 900)
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await feedStore.refreshNewsIfNeeded()
            }
        }
        .sheet(item: $selectedArticle) { article in
            NavigationStack {
                ActivityArticleReaderView(article: article, feedStore: feedStore)
            }
            .frame(minWidth: 780, idealWidth: 860, minHeight: 720, idealHeight: 780)
        }
    }

    private var expandedToolbox: some View {
        VStack(spacing: 0) {
            toolboxChrome

            Divider()
                .overlay(Color.primary.opacity(0.08))

            feedContent
        }
        .frame(width: CGFloat(width))
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.20))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.leading, 8)
        .padding(.top, 0)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var collapsedToolboxButton: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                toggleToolboxButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.20))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
            }

            Spacer(minLength: 0)
        }
        .frame(width: CGFloat(width))
        .frame(maxHeight: .infinity)
        .padding(.leading, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    private var toolboxChrome: some View {
        VStack(spacing: 10) {
            Color.clear
                .frame(height: headerTopSpacerHeight)

            HStack(spacing: 10) {
                toggleToolboxButton

                Text("Activity Feed")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    Task {
                        await feedStore.refreshNews()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(feedStore.isLoadingNews)
                .accessibilityLabel("Refresh Activity Feed")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var toggleToolboxButton: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide Activity Feed" : "Show Activity Feed")
        .accessibilityHint("Collapses or reveals the XB.Live activity feed toolbox")
    }

    private var feedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text("XB.Live")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(feedEntries.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if feedStore.isLoadingNews && feedEntries.isEmpty {
                        ActivityFeedLoadingRow()
                    }

                    if let newsError = feedStore.newsError, feedEntries.isEmpty {
                        ActivityFeedEmptyRow(title: "Activity feed unavailable",
                                             subtitle: newsError,
                                             systemImage: "exclamationmark.triangle")
                    } else if feedEntries.isEmpty {
                        ActivityFeedEmptyRow(title: "No activity yet",
                                             subtitle: "XB.Live posts and friend activity will appear here.",
                                             systemImage: "list.bullet.rectangle")
                    } else {
                        ForEach(feedEntries) { entry in
                            ActivityFeedEntryRow(
                                entry: entry,
                                action: entry.isInteractive ? { handleSelection(entry) } : nil
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var feedEntries: [ActivityFeedEntry] {
        let newsEntries = feedStore.articles.map(ActivityFeedEntry.news)
        let liveEntries = friendOnlineEntries
        let achievementEntries = friendAchievementEntries

        return (newsEntries + liveEntries + achievementEntries)
            .sorted {
                if $0.date != $1.date {
                    return $0.date > $1.date
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(120)
            .map { $0 }
    }

    private var friendOnlineEntries: [ActivityFeedEntry] {
        var entriesByKey: [String: ActivityFeedEntry] = [:]
        let snapshot = profileStore.authenticatedSnapshot

        for friend in snapshot?.friends ?? [] {
            let profile = snapshot?.friendProfiles[friend.key]
            guard Self.isOnline(insigniaFriend: friend, profile: profile) else {
                continue
            }

            let entry = ActivityFeedEntry.friendOnline(
                username: friend.gamertag,
                displayName: friend.gamertag,
                currentGame: profile?.currentGame.activityTrimmedNonEmpty ?? friend.game.activityTrimmedNonEmpty,
                avatarURL: profile?.avatarURL,
                profileImage: customProfileImage(for: friend.key),
                date: Self.onlineDate(profile: profile, fallback: snapshot?.loadedAt)
            )
            entriesByKey[friend.key] = entry
        }

        for friend in socialStore.messageableFriends {
            let profile = socialStore.messageableFriendProfiles[friend.key]
            guard Self.isOnline(socialFriend: friend, profile: profile) else {
                continue
            }

            let entry = ActivityFeedEntry.friendOnline(
                username: friend.username,
                displayName: profile?.gamertag.activityTrimmedNonEmpty ?? friend.title,
                currentGame: profile?.currentGame.activityTrimmedNonEmpty ?? friend.currentGame.activityTrimmedNonEmpty,
                avatarURL: profile?.avatarURL ?? friend.avatarURL,
                profileImage: customProfileImage(for: friend.key) ??
                    customProfileImage(for: friend.username) ??
                    profile.flatMap { customProfileImage(for: $0.gamertag) },
                date: Self.onlineDate(profile: profile, socialFriend: friend, fallback: snapshot?.loadedAt)
            )
            entriesByKey[friend.key] = entry
        }

        return Array(entriesByKey.values)
    }

    private var friendAchievementEntries: [ActivityFeedEntry] {
        var profilesByKey: [String: XBLiveFriendProfile] = [:]
        profileStore.authenticatedSnapshot?.friendProfiles.values.forEach {
            profilesByKey[$0.gamertag.activityNormalizedKey] = $0
        }
        socialStore.messageableFriendProfiles.values.forEach {
            profilesByKey[$0.gamertag.activityNormalizedKey] = $0
        }

        return profilesByKey.values.flatMap { profile in
            (profile.achievements?.achievements ?? [])
                .filter(\.isUnlockedForDisplay)
                .compactMap { achievement -> ActivityFeedEntry? in
                    guard let unlockedAt = XBLiveActivityTimestamp.date(from: achievement.unlockedAt) else {
                        return nil
                    }

                    return ActivityFeedEntry.achievement(
                        username: profile.gamertag,
                        achievement: achievement,
                        iconDisplay: achievementIconDisplay(for: achievement),
                        profileImage: customProfileImage(for: profile.gamertag),
                        date: unlockedAt
                    )
                }
        }
    }

    private func achievementIconDisplay(for achievement: XBLiveAchievement) -> ActivityFeedIconDisplay {
        let supportedGame = supportedGame(for: achievement)
        let title = supportedGame?.title ?? achievement.gameTitle
        let titleID = supportedGame?.titleID ?? achievement.gameTitleID
        let primaryURL = XboxTitleIconCatalog.iconURL(for: titleID) ??
            playedGame(for: achievement, supportedGame: supportedGame)?.imageURL ??
            achievement.gameIconURL
        return ActivityFeedIconDisplayResolver.display(
            title: title,
            titleID: titleID,
            achievement: achievement,
            primaryURL: primaryURL
        )
    }

    private func supportedGame(for achievement: XBLiveAchievement) -> InsigniaSupportedGame? {
        guard let titleID = achievement.gameTitleID?.uppercased().activityTrimmedNonEmpty else {
            return nil
        }
        return profileStore.authenticatedSnapshot?.supportedGames.first {
            $0.titleID.uppercased() == titleID
        }
    }

    private func playedGame(
        for achievement: XBLiveAchievement,
        supportedGame: InsigniaSupportedGame?
    ) -> XBLiveGamePlayed? {
        let titleIDs = Set([
            achievement.gameTitleID?.uppercased().activityTrimmedNonEmpty,
            supportedGame?.titleID.uppercased().activityTrimmedNonEmpty
        ].compactMap { $0 })
        if let game = profileStore.authenticatedSnapshot?.playtimeGames.first(where: { game in
            guard let titleID = game.titleId?.uppercased().activityTrimmedNonEmpty else {
                return false
            }
            return titleIDs.contains(titleID)
        }) {
            return game
        }

        guard let normalizedTitle = achievement.gameTitle.activityTrimmedNonEmpty.map(Self.normalizedTitle) else {
            return nil
        }
        return profileStore.authenticatedSnapshot?.playtimeGames.first {
            Self.normalizedTitle($0.gameName) == normalizedTitle
        }
    }

    private func customProfileImage(for key: String) -> UIImage? {
        profileStore.friendProfileImages[key.activityNormalizedKey]
    }

    private func handleSelection(_ entry: ActivityFeedEntry) {
        switch entry.kind {
        case .news:
            selectedArticle = entry.article
        case .friendOnline:
            if let friendUsername = entry.friendUsername {
                openFriend(friendUsername)
            }
        case .achievement:
            break
        }
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
        if let timestamp {
            return XBLiveActivityTimestamp.date(from: timestamp)
        }
        return fallback ?? Date()
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }
}

private struct ActivityArticleReaderView: View {
    @Environment(\.dismiss) private var dismiss

    let article: XBLiveNewsArticle
    @ObservedObject var feedStore: XBLiveActivityFeedStore

    @State private var detail: XBLiveNewsArticle?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                        .foregroundStyle(.primary)
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
                    ActivityArticleBodyText(bodyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else if detail == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading article...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if !resolvedArticle.tags.isEmpty {
                    tagRow
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
            .padding(.vertical, 24)
            .padding(.horizontal, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 720, idealHeight: 780)
        .background {
            DukeXThemedBackgroundView(dimming: 0.20)
        }
        .navigationTitle("XB.Live News")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
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
            ActivityFeedCachedImage(url: url, contentMode: .fit, placeholderAspectRatio: 16.0 / 9.0) {
                ActivityArticleImagePlaceholder()
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private var tagRow: some View {
        FlowLayout(spacing: 8) {
            ForEach(resolvedArticle.tags, id: \.idValue) { tag in
                if let label = tag.label?.activityTrimmedNonEmpty {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.13), in: Capsule())
                }
            }
        }
    }
}

private struct ActivityArticleBodyText: UIViewRepresentable {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.attributedText = Self.attributedString(from: text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }

        let size = uiView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(size.height))
    }

    private static func attributedString(from text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 10

        return NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}

struct ActivityFeedFriendDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dukeXTheme) private var theme

    let username: String
    @ObservedObject var profileStore: InsigniaProfileStore
    @ObservedObject var socialStore: XBLiveSocialStore
    let installedGames: [LibraryFile]
    let inviteEligibleGames: [LibraryFile]
    let launchGameFromInvite: (LibraryFile) -> Void
    let changeFriendProfileImage: (InsigniaFriend) -> Void
    let changeSocialFriendProfileImage: (XBLiveSocialFriend) -> Void

    var body: some View {
        Group {
            if let friend = insigniaFriend {
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
            } else if let friend = socialFriend {
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
                ActivityFeedFriendUnavailableView(username: username)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .tint(theme.accentColor)
        .accentColor(theme.accentColor)
        .task(id: username) {
            profileStore.refresh()
            if profileStore.session?.isAuthenticated == true {
                await socialStore.refreshAll()
            }
        }
    }

    private var snapshot: InsigniaAuthenticatedSnapshot? {
        profileStore.authenticatedSnapshot
    }

    private var normalizedUsername: String {
        username.activityNormalizedKey
    }

    private var insigniaFriend: InsigniaFriend? {
        snapshot?.friends.first {
            $0.key == normalizedUsername ||
                $0.gamertag.activityNormalizedKey == normalizedUsername
        }
    }

    private var socialFriend: XBLiveSocialFriend? {
        if let friend = socialStore.messageableFriends.first(where: {
            $0.key == normalizedUsername ||
                $0.title.activityNormalizedKey == normalizedUsername
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
            profileStore.authenticatedSnapshot?.friendProfiles.values.first {
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
}

private struct ActivityFeedFriendUnavailableView: View {
    let username: String

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 54, weight: .semibold))
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

private struct ActivityFeedEntryRow: View {
    let entry: ActivityFeedEntry
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                rowContent(showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(showsChevron: false)
        }
    }

    private func rowContent(showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ActivityFeedThumbnail(entry: entry)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.categoryTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(entry.tint)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(XBLiveActivityTimestamp.displayText(for: entry.date))
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.65))
                    .padding(.top, 22)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(entry.tint.opacity(0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(entry.tint.opacity(0.20), lineWidth: 1)
        }
    }
}

private struct ActivityFeedThumbnail: View {
    let entry: ActivityFeedEntry

    var body: some View {
        ZStack {
            if let imageAssetName = entry.imageAssetName {
                Image(imageAssetName)
                    .resizable()
                    .scaledToFill()
            } else if let profileImage = entry.profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL = entry.imageURL {
                ActivityFeedCachedImage(url: imageURL, contentMode: .fill, placeholderAspectRatio: nil) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(entry.tint.opacity(0.24), lineWidth: 1)
        }
    }

    private var placeholder: some View {
        ZStack {
            entry.tint.opacity(0.14)
            Image(systemName: entry.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(entry.tint)
        }
    }
}

private struct ActivityFeedCachedImage<Placeholder: View>: View {
    let url: URL
    let contentMode: ContentMode
    let placeholderAspectRatio: CGFloat?
    @ViewBuilder let placeholder: Placeholder

    @State private var image: UIImage?
    @State private var loadTaskURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.activityAspectRatio, contentMode: contentMode)
            } else {
                placeholderView
            }
        }
        .task(id: url) {
            guard loadTaskURL != url || image == nil else {
                return
            }
            loadTaskURL = url
            image = await XBLiveActivityImageCache.shared.image(for: url)
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let placeholderAspectRatio {
            placeholder
                .aspectRatio(placeholderAspectRatio, contentMode: .fit)
        } else {
            placeholder
        }
    }
}

private struct ActivityFeedLoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading XB.Live activity...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ActivityFeedEmptyRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ActivityArticleImagePlaceholder: View {
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.16)
            Image(systemName: "newspaper")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ActivityFeedEntry: Identifiable {
    enum Kind {
        case news
        case friendOnline
        case achievement
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let categoryTitle: String
    let date: Date
    let imageURL: URL?
    let imageAssetName: String?
    let profileImage: UIImage?
    let systemImage: String
    let tint: Color
    let article: XBLiveNewsArticle?
    let friendUsername: String?

    var isInteractive: Bool {
        kind != .achievement
    }

    static func news(_ article: XBLiveNewsArticle) -> ActivityFeedEntry {
        ActivityFeedEntry(
            id: "news-\(article.slug)",
            kind: .news,
            title: article.title,
            subtitle: article.readableSummary,
            categoryTitle: article.isFeatured == true ? "Featured News" : "News",
            date: article.publishedDate ?? .distantPast,
            imageURL: article.absoluteHeroImageURL,
            imageAssetName: nil,
            profileImage: nil,
            systemImage: "newspaper",
            tint: Color.accentColor,
            article: article,
            friendUsername: nil
        )
    }

    static func friendOnline(
        username: String,
        displayName: String,
        currentGame: String?,
        avatarURL: URL?,
        profileImage: UIImage?,
        date: Date
    ) -> ActivityFeedEntry {
        ActivityFeedEntry(
            id: "friend-online-\(username.activityNormalizedKey)",
            kind: .friendOnline,
            title: "\(displayName) is online",
            subtitle: currentGame.map { "Playing \($0)" },
            categoryTitle: "Friend Online",
            date: date,
            imageURL: avatarURL,
            imageAssetName: nil,
            profileImage: profileImage,
            systemImage: "person.crop.circle.badge.checkmark",
            tint: .green,
            article: nil,
            friendUsername: username
        )
    }

    static func achievement(
        username: String,
        achievement: XBLiveAchievement,
        iconDisplay: ActivityFeedIconDisplay,
        profileImage: UIImage?,
        date: Date
    ) -> ActivityFeedEntry {
        let score = achievement.score.map { "\($0)G" }
        let subtitle = [
            achievement.gameTitle?.activityTrimmedNonEmpty,
            score
        ]
            .compactMap { $0 }
            .joined(separator: " - ")
            .activityTrimmedNonEmpty

        return ActivityFeedEntry(
            id: "achievement-\(username.activityNormalizedKey)-\(achievement.id)-\(Int(date.timeIntervalSince1970))",
            kind: .achievement,
            title: "\(username) unlocked \(achievement.title)",
            subtitle: subtitle,
            categoryTitle: "Achievement",
            date: date,
            imageURL: iconDisplay.assetName == nil ? iconDisplay.url : nil,
            imageAssetName: iconDisplay.assetName,
            profileImage: iconDisplay.assetName == nil && iconDisplay.url == nil ? profileImage : nil,
            systemImage: iconDisplay.systemImage,
            tint: .yellow,
            article: nil,
            friendUsername: username
        )
    }
}

private struct ActivityFeedIconDisplay {
    let url: URL?
    let assetName: String?
    let systemImage: String
}

private enum ActivityFeedIconDisplayResolver {
    static func display(
        title: String?,
        titleID: String?,
        achievement: XBLiveAchievement,
        primaryURL: URL?
    ) -> ActivityFeedIconDisplay {
        let normalizedTitleID = GameLaunchLink.normalizedTitleID(titleID)
        let normalizedValues = [
            title,
            achievement.groupID,
            achievement.gameTitle,
            achievement.category
        ]
            .compactMap { value -> String? in
                guard let value = value?.activityTrimmedNonEmpty else {
                    return nil
                }
                return normalizedTitle(value)
            }

        if normalizedValues.contains("testgame") {
            return ActivityFeedIconDisplay(url: nil, assetName: "TestGameAchievementIcon", systemImage: "gamecontroller")
        }
        if normalizedValues.contains("dukexcore") {
            return ActivityFeedIconDisplay(url: nil, assetName: "DukeXCoreAchievementIcon", systemImage: "gamecontroller")
        }
        if normalizedValues.contains("xblcore") || normalizedValues.contains("xblivecore") {
            return ActivityFeedIconDisplay(url: nil, assetName: "XBLCoreAchievementIcon", systemImage: "network")
        }
        if normalizedTitleID == "4D53007C" || normalizedValues.contains("xboxvideochat") {
            return ActivityFeedIconDisplay(url: nil, assetName: "XboxVideoChatIcon", systemImage: "video.circle")
        }
        if normalizedTitleID == "FFFE0000" || normalizedValues.contains("xboxlivedashboard") {
            return ActivityFeedIconDisplay(url: nil, assetName: "XboxLiveDashboardIcon", systemImage: "network")
        }
        return ActivityFeedIconDisplay(url: primaryURL, assetName: nil, systemImage: "medal")
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
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
            return "XB.Live returned HTTP \(status)."
        }
    }
}

private enum XBLiveActivityURL {
    static func absoluteURL(from rawValue: String?) -> URL? {
        guard let value = rawValue?.activityTrimmedNonEmpty else {
            return nil
        }

        if var components = URLComponents(string: value),
           components.scheme != nil {
            if components.scheme == "http" {
                components.scheme = "https"
            }
            return components.url
        }

        return URL(string: value, relativeTo: URL(string: "https://xb.live"))?.absoluteURL
    }
}

private enum XBLiveActivityTimestamp {
    static func date(from rawValue: String?) -> Date? {
        guard let rawValue = rawValue?.activityTrimmedNonEmpty else {
            return nil
        }

        if let timestamp = Double(rawValue) {
            return date(from: timestamp)
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: rawValue) {
            return date
        }

        for formatter in fallbackFormatters {
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        return nil
    }

    static func date(from timestamp: Double) -> Date {
        let normalizedTimestamp = timestamp > 9_999_999_999 ? timestamp / 1_000 : timestamp
        return Date(timeIntervalSince1970: normalizedTimestamp)
    }

    static func displayText(for date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }
        return displayFormatter.string(from: date)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
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

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        let attributedString = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        )

        return attributedString?.string
            .replacingOccurrences(of: "\u{fffc}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

private extension UIImage {
    var activityAspectRatio: CGFloat {
        guard size.width > 0, size.height > 0 else {
            return 16.0 / 9.0
        }
        return size.width / size.height
    }
}
