import Combine
import Foundation

struct InsigniaLiveStatusSnapshot: Codable, Equatable {
    let supportedGames: [InsigniaSupportedGame]
    let activeGames: [InsigniaActiveGame]
}

struct GameLiveStatus: Equatable {
    let isSupported: Bool
    let hasPlayersOnline: Bool
    let onlineUsersText: String?
}

@MainActor
final class InsigniaLiveStatusStore: ObservableObject {
    @Published private(set) var snapshot: InsigniaLiveStatusSnapshot?
    @Published private(set) var isRefreshing = false

    private static let snapshotKey = "InsigniaLiveStatusSnapshot"

    init() {
        snapshot = Self.loadSnapshot()
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        Task { @MainActor in
            do {
                let snapshot = try await InsigniaPublicService.fetchLiveStatusSnapshot()
                self.snapshot = snapshot
                Self.saveSnapshot(snapshot)
            } catch {
            }

            isRefreshing = false
        }
    }

    func status(for game: LibraryFile) -> GameLiveStatus? {
        guard let snapshot else {
            return nil
        }

        let gameTitleID = Self.normalizedTitleID(game.titleID)
        let gameTitleKey = Self.normalizedTitle(game.displayName)
        let gameFallbackKey = Self.normalizedTitle(game.fallbackDisplayName)

        let supportedGame = snapshot.supportedGames.first { supportedGame in
            if !gameTitleID.isEmpty, Self.normalizedTitleID(supportedGame.titleID) == gameTitleID {
                return true
            }

            let supportedTitleKey = Self.normalizedTitle(supportedGame.title)
            let supportedSubtitleKey = Self.normalizedTitle(supportedGame.subtitle)
            return Self.matchesTitle(gameTitleKey, supportedTitleKey, supportedSubtitleKey) ||
                Self.matchesTitle(gameFallbackKey, supportedTitleKey, supportedSubtitleKey)
        }

        guard supportedGame != nil else {
            return nil
        }

        let activeGame = snapshot.activeGames.first { activeGame in
            if !gameTitleID.isEmpty, Self.normalizedTitleID(activeGame.titleID) == gameTitleID {
                return true
            }

            let activeTitleKey = Self.normalizedTitle(activeGame.title)
            return Self.matchesTitle(gameTitleKey, activeTitleKey) ||
                Self.matchesTitle(gameFallbackKey, activeTitleKey)
        }
        let onlineUsers = activeGame?.onlineUsersCount ?? 0

        return GameLiveStatus(
            isSupported: true,
            hasPlayersOnline: onlineUsers > 0,
            onlineUsersText: activeGame?.onlineUsers
        )
    }

    private static func loadSnapshot() -> InsigniaLiveStatusSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(InsigniaLiveStatusSnapshot.self, from: data)
    }

    private static func saveSnapshot(_ snapshot: InsigniaLiveStatusSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    private static func normalizedTitleID(_ value: String?) -> String {
        guard let value else {
            return ""
        }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func matchesTitle(_ candidate: String, _ knownTitles: String...) -> Bool {
        !candidate.isEmpty && knownTitles.contains(candidate)
    }
}

private extension InsigniaActiveGame {
    var titleID: String? {
        serial.firstMatch(for: #"[0-9A-Fa-f]{8}"#)?.uppercased()
    }

    var onlineUsersCount: Int {
        Int(onlineUsers.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

private extension String {
    func firstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              let matchRange = Range(match.range, in: self) else {
            return nil
        }
        return String(self[matchRange])
    }
}
