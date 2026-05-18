import Foundation

enum GameLibraryFavorites {
    static let defaultsKey = "DukeXFavoriteGameKeys"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    static func save(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys).sorted(), forKey: defaultsKey)
    }

    static func key(for game: LibraryFile) -> String {
        game.libraryIdentityKey
    }
}

enum GameLibraryRecents {
    static let defaultsKey = "DukeXRecentlyPlayedGameTimes"

    static func load() -> [String: TimeInterval] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: TimeInterval] ?? [:]
    }

    static func save(_ times: [String: TimeInterval]) {
        UserDefaults.standard.set(times, forKey: defaultsKey)
    }
}
