import SwiftUI

enum GameLibraryGridMetrics {
    static let compactControlHeight: CGFloat = 43

    static func spacing(for columnCount: Int) -> CGFloat {
        switch columnCount {
        case 8:
            return 8
        case 6...7:
            return 10
        case 4...5:
            return 12
        case 3:
            return 10
        default:
            return 12
        }
    }

    static func columns(for columnCount: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: spacing(for: columnCount)),
            count: columnCount
        )
    }
}
