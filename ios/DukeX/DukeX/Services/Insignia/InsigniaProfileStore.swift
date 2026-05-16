import Foundation
import SafariServices
import SwiftUI
import UIKit

struct InsigniaProfileSession: Equatable {
    let gamertag: String
    let signedInAt: Date
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

    private static func firstStatistic(named label: String, in html: String) -> String? {
        let pattern = "<h3>\\s*([0-9,]+)\\s*</h3>\\s*<p>\\s*\(NSRegularExpression.escapedPattern(for: label))\\s*</p>"
        return firstMatch(pattern: pattern, in: html).first
    }

    private static func activeGames(from html: String) -> [InsigniaActiveGame] {
        let pattern = #"<tr>\s*<td>\s*<a href="[^"]+">\s*<img[\s\S]*?</a>\s*<a href="[^"]+">([\s\S]*?)</a>\s*<br />\s*<small[^>]*>([\s\S]*?)</small>\s*</td>\s*<td>\s*([\s\S]*?)<br />\s*<small[^>]*>([\s\S]*?)</small>\s*</td>\s*<td[^>]*>\s*([0-9]+)\s*</td>\s*<td[^>]*>\s*([\s\S]*?)\s*</td>"#

        return matches(pattern: pattern, in: html)
            .prefix(8)
            .compactMap { captures -> InsigniaActiveGame? in
                guard captures.count == 6 else {
                    return nil
                }

                let title = cleanedHTML(captures[0])
                let subtitle = cleanedHTML(captures[1])
                let publisherCode = cleanedHTML(captures[2])
                let titleID = cleanedHTML(captures[3])
                let onlineUsers = cleanedHTML(captures[4])
                let activePlayers = cleanedHTML(captures[5])
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
                    detail: detail
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

    enum ServiceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Insignia service metadata is unavailable."
        }
    }
}

@MainActor
final class InsigniaProfileStore: ObservableObject {
    @Published private(set) var session: InsigniaProfileSession?
    @Published private(set) var publicSnapshot: InsigniaPublicSnapshot?
    @Published private(set) var profileImage: UIImage?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var isRefreshing = false

    private static let gamertagKey = "InsigniaProfileGamertag"
    private static let signedInAtKey = "InsigniaProfileSignedInAt"
    private static let lastRefreshedKey = "InsigniaProfileLastRefreshedAt"
    private static let publicSnapshotKey = "InsigniaPublicSnapshot"
    private static let profileImageFileName = "profile-picture.jpg"

    var isSignedIn: Bool {
        session != nil
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

    var lastRefreshedText: String {
        guard let lastRefreshed else {
            return "Never"
        }

        return lastRefreshed.formatted(date: .omitted, time: .shortened)
    }

    init() {
        let defaults = UserDefaults.standard
        if let gamertag = defaults.string(forKey: Self.gamertagKey), !gamertag.isEmpty {
            let signedInAt = defaults.object(forKey: Self.signedInAtKey) as? Date ?? Date()
            session = InsigniaProfileSession(gamertag: gamertag, signedInAt: signedInAt)
        }
        lastRefreshed = defaults.object(forKey: Self.lastRefreshedKey) as? Date
        publicSnapshot = Self.loadPublicSnapshot()
        loadProfileImage()
    }

    func signIn(gamertag: String) throws {
        let trimmed = gamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProfileSignInError.missingGamertag
        }

        let signedInAt = Date()
        session = InsigniaProfileSession(gamertag: trimmed, signedInAt: signedInAt)
        lastRefreshed = nil

        let defaults = UserDefaults.standard
        defaults.set(trimmed, forKey: Self.gamertagKey)
        defaults.set(signedInAt, forKey: Self.signedInAtKey)
        defaults.removeObject(forKey: Self.lastRefreshedKey)
    }

    func signOut() {
        session = nil
        lastRefreshed = nil
        isRefreshing = false

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.gamertagKey)
        defaults.removeObject(forKey: Self.signedInAtKey)
        defaults.removeObject(forKey: Self.lastRefreshedKey)
    }

    func assignProfileImage(_ data: Data) throws {
        let image = UIImage(data: data)
        let imageData = image?.jpegData(compressionQuality: 0.9) ?? data
        try FileManager.default.createDirectory(at: profileDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try imageData.write(to: profileImageURL, options: .atomic)
        profileImage = UIImage(data: imageData)
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
            do {
                let snapshot = try await InsigniaPublicService.fetchPublicSnapshot()
                publicSnapshot = snapshot
                Self.savePublicSnapshot(snapshot)

                let refreshedAt = Date()
                lastRefreshed = refreshedAt
                UserDefaults.standard.set(refreshedAt, forKey: Self.lastRefreshedKey)
            } catch {
            }

            isRefreshing = false
        }
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

    private var profileDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Profile", isDirectory: true)
    }

    private var profileImageURL: URL {
        profileDirectoryURL.appendingPathComponent(Self.profileImageFileName)
    }

    private func loadProfileImage() {
        guard let data = try? Data(contentsOf: profileImageURL) else {
            profileImage = nil
            return
        }
        profileImage = UIImage(data: data)
    }
}

private enum ProfileSignInError: LocalizedError {
    case missingGamertag

    var errorDescription: String? {
        switch self {
        case .missingGamertag:
            return "Enter a gamertag to continue."
        }
    }
}
