import Foundation

enum ESRBRating: String, CaseIterable, Codable, Identifiable {
    case none
    case earlyChildhood
    case everyone
    case everyone10
    case teen
    case mature17
    case adultsOnly18
    case ratingPending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .earlyChildhood:
            return "Early Childhood"
        case .everyone:
            return "Everyone"
        case .everyone10:
            return "Everyone 10+"
        case .teen:
            return "Teen"
        case .mature17:
            return "Mature 17+"
        case .adultsOnly18:
            return "Adults Only 18+"
        case .ratingPending:
            return "Rating Pending"
        }
    }

    var shortTitle: String {
        switch self {
        case .none:
            return "None"
        case .earlyChildhood:
            return "EC"
        case .everyone:
            return "E"
        case .everyone10:
            return "E10+"
        case .teen:
            return "T"
        case .mature17:
            return "M"
        case .adultsOnly18:
            return "AO"
        case .ratingPending:
            return "RP"
        }
    }

    var assetName: String? {
        switch self {
        case .none:
            return nil
        case .earlyChildhood:
            return "ESRB_EC"
        case .everyone:
            return "ESRB_E"
        case .everyone10:
            return "ESRB_E10"
        case .teen:
            return "ESRB_T"
        case .mature17:
            return "ESRB_M"
        case .adultsOnly18:
            return "ESRB_AO"
        case .ratingPending:
            return "ESRB_RP"
        }
    }
}

struct GameListMetadata: Codable, Equatable {
    var title: String
    var subtitle: String
    var year: String
    var studio: String
    var esrbRating: ESRBRating
    var description: String

    static let empty = GameListMetadata(
        title: "",
        subtitle: "",
        year: "",
        studio: "",
        esrbRating: .none,
        description: ""
    )

    init(title: String,
         subtitle: String = "",
         year: String,
         studio: String,
         esrbRating: ESRBRating,
         description: String) {
        self.title = title
        self.subtitle = subtitle
        self.year = year
        self.studio = studio
        self.esrbRating = esrbRating
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        year = try container.decode(String.self, forKey: .year)
        studio = try container.decode(String.self, forKey: .studio)
        esrbRating = try container.decode(ESRBRating.self, forKey: .esrbRating)
        description = try container.decode(String.self, forKey: .description)
    }

    var studioYearLine: String? {
        let parts = [year, studio]
            .compactMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var normalizedForStorage: GameListMetadata {
        GameListMetadata(
            title: title.normalizedField,
            subtitle: subtitle.normalizedField,
            year: year.normalizedField,
            studio: studio.normalizedField,
            esrbRating: esrbRating,
            description: description.normalizedField
        )
    }

    var hasVisibleContent: Bool {
        !title.normalizedField.isEmpty ||
            !subtitle.normalizedField.isEmpty ||
            !year.normalizedField.isEmpty ||
            !studio.normalizedField.isEmpty ||
            esrbRating != .none ||
            !description.normalizedField.isEmpty
    }
}

@MainActor
final class GameMetadataStore: ObservableObject {
    @Published private(set) var metadataByGameKey: [String: GameListMetadata] = [:]

    private static let cacheKey = "DukeXGameMetadataCache"

    init() {
        metadataByGameKey = Self.loadCache()
    }

    func metadata(for game: LibraryFile) -> GameListMetadata? {
        metadataByGameKey[cacheKey(for: game)]
    }

    func setMetadata(_ metadata: GameListMetadata, for game: LibraryFile) {
        let key = cacheKey(for: game)
        let normalized = metadata.normalizedForStorage

        if normalized.hasVisibleContent {
            metadataByGameKey[key] = normalized
        } else {
            metadataByGameKey.removeValue(forKey: key)
        }

        Self.saveCache(metadataByGameKey)
    }

    private func cacheKey(for game: LibraryFile) -> String {
        game.libraryIdentityKey
    }

    private static func loadCache() -> [String: GameListMetadata] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: GameListMetadata].self, from: data) else {
            return [:]
        }
        return cache
    }

    private static func saveCache(_ cache: [String: GameListMetadata]) {
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

private extension String {
    var normalizedField: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
