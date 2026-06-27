import Foundation

enum GameLibrarySortMode: String, CaseIterable, Identifiable {
    case favorites
    case title
    case live
    case recent

    static let defaultsKey = "DukeXGameLibrarySortMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites:
            return "Favorites"
        case .title:
            return "Title"
        case .live:
            return "Live"
        case .recent:
            return "Recent"
        }
    }
}
